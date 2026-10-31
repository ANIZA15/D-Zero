#import "Zero3DEngineTexture.h"
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static const int kTripleBufferCount = 4;

typedef struct {
    float resolution[2];
    float timeSec;
    float cameraYaw;
    float cameraPitch;
    float cameraDist;
    float cameraFov;
    float lightAzimuth;
    float lightElevation;
    float lodThreshold;
    int32_t renderMode;
    int32_t maxRayBounces;
    float heroPosScale[4];
    float cameraTarget[4];
    float pbrParams[4];
    float postProcess[4];
} Zero3DGpuUniforms;

static NSString *const kZero3DMetalShaderSource = @R"(
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float timeSec;
    float cameraYaw;
    float cameraPitch;
    float cameraDist;
    float cameraFov;
    float lightAzimuth;
    float lightElevation;
    float lodThreshold;
    int renderMode;
    int maxRayBounces;
    float4 heroPosScale;
    float4 cameraTarget;
    float4 pbrParams;   // x: metallic, y: roughness, z: emissive, w: physicsEnabled
    float4 postProcess; // x: fogDensity, y: exposureEv, z: bloomIntensity, w: sequencerTime
};

float sdOctahedron(float3 p, float s) {
    p = abs(p);
    return (p.x + p.y + p.z - s) * 0.57735027;
}

float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Scene SDF with Material / Cluster ID
float2 mapScene(float3 p, float t, float4 heroPosScale) {
    float dFloor = p.y + 1.05;
    float2 res = float2(dFloor, 1.0);

    float3 q = p - float3(0.0, 0.1 * sin(t * 1.4), 0.0);
    float dCore = sdTorus(q, float2(0.82, 0.26));
    if (dCore < res.x) res = float2(dCore, 2.0);

    float heroScale = max(heroPosScale.w, 0.2);
    float dOct = sdOctahedron(p - heroPosScale.xyz, 0.55 * heroScale);
    if (dOct < res.x) res = float2(dOct, 3.0);

    for (int i = 0; i < 4; ++i) {
        float ang = t * 0.7 + float(i) * 1.5707963;
        float3 sp = p - float3(cos(ang) * 1.45, -0.15 + 0.2 * sin(t * 2.0 + float(i)), sin(ang) * 1.45);
        float ds = length(sp) - 0.30;
        if (ds < res.x) res = float2(ds, 4.0 + float(i));
    }
    return res;
}

float3 calcNormal(float3 p, float t, float4 hero) {
    const float2 e = float2(0.0015, -0.0015);
    return normalize(
        e.xyy * mapScene(p + e.xyy, t, hero).x +
        e.yyx * mapScene(p + e.yyx, t, hero).x +
        e.yxy * mapScene(p + e.yxy, t, hero).x +
        e.xxx * mapScene(p + e.xxx, t, hero).x
    );
}

float calcSoftShadow(float3 ro, float3 rd, float tSec, float4 hero) {
    float res = 1.0;
    float t = 0.04;
    for (int i = 0; i < 24; ++i) {
        float h = mapScene(ro + rd * t, tSec, hero).x;
        if (h < 0.001) return 0.0;
        res = min(res, 12.0 * h / t);
        t += clamp(h, 0.02, 0.25);
        if (t > 6.0) break;
    }
    return clamp(res, 0.0, 1.0);
}

float3 clusterHashColor(float3 p, float lodStep) {
    float3 cell = floor(p * (6.0 / max(lodStep, 0.25)));
    float h = fract(sin(dot(cell, float3(12.9898, 78.233, 37.719))) * 43758.5453);
    return 0.35 + 0.65 * cos(6.28318 * (h + float3(0.0, 0.33, 0.67)));
}

float calcAmbientOcclusion(float3 pos, float3 nor, float tSec, float4 hero) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = 0; i < 5; ++i) {
        float h = 0.02 + 0.11 * float(i) / 4.0;
        float d = mapScene(pos + h * nor, tSec, hero).x;
        occ += (h - d) * sca;
        sca *= 0.92;
    }
    return clamp(1.0 - 2.6 * occ, 0.0, 1.0);
}

float3 materialColorForId(float matId, float3 pos, int renderMode, float lodStep, float rayDist) {
    if (renderMode == 2) {
        return clusterHashColor(pos, lodStep);
    }
    if (matId == 1.0) {
        float2 coord = pos.xz * 2.0;
        float2 grid = abs(fract(coord - 0.5) - 0.5) / max(0.015 * rayDist, 0.008);
        float line = min(grid.x, grid.y);
        float checker = fmod(floor(coord.x) + floor(coord.y), 2.0);
        float3 tileCol = (checker != 0.0) ? float3(0.07, 0.11, 0.18) : float3(0.04, 0.07, 0.12);
        return mix(float3(0.0, 0.85, 0.95), tileCol, clamp(line, 0.0, 1.0));
    }
    if (matId == 3.0) return float3(0.98, 0.42, 0.16);
    if (matId >= 4.0) return float3(0.60, 0.28, 0.96);
    return float3(0.12, 0.72, 0.98);
}

// Cook-Torrance Microfacet GGX BRDF (UE5-style PBR Shading)
float3 evalCookTorranceGGX(
    float3 N,
    float3 V,
    float3 L,
    float3 albedo,
    float metallic,
    float roughness,
    float shadow,
    float ao,
    float emissive
) {
    float3 sumVL = V + L;
    float3 H = (dot(sumVL, sumVL) > 1e-6) ? normalize(sumVL) : N;
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.005);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);

    float a = max(roughness * roughness, 0.004);
    float a2 = a * a;
    float denom = (NdotH * NdotH * (a2 - 1.0) + 1.0);
    float D = a2 / max(3.14159265 * denom * denom, 0.001);

    float k = ((roughness + 1.0) * (roughness + 1.0)) * 0.125;
    float G_V = NdotV / (NdotV * (1.0 - k) + k);
    float G_L = NdotL / (NdotL * (1.0 - k) + k);
    float G = G_V * G_L;

    float3 F0 = mix(float3(0.04), albedo, metallic);
    float3 F = F0 + (1.0 - F0) * pow(clamp(1.0 - VdotH, 0.0, 1.0), 5.0);

    float3 spec = min((D * G * F) / max(4.0 * NdotV * NdotL, 0.005), float3(4.0));
    float3 kD = (float3(1.0) - F) * (1.0 - metallic);
    float3 diffuse = kD * albedo / 3.14159265;

    float3 radiance = float3(2.8, 2.7, 2.5) * shadow;
    float3 direct = albedo * (0.18 * ao) + (diffuse + spec) * radiance * NdotL + albedo * emissive;
    return clamp(direct, float3(0.0), float3(6.0));
}

// Volumetric Distance Fog & Mie Sun Scattering (God-Ray Halo)
float3 applyVolumetricAtmosphere(
    float3 col,
    float3 rd,
    float3 lightDir,
    float firstHitDist,
    float fogDensity
) {
    float fogAmount = 1.0 - exp(-firstHitDist * fogDensity * 0.28);
    float sunDot = max(dot(rd, lightDir), 0.0);
    float3 fogCol = mix(
        float3(0.05, 0.09, 0.17),
        float3(0.95, 0.68, 0.38),
        pow(sunDot, 6.0)
    );
    return mix(col, fogCol, clamp(fogAmount, 0.0, 0.92));
}

// Academy ACES Filmic Tone Mapping Curve
float3 acesFilmicToneMap(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

kernel void zero3d_render_kernel(
    texture2d<half, access::write> outTex [[texture(0)]],
    constant Uniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    float2 uv = (float2(gid) - 0.5 * u.resolution) / max(u.resolution.y, 1.0);
    uv.y = -uv.y;

    float cy = cos(u.cameraYaw), sy = sin(u.cameraYaw);
    float cp = cos(u.cameraPitch), sp = sin(u.cameraPitch);
    float3 camOffset = float3(sy * cp, sp, cy * cp) * max(u.cameraDist, 1.2);
    float3 ro = u.cameraTarget.xyz + camOffset;
    float3 fwd = normalize(-camOffset);
    float3 right = normalize(cross(fwd, float3(0.0, 1.0, 0.0)));
    float3 up = cross(right, fwd);
    float fovScale = tan(u.cameraFov * 0.5 * 0.01745329);
    float3 rd = normalize(fwd + (uv.x * right + uv.y * up) * fovScale);

    float3 lightDir = normalize(float3(
        cos(u.lightElevation) * sin(u.lightAzimuth),
        sin(u.lightElevation),
        cos(u.lightElevation) * cos(u.lightAzimuth)
    ));

    float3 accumCol = float3(0.0);
    float3 throughput = float3(1.0);
    float firstHitDist = 14.0;
    float animTime = u.postProcess.w > 0.001 ? u.postProcess.w : u.timeSec;
    int bounces = (u.renderMode == 1) ? clamp(u.maxRayBounces, 1, 4) : 1;

    for (int bounce = 0; bounce < bounces; ++bounce) {
        float t = (bounce == 0) ? 0.0 : 0.025;
        float matId = -1.0;
        int maxSteps = (bounce == 0) ? 64 : 32;
        for (int i = 0; i < maxSteps; ++i) {
            float2 h = mapScene(ro + rd * t, animTime, u.heroPosScale);
            if (h.x < 0.002) {
                matId = h.y;
                break;
            }
            t += h.x;
            if (t > 16.0) break;
        }

        float3 sky = mix(float3(0.03, 0.05, 0.10), float3(0.07, 0.14, 0.26), clamp(rd.y + 0.5, 0.0, 1.0));
        if (matId < 0.0) {
            accumCol += throughput * sky;
            break;
        }
        if (bounce == 0) firstHitDist = t;

        float3 pos = ro + rd * t;
        float3 nor = calcNormal(pos, animTime, u.heroPosScale);
        float shadow = (u.renderMode <= 1) ? calcSoftShadow(pos + nor * 0.02, lightDir, animTime, u.heroPosScale) : 1.0;
        float ao = (bounce == 0) ? calcAmbientOcclusion(pos, nor, animTime, u.heroPosScale) : 0.85;

        float3 baseCol = materialColorForId(matId, pos, u.renderMode, u.lodThreshold, t);
        float metallic = (matId == 1.0) ? 0.25 : clamp(u.pbrParams.x, 0.0, 1.0);
        float roughness = (matId == 1.0) ? 0.35 : clamp(u.pbrParams.y, 0.04, 1.0);
        float emissive = (matId == 3.0) ? clamp(u.pbrParams.z, 0.0, 5.0) : 0.0;

        float3 direct = evalCookTorranceGGX(
            nor, -rd, lightDir, baseCol, metallic, roughness, shadow, ao, emissive
        );

        accumCol += throughput * direct;
        throughput *= mix(0.18, 0.55, metallic) * (1.0 - roughness * 0.65);
        ro = pos + nor * 0.025;
        rd = reflect(rd, nor);
    }

    // Volumetric Fog & Sun Scattering + Bloom + ACES Filmic Tone Mapping
    float3 fogged = applyVolumetricAtmosphere(
        accumCol, rd, lightDir, firstHitDist, clamp(u.postProcess.x, 0.0, 1.0)
    );
    float3 bloomHighlight = max(fogged - float3(0.75), float3(0.0)) * clamp(u.postProcess.z, 0.0, 2.0);
    float3 exposed = (fogged + bloomHighlight) * clamp(u.postProcess.y, 0.2, 4.0);
    float3 mapped = pow(acesFilmicToneMap(exposed), float3(0.88));
    outTex.write(half4(half3(mapped), 1.0h), gid);
}
)";

@interface Zero3DEngineTexture () {
    NSObject<FlutterTextureRegistry> *_registry;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLComputePipelineState> _computePipeline;
    CVMetalTextureCacheRef _textureCache;
    CVPixelBufferRef _pixelBuffers[kTripleBufferCount];
    CVMetalTextureRef _metalTextures[kTripleBufferCount];
    int _writeSlot;
    int _readySlot;
    int _readingSlot;
    int _prevReadingSlot;
    std::atomic<bool> _gpuInFlight;
    os_unfair_lock _bufferLock;
    CADisplayLink *_displayLink;
    dispatch_source_t _uncappedTimer;
    Zero3DEngineState *_engineState;
    Zero3DEcsWorld *_ecsWorld;
    int64_t _textureId;
    int32_t _width;
    int32_t _height;
    CFTimeInterval _startTime;
    CFTimeInterval _lastFrameTime;
    BOOL _isDisposed;
}
- (void)onDisplayLink:(CADisplayLink *)link;
- (void)renderSingleFrame;
@end

@interface _Zero3DDisplayLinkProxy : NSObject {
    __weak Zero3DEngineTexture *_target;
}
- (instancetype)initWithTarget:(Zero3DEngineTexture *)target;
- (void)onDisplayLink:(CADisplayLink *)link;
@end

@implementation _Zero3DDisplayLinkProxy
- (instancetype)initWithTarget:(Zero3DEngineTexture *)target {
    self = [super init];
    if (self) { _target = target; }
    return self;
}
- (void)onDisplayLink:(CADisplayLink *)link {
    Zero3DEngineTexture *strong = _target;
    if (strong) {
        [strong onDisplayLink:link];
    } else {
        [link invalidate];
    }
}
@end

@implementation Zero3DEngineTexture

@synthesize textureId = _textureId;
@synthesize engineState = _engineState;
@synthesize ecsWorld = _ecsWorld;

- (instancetype)initWithWidth:(int32_t)width
                       height:(int32_t)height
                     registry:(NSObject<FlutterTextureRegistry> *)registry {
    self = [super init];
    if (self) {
        _registry = registry;
        _width = width > 64 ? width : 1280;
        _height = height > 64 ? height : 720;
        _bufferLock = OS_UNFAIR_LOCK_INIT;
        _writeSlot = 0;
        _readySlot = 0;
        _readingSlot = 0;
        _prevReadingSlot = 0;
        _gpuInFlight.store(false, std::memory_order_relaxed);
        _isDisposed = NO;
        _startTime = CACurrentMediaTime();
        _lastFrameTime = _startTime;

        _engineState = zero_3d_create_state();
        _ecsWorld = zero_3d_ecs_create_world();
        // Entity #0: 中央のメイン Octahedron (Gizmo で 3D 移動・スケール操作可能)
        zero_3d_ecs_spawn_entity(_ecsWorld, 0.0f, 0.25f, 0.0f, 1.0f, 0.65f, 128);
        for (int i = 1; i < 64; ++i) {
            float x = (float)((i % 8) - 3.5f) * 1.2f;
            float z = (float)((i / 8) - 3.5f) * 1.2f;
            zero_3d_ecs_spawn_entity(_ecsWorld, x, 0.0f, z, 1.0f, 0.6f, 64);
        }
        zero_3d_ecs_load_builtin_obj_preset(_ecsWorld, 1);
        zero_3d_set_status(_engineState, ZERO_3D_STATUS_RENDERING);

        [self setupMetalPipeline];
        [self allocateTripleBufferedIOSurfacesWidth:_width height:_height];

        _textureId = [_registry registerTexture:self];
        [self renderSingleFrame];
        [self setupHighRefreshDisplayLink];
    }
    return self;
}

- (void)setupMetalPipeline {
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) return;
    _commandQueue = [_device newCommandQueue];
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, _device, nil, &_textureCache);

    NSError *err = nil;
    MTLCompileOptions *opts = [[MTLCompileOptions alloc] init];
    opts.fastMathEnabled = NO;
    id<MTLLibrary> lib = [_device newLibraryWithSource:kZero3DMetalShaderSource options:opts error:&err];
    if (!lib && err) {
        NSLog(@"[d_zero_3dengine] Metal shader compile error: %@", err);
        return;
    }
    if (lib) {
        id<MTLFunction> fn = [lib newFunctionWithName:@"zero3d_render_kernel"];
        if (fn) {
            _computePipeline = [_device newComputePipelineStateWithFunction:fn error:&err];
        }
    }
}

- (void)allocateTripleBufferedIOSurfacesWidth:(int32_t)w height:(int32_t)h {
    [self releaseTripleBuffers];
    if (!_device || !_textureCache) return;

    NSDictionary *attrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferMetalCompatibilityKey : @YES,
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    for (int i = 0; i < kTripleBufferCount; ++i) {
        CVPixelBufferCreate(
            kCFAllocatorDefault, w, h,
            kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attrs,
            &_pixelBuffers[i]
        );
        if (_pixelBuffers[i]) {
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, _textureCache, _pixelBuffers[i], nil,
                MTLPixelFormatBGRA8Unorm, w, h, 0, &_metalTextures[i]
            );
        }
    }
}

- (void)releaseTripleBuffers {
    for (int i = 0; i < kTripleBufferCount; ++i) {
        if (_metalTextures[i]) {
            CFRelease(_metalTextures[i]);
            _metalTextures[i] = NULL;
        }
        if (_pixelBuffers[i]) {
            CVBufferRelease(_pixelBuffers[i]);
            _pixelBuffers[i] = NULL;
        }
    }
}

- (float)detectNativeMonitorRefreshRate {
#if TARGET_OS_OSX
    CGDirectDisplayID displayId = CGMainDisplayID();
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayId);
    if (mode) {
        double hz = CGDisplayModeGetRefreshRate(mode);
        CGDisplayModeRelease(mode);
        if (hz >= 30.0 && hz <= 500.0) {
            return (float)hz;
        }
    }
#endif
    return 120.0f;
}

- (void)setupHighRefreshDisplayLink {
    _Zero3DDisplayLinkProxy *proxy = [[_Zero3DDisplayLinkProxy alloc] initWithTarget:self];
    float nativeHz = [self detectNativeMonitorRefreshRate];

#if TARGET_OS_OSX
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    _displayLink = [screen displayLinkWithTarget:proxy selector:@selector(onDisplayLink:)];
#else
    _displayLink = [CADisplayLink displayLinkWithTarget:proxy selector:@selector(onDisplayLink:)];
#endif
    if (@available(iOS 15.0, macOS 14.0, *)) {
        // 144Hz / 240Hz ゲーミングモニターの上限まで CADisplayLink を解放
        float maxTarget = nativeHz > 120.0f ? nativeHz : 240.0f;
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60.0f, maxTarget, maxTarget);
    }
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    // Uncapped / High-Refresh (144Hz / 240Hz / 500Hz) タイマー駆動
    __weak Zero3DEngineTexture *weakSelf = self;
    _uncappedTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_main_queue());
    dispatch_source_set_timer(_uncappedTimer, DISPATCH_TIME_NOW, 2000000ull, 100000ull);
    dispatch_source_set_event_handler(_uncappedTimer, ^{
        Zero3DEngineTexture *strong = weakSelf;
        if (!strong || strong->_isDisposed || !strong->_engineState) return;
        int32_t fpsMode = strong->_engineState->fps_mode.load(std::memory_order_relaxed);
        if (fpsMode >= ZERO_3D_FPS_CAP_144 || !strong->_displayLink) {
            CFTimeInterval elapsed = CACurrentMediaTime() - strong->_lastFrameTime;
            CFTimeInterval minInterval = (fpsMode == ZERO_3D_FPS_CAP_144) ? (1.0 / 146.0)
                                       : (fpsMode == ZERO_3D_FPS_CAP_240) ? (1.0 / 244.0)
                                       : 0.0018;
            if (elapsed >= minInterval) {
                [strong renderSingleFrame];
            }
        }
    });
    dispatch_resume(_uncappedTimer);
}

- (void)onDisplayLink:(CADisplayLink *)link {
    if (_isDisposed || !_engineState) return;
    int32_t fpsMode = _engineState->fps_mode.load(std::memory_order_relaxed);
    if (fpsMode >= ZERO_3D_FPS_CAP_144) return;
    [self renderSingleFrame];
}

- (void)renderSingleFrame {
    if (_isDisposed || !_engineState) return;
    if (!_computePipeline || !_commandQueue) return;
    if (_gpuInFlight.exchange(true, std::memory_order_acq_rel)) return;

    CFTimeInterval now = CACurrentMediaTime();
    float dtMs = (float)((now - _lastFrameTime) * 1000.0);
    _lastFrameTime = now;
    if (dtMs <= 0.05f || dtMs > 500.0f) dtMs = 2.0f;

    os_unfair_lock_lock(&_bufferLock);
    int slot = (_writeSlot + 1) % kTripleBufferCount;
    for (int i = 0; i < kTripleBufferCount; ++i) {
        int candidate = (_writeSlot + 1 + i) % kTripleBufferCount;
        if (candidate != _readySlot &&
            candidate != _readingSlot &&
            candidate != _prevReadingSlot) {
            slot = candidate;
            break;
        }
    }
    _writeSlot = slot;
    CVMetalTextureRef cvTex = _metalTextures[slot];
    id<MTLTexture> mtlTex = cvTex ? CVMetalTextureGetTexture(cvTex) : nil;
    os_unfair_lock_unlock(&_bufferLock);
    if (!mtlTex) {
        _gpuInFlight.store(false, std::memory_order_release);
        return;
    }

    Zero3DGpuUniforms u;
    u.resolution[0] = (float)_width;
    u.resolution[1] = (float)_height;
    u.timeSec = (float)(now - _startTime);
    u.cameraYaw = _engineState->camera_yaw.load(std::memory_order_relaxed);
    u.cameraPitch = _engineState->camera_pitch.load(std::memory_order_relaxed);
    u.cameraDist = _engineState->camera_distance.load(std::memory_order_relaxed);
    u.cameraFov = _engineState->camera_fov_deg.load(std::memory_order_relaxed);
    u.lightAzimuth = _engineState->light_azimuth.load(std::memory_order_relaxed);
    u.lightElevation = _engineState->light_elevation.load(std::memory_order_relaxed);
    u.lodThreshold = _engineState->lod_error_threshold.load(std::memory_order_relaxed);
    u.renderMode = _engineState->render_mode.load(std::memory_order_relaxed);
    u.maxRayBounces = _engineState->max_ray_bounces.load(std::memory_order_relaxed);
    int32_t selId = _ecsWorld ? zero_3d_ecs_get_selected_entity(_ecsWorld) : 0;
    if (selId < 0) selId = 0;
    u.heroPosScale[0] = _ecsWorld ? zero_3d_ecs_get_entity_x(_ecsWorld, selId) : 0.0f;
    u.heroPosScale[1] = _ecsWorld ? zero_3d_ecs_get_entity_y(_ecsWorld, selId) : 0.25f;
    u.heroPosScale[2] = _ecsWorld ? zero_3d_ecs_get_entity_z(_ecsWorld, selId) : 0.0f;
    u.heroPosScale[3] = _ecsWorld ? zero_3d_ecs_get_entity_scale(_ecsWorld, selId) : 1.0f;
    u.cameraTarget[0] = _engineState->target_x.load(std::memory_order_relaxed);
    u.cameraTarget[1] = _engineState->target_y.load(std::memory_order_relaxed);
    u.cameraTarget[2] = _engineState->target_z.load(std::memory_order_relaxed);
    u.cameraTarget[3] = 0.0f;
    u.pbrParams[0] = _ecsWorld ? zero_3d_ecs_get_pbr_metallic(_ecsWorld) : 0.75f;
    u.pbrParams[1] = _ecsWorld ? zero_3d_ecs_get_pbr_roughness(_ecsWorld) : 0.18f;
    u.pbrParams[2] = _ecsWorld ? zero_3d_ecs_get_pbr_emissive(_ecsWorld) : 0.25f;
    u.pbrParams[3] = _ecsWorld ? (float)zero_3d_ecs_get_physics_enabled(_ecsWorld) : 0.0f;
    u.postProcess[0] = _ecsWorld ? zero_3d_ecs_get_fog_density(_ecsWorld) : 0.15f;
    u.postProcess[1] = _ecsWorld ? zero_3d_ecs_get_exposure_ev(_ecsWorld) : 1.25f;
    u.postProcess[2] = _ecsWorld ? zero_3d_ecs_get_bloom_intensity(_ecsWorld) : 0.45f;
    u.postProcess[3] = _ecsWorld ? zero_3d_ecs_get_sequencer_time(_ecsWorld) : u.timeSec;

    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> enc = [cmdBuf computeCommandEncoder];
    [enc setComputePipelineState:_computePipeline];
    [enc setTexture:mtlTex atIndex:0];
    [enc setBytes:&u length:sizeof(u) atIndex:0];

    MTLSize tgSize = MTLSizeMake(8, 8, 1);
    MTLSize gridSize = MTLSizeMake(_width, _height, 1);
    [enc dispatchThreads:gridSize threadsPerThreadgroup:tgSize];
    [enc endEncoding];

    float monitorHz = [self detectNativeMonitorRefreshRate];
    _engineState->display_refresh_hz.store(monitorHz, std::memory_order_relaxed);
    if (_ecsWorld) {
        zero_3d_ecs_step_sequencer(_ecsWorld, dtMs * 0.001f);
        zero_3d_ecs_step_transforms(_ecsWorld, dtMs * 0.001f);
        zero_3d_ecs_step_physics(_ecsWorld, dtMs * 0.001f);
        zero_3d_ecs_cull_and_update_state(_ecsWorld, _engineState, dtMs);
    } else {
        zero_3d_simulate_frame_step(_engineState, 4096, dtMs);
    }

    if (_engineState->frame_count.load(std::memory_order_relaxed) <= 1) {
        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];
        os_unfair_lock_lock(&_bufferLock);
        _readySlot = slot;
        os_unfair_lock_unlock(&_bufferLock);
        _gpuInFlight.store(false, std::memory_order_release);
        [_registry textureFrameAvailable:_textureId];
        return;
    }

    __weak Zero3DEngineTexture *weakSelf = self;
    [cmdBuf addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
        Zero3DEngineTexture *strong = weakSelf;
        if (!strong || strong->_isDisposed) return;
        os_unfair_lock_lock(&strong->_bufferLock);
        strong->_readySlot = slot;
        os_unfair_lock_unlock(&strong->_bufferLock);
        strong->_gpuInFlight.store(false, std::memory_order_release);
        dispatch_async(dispatch_get_main_queue(), ^{
            Zero3DEngineTexture *mainStrong = weakSelf;
            if (mainStrong && !mainStrong->_isDisposed) {
                [mainStrong->_registry textureFrameAvailable:mainStrong->_textureId];
            }
        });
    }];
    [cmdBuf commit];
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    os_unfair_lock_lock(&_bufferLock);
    if (_readingSlot != _readySlot) {
        _prevReadingSlot = _readingSlot;
        _readingSlot = _readySlot;
    }
    CVPixelBufferRef buf = _pixelBuffers[_readingSlot];
    if (buf) {
        CVBufferRetain(buf);
    }
    os_unfair_lock_unlock(&_bufferLock);
    return buf;
}

- (void)resizeWidth:(int32_t)width height:(int32_t)height {
    if (_isDisposed || width <= 64 || height <= 64) return;
    if (width == _width && height == _height) return;
    os_unfair_lock_lock(&_bufferLock);
    _width = width;
    _height = height;
    [self allocateTripleBufferedIOSurfacesWidth:_width height:_height];
    os_unfair_lock_unlock(&_bufferLock);
}

- (void)startRendering {
    if (_isDisposed) return;
    _displayLink.paused = NO;
    zero_3d_set_status(_engineState, ZERO_3D_STATUS_RENDERING);
}

- (void)pauseRendering {
    if (_isDisposed) return;
    _displayLink.paused = YES;
    zero_3d_set_status(_engineState, ZERO_3D_STATUS_PAUSED);
}

- (void)dispose {
    if (_isDisposed) return;
    _isDisposed = YES;

    if (_uncappedTimer) {
        dispatch_source_cancel(_uncappedTimer);
        _uncappedTimer = nil;
    }
    [_displayLink invalidate];
    _displayLink = nil;

    os_unfair_lock_lock(&_bufferLock);
    [self releaseTripleBuffers];
    if (_textureCache) {
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    os_unfair_lock_unlock(&_bufferLock);

    [_registry unregisterTexture:_textureId];

    if (_ecsWorld) {
        zero_3d_ecs_destroy_world(_ecsWorld);
        _ecsWorld = nullptr;
    }
    if (_engineState) {
        zero_3d_destroy_state(_engineState);
        _engineState = nullptr;
    }
}

- (void)dealloc {
    [self dispose];
}

@end

#pragma clang diagnostic pop

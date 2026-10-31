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

static const int kTripleBufferCount = 3;

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
float2 mapScene(float3 p, float t) {
    float dFloor = p.y + 1.05;
    float2 res = float2(dFloor, 1.0);

    float3 q = p - float3(0.0, 0.1 * sin(t * 1.4), 0.0);
    float dCore = sdTorus(q, float2(0.82, 0.26));
    if (dCore < res.x) res = float2(dCore, 2.0);

    float dOct = sdOctahedron(p - float3(0.0, 0.25, 0.0), 0.55);
    if (dOct < res.x) res = float2(dOct, 3.0);

    for (int i = 0; i < 4; ++i) {
        float ang = t * 0.7 + float(i) * 1.5707963;
        float3 sp = p - float3(cos(ang) * 1.45, -0.15 + 0.2 * sin(t * 2.0 + float(i)), sin(ang) * 1.45);
        float ds = length(sp) - 0.30;
        if (ds < res.x) res = float2(ds, 4.0 + float(i));
    }
    return res;
}

float3 calcNormal(float3 p, float t) {
    const float2 e = float2(0.0015, -0.0015);
    return normalize(
        e.xyy * mapScene(p + e.xyy, t).x +
        e.yyx * mapScene(p + e.yyx, t).x +
        e.yxy * mapScene(p + e.yxy, t).x +
        e.xxx * mapScene(p + e.xxx, t).x
    );
}

float calcSoftShadow(float3 ro, float3 rd, float tSec) {
    float res = 1.0;
    float t = 0.04;
    for (int i = 0; i < 24; ++i) {
        float h = mapScene(ro + rd * t, tSec).x;
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

float calcAmbientOcclusion(float3 pos, float3 nor, float tSec) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = 0; i < 5; ++i) {
        float h = 0.02 + 0.11 * float(i) / 4.0;
        float d = mapScene(pos + h * nor, tSec).x;
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
    float3 ro = float3(sy * cp, sp, cy * cp) * max(u.cameraDist, 1.2);
    float3 fwd = normalize(-ro);
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
    int bounces = (u.renderMode == 1) ? clamp(u.maxRayBounces, 1, 4) : 1;

    for (int bounce = 0; bounce < bounces; ++bounce) {
        float t = 0.0;
        float matId = -1.0;
        for (int i = 0; i < 64; ++i) {
            float2 h = mapScene(ro + rd * t, u.timeSec);
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

        float3 pos = ro + rd * t;
        float3 nor = calcNormal(pos, u.timeSec);
        float diff = max(dot(nor, lightDir), 0.0);
        float shadow = (u.renderMode <= 1) ? calcSoftShadow(pos + nor * 0.01, lightDir, u.timeSec) : 1.0;
        float ao = calcAmbientOcclusion(pos, nor, u.timeSec);

        float3 baseCol = materialColorForId(matId, pos, u.renderMode, u.lodThreshold, t);
        float3 halfV = normalize(lightDir - rd);
        float spec = pow(max(dot(nor, halfV), 0.0), 48.0) * shadow;
        float3 direct = baseCol * (0.22 * ao + 0.85 * diff * shadow) + float3(0.9, 0.95, 1.0) * spec * 0.65;

        accumCol += throughput * direct;
        throughput *= 0.38;
        ro = pos + nor * 0.012;
        rd = reflect(rd, nor);
    }

    // Tone mapping & gamma curve for vivid HDR presentation
    float3 mapped = accumCol / (accumCol + float3(0.65));
    mapped = pow(clamp(mapped * 1.35, 0.0, 1.0), float3(0.85));
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
        _isDisposed = NO;
        _startTime = CACurrentMediaTime();
        _lastFrameTime = _startTime;

        _engineState = zero_3d_create_state();
        _ecsWorld = zero_3d_ecs_create_world();
        for (int i = 0; i < 64; ++i) {
            float x = (float)((i % 8) - 3.5f) * 1.2f;
            float z = (float)((i / 8) - 3.5f) * 1.2f;
            zero_3d_ecs_spawn_entity(_ecsWorld, x, 0.0f, z, 1.0f, 0.6f, 64);
        }
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
    opts.fastMathEnabled = YES;
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
            [strong renderSingleFrame];
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

    CFTimeInterval now = CACurrentMediaTime();
    float dtMs = (float)((now - _lastFrameTime) * 1000.0);
    _lastFrameTime = now;
    if (dtMs <= 0.05f || dtMs > 500.0f) dtMs = 2.0f;

    int slot = (_writeSlot + 1) % kTripleBufferCount;
    CVMetalTextureRef cvTex = _metalTextures[slot];
    id<MTLTexture> mtlTex = cvTex ? CVMetalTextureGetTexture(cvTex) : nil;
    if (!mtlTex) return;

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

    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> enc = [cmdBuf computeCommandEncoder];
    [enc setComputePipelineState:_computePipeline];
    [enc setTexture:mtlTex atIndex:0];
    [enc setBytes:&u length:sizeof(u) atIndex:0];

    MTLSize tgSize = MTLSizeMake(8, 8, 1);
    MTLSize gridSize = MTLSizeMake(_width, _height, 1);
    [enc dispatchThreads:gridSize threadsPerThreadgroup:tgSize];
    [enc endEncoding];
    [cmdBuf commit];
    if (_engineState->frame_count.load(std::memory_order_relaxed) == 0) {
        [cmdBuf waitUntilCompleted];
    }

    os_unfair_lock_lock(&_bufferLock);
    _writeSlot = slot;
    _readySlot = slot;
    os_unfair_lock_unlock(&_bufferLock);

    float monitorHz = [self detectNativeMonitorRefreshRate];
    _engineState->display_refresh_hz.store(monitorHz, std::memory_order_relaxed);
    if (_ecsWorld) {
        zero_3d_ecs_step_transforms(_ecsWorld, dtMs * 0.001f);
        zero_3d_ecs_cull_and_update_state(_ecsWorld, _engineState, dtMs);
    } else {
        zero_3d_simulate_frame_step(_engineState, 4096, dtMs);
    }
    [_registry textureFrameAvailable:_textureId];
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    os_unfair_lock_lock(&_bufferLock);
    CVPixelBufferRef buf = _pixelBuffers[_readySlot];
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

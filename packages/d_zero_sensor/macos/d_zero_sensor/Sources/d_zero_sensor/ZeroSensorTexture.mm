#import "ZeroSensorTexture.h"
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <Vision/Vision.h>
#import <os/lock.h>
#include <algorithm>
#include <chrono>
#include <cstring>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

namespace {
inline int64_t now_steady_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}
}  // namespace

@interface ZeroSensorTexture () {
    NSObject<FlutterTextureRegistry> *_registry;
    ZeroCameraSharedState *_cameraState;
    AVCaptureSession *_captureSession;
    AVCaptureVideoDataOutput *_videoOutput;
    dispatch_queue_t _captureQueue;
    VNSequenceRequestHandler *_visionHandler;
    VNDetectBarcodesRequest *_qrRequest;
    CVPixelBufferRef _latestPixelBuffer;
    os_unfair_lock _pixelBufferLock;
    int64_t _textureId;
    int32_t _facing;
    int32_t _preferredFps;
    BOOL _ownsState;
    BOOL _isDisposed;
}
@end

@implementation ZeroSensorTexture

@synthesize textureId = _textureId;
@synthesize cameraState = _cameraState;

- (instancetype)initWithState:(ZeroCameraSharedState *)state
                       facing:(int32_t)facing
                 preferredFps:(int32_t)preferredFps
                     registry:(NSObject<FlutterTextureRegistry> *)registry {
    self = [super init];
    if (self) {
        _registry = registry;
        _isDisposed = NO;
        _latestPixelBuffer = nil;
        _pixelBufferLock = OS_UNFAIR_LOCK_INIT;
        _facing = facing;
        _preferredFps = preferredFps > 0 ? preferredFps : 120;

        if (state != nullptr) {
            _cameraState = state;
            _ownsState = NO;
        } else {
            _cameraState = zero_camera_create_state();
            _ownsState = YES;
        }

        zero_camera_set_status(_cameraState, ZERO_CAM_STATUS_INITIALIZING);
        _textureId = [_registry registerTexture:self];

        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(
            DISPATCH_QUEUE_SERIAL,
            QOS_CLASS_USER_INTERACTIVE,
            0
        );
        _captureQueue = dispatch_queue_create("com.fexcy.d_zero_sensor.capture", attr);

        _visionHandler = [[VNSequenceRequestHandler alloc] init];
        _qrRequest = [[VNDetectBarcodesRequest alloc] init];
        _qrRequest.symbologies = @[ VNBarcodeSymbologyQR ];

        [self configureCaptureSession];
    }
    return self;
}

- (nullable AVCaptureDevice *)selectCaptureDeviceForFacing:(int32_t)facing {
#if TARGET_OS_OSX
    NSArray<AVCaptureDeviceType> *types = @[ AVCaptureDeviceTypeBuiltInWideAngleCamera ];
    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:types
                              mediaType:AVMediaTypeVideo
                               position:AVCaptureDevicePositionUnspecified];
    if (discovery.devices.count > 0) {
        return discovery.devices.firstObject;
    }
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
#else
    AVCaptureDevicePosition pos = (facing == 1)
        ? AVCaptureDevicePositionFront
        : AVCaptureDevicePositionBack;
    NSArray<AVCaptureDeviceType> *types = @[
        AVCaptureDeviceTypeBuiltInWideAngleCamera,
        AVCaptureDeviceTypeBuiltInUltraWideCamera
    ];
    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:types
                              mediaType:AVMediaTypeVideo
                               position:pos];
    if (discovery.devices.count > 0) {
        return discovery.devices.firstObject;
    }
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
#endif
}

- (void)applyHighFrameRateFormatOnDevice:(AVCaptureDevice *)device targetFps:(int32_t)targetFps {
    AVCaptureDeviceFormat *bestFormat = nil;
    AVFrameRateRange *bestRange = nil;
    Float64 bestMaxFps = 0.0;

    for (AVCaptureDeviceFormat *format in device.formats) {
        CMFormatDescriptionRef desc = format.formatDescription;
        FourCharCode subType = CMFormatDescriptionGetMediaSubType(desc);
        BOOL isBiPlanarYuv = (subType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                              subType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
        if (!isBiPlanarYuv) continue;

        CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(desc);
        if (dims.width < 640 || dims.width > 1920) continue;

        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
            Float64 cappedFps = std::min<Float64>(range.maxFrameRate, (Float64)targetFps);
            if (cappedFps > bestMaxFps) {
                bestMaxFps = cappedFps;
                bestFormat = format;
                bestRange = range;
            }
        }
    }

    if (!bestFormat || !bestRange) return;
    NSError *lockErr = nil;
    if ([device lockForConfiguration:&lockErr]) {
        device.activeFormat = bestFormat;
        int32_t chosenFps = (int32_t)std::clamp<Float64>(
            bestMaxFps,
            bestRange.minFrameRate,
            bestRange.maxFrameRate
        );
        if (chosenFps > 0) {
            CMTime frameDuration = CMTimeMake(1, chosenFps);
            device.activeVideoMinFrameDuration = frameDuration;
            device.activeVideoMaxFrameDuration = frameDuration;
        }
        [device unlockForConfiguration];
    }
}

- (void)configureCaptureSession {
    AVCaptureDevice *device = [self selectCaptureDeviceForFacing:_facing];
    if (!device) {
        zero_camera_set_status(_cameraState, ZERO_CAM_STATUS_ERROR);
        return;
    }

    NSError *inputErr = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&inputErr];
    if (!input || inputErr) {
        zero_camera_set_status(_cameraState, ZERO_CAM_STATUS_ERROR);
        return;
    }

    _captureSession = [[AVCaptureSession alloc] init];
    [_captureSession beginConfiguration];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        _captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    }
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    }

    [self applyHighFrameRateFormatOnDevice:device targetFps:_preferredFps];

    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    _videoOutput.videoSettings = @{
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        (id)kCVPixelBufferMetalCompatibilityKey : @YES,
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    [_videoOutput setSampleBufferDelegate:self queue:_captureQueue];

    if ([_captureSession canAddOutput:_videoOutput]) {
        [_captureSession addOutput:_videoOutput];
    }
    [_captureSession commitConfiguration];
}

- (void)startCapture {
    if (_isDisposed || !_captureSession) return;
    AVCaptureSession *session = _captureSession;
    ZeroCameraSharedState *state = _cameraState;
    dispatch_async(_captureQueue, ^{
        if (!session.isRunning) {
            [session startRunning];
            zero_camera_set_status(state, ZERO_CAM_STATUS_STREAMING);
        }
    });
}

- (void)stopCapture {
    if (_isDisposed || !_captureSession) return;
    AVCaptureSession *session = _captureSession;
    ZeroCameraSharedState *state = _cameraState;
    dispatch_async(_captureQueue, ^{
        if (session.isRunning) {
            [session stopRunning];
            zero_camera_set_status(state, ZERO_CAM_STATUS_PAUSED);
        }
    });
}

- (void)switchCameraFacing:(int32_t)facing preferredFps:(int32_t)preferredFps {
    if (_isDisposed) return;
    _facing = facing;
    if (preferredFps > 0) {
        _preferredFps = preferredFps;
    }
    __weak ZeroSensorTexture *weakSelf = self;
    dispatch_async(_captureQueue, ^{
        ZeroSensorTexture *strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_isDisposed) return;
        [strongSelf->_captureSession stopRunning];
        [strongSelf configureCaptureSession];
        [strongSelf->_captureSession startRunning];
        zero_camera_set_status(strongSelf->_cameraState, ZERO_CAM_STATUS_STREAMING);
    });
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate (Zero-Copy YUV420 -> C++ Shared Memory)

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    if (_isDisposed || !_cameraState) return;

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;

    // 1. Update zero-copy GPU FlutterTexture (NV12 IOSurface)
    CVBufferRetain(pixelBuffer);
    os_unfair_lock_lock(&_pixelBufferLock);
    CVPixelBufferRef oldBuffer = _latestPixelBuffer;
    _latestPixelBuffer = pixelBuffer;
    os_unfair_lock_unlock(&_pixelBufferLock);
    if (oldBuffer) {
        CVBufferRelease(oldBuffer);
    }
    [_registry textureFrameAvailable:_textureId];

    // 2. Direct YUV420 Plane 0 (Luma Y) pointer ingestion into C++ Seqlock shared memory
    const int64_t startUs = now_steady_us();
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    const uint8_t *yPlane = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    int32_t width = (int32_t)CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    int32_t height = (int32_t)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    int32_t stride = (int32_t)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    if (!yPlane || width <= 0 || height <= 0) {
        yPlane = (const uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
        width = (int32_t)CVPixelBufferGetWidth(pixelBuffer);
        height = (int32_t)CVPixelBufferGetHeight(pixelBuffer);
        stride = (int32_t)CVPixelBufferGetBytesPerRow(pixelBuffer);
    }
    int32_t contrast = 0;
    if (yPlane && width >= 21 && height >= 21) {
        contrast = zero_camera_ingest_yuv_luma(_cameraState, yPlane, width, height, stride, 0.82f);
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    // 3. Contrast-gated zero-channel QR decode directly into C++ ZeroCameraSharedState
    if (contrast >= 28) {
        [self decodeQrIntoSharedMemory:pixelBuffer startUs:startUs];
    }
}

- (void)decodeQrIntoSharedMemory:(CVPixelBufferRef)pixelBuffer startUs:(int64_t)startUs {
    NSError *err = nil;
    BOOL ok = [_visionHandler performRequests:@[ _qrRequest ]
                              onCVPixelBuffer:pixelBuffer
                                        error:&err];
    if (!ok || err) return;

    NSArray<VNBarcodeObservation *> *results = _qrRequest.results;
    if (!results || results.count == 0) return;

    VNBarcodeObservation *primary = results.firstObject;
    NSString *payload = primary.payloadStringValue;
    if (!payload || payload.length == 0) return;

    zero_camera_begin_detections(_cameraState);
    int32_t limit = (int32_t)std::min<NSUInteger>(results.count, ZERO_CAM_MAX_DETECTIONS);
    for (int32_t i = 0; i < limit; ++i) {
        VNBarcodeObservation *obs = results[i];
        CGRect box = obs.boundingBox;
        // Vision normalized coordinates have origin at bottom-left; convert to top-left [0..1]
        float left = (float)box.origin.x;
        float top = (float)(1.0 - box.origin.y - box.size.height);
        float right = (float)(box.origin.x + box.size.width);
        float bottom = (float)(1.0 - box.origin.y);
        zero_camera_set_detection_box(
            _cameraState,
            i,
            left,
            top,
            right,
            bottom,
            obs.confidence * 100.0f
        );
    }

    const char *utf8 = [payload UTF8String];
    int32_t byteLen = utf8 ? (int32_t)std::strlen(utf8) : 0;
    int64_t decodeUs = std::max<int64_t>(1, now_steady_us() - startUs);
    zero_camera_commit_detection_payload(
        _cameraState,
        (const uint8_t *)utf8,
        byteLen,
        decodeUs
    );
}

#pragma mark - FlutterTexture Protocol

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    os_unfair_lock_lock(&_pixelBufferLock);
    CVPixelBufferRef buffer = _latestPixelBuffer;
    if (buffer) {
        CVBufferRetain(buffer);
    }
    os_unfair_lock_unlock(&_pixelBufferLock);
    return buffer;
}

- (void)dispose {
    if (_isDisposed) return;
    _isDisposed = YES;

    [_videoOutput setSampleBufferDelegate:nil queue:nil];
    if (_captureSession && _captureSession.isRunning) {
        [_captureSession stopRunning];
    }
    _captureSession = nil;
    _videoOutput = nil;

    os_unfair_lock_lock(&_pixelBufferLock);
    CVPixelBufferRef toRelease = _latestPixelBuffer;
    _latestPixelBuffer = nil;
    os_unfair_lock_unlock(&_pixelBufferLock);
    if (toRelease) {
        CVBufferRelease(toRelease);
    }

    [_registry unregisterTexture:_textureId];

    if (_ownsState && _cameraState) {
        zero_camera_destroy_state(_cameraState);
    }
    _cameraState = nullptr;
}

- (void)dealloc {
    [self dispose];
}

@end

#pragma clang diagnostic pop

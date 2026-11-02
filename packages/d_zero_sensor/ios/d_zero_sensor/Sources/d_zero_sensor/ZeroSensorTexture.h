#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif
#include "zero_camera_state.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZeroSensorTexture : NSObject <FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, readonly) int64_t textureId;
@property (nonatomic, readonly) ZeroCameraSharedState *cameraState;

- (instancetype)initWithState:(ZeroCameraSharedState *)state
                       facing:(int32_t)facing
                 preferredFps:(int32_t)preferredFps
                     registry:(NSObject<FlutterTextureRegistry> *)registry;

- (void)startCapture;
- (void)stopCapture;
- (void)switchCameraFacing:(int32_t)facing preferredFps:(int32_t)preferredFps;
- (void)dispose;

@end

NS_ASSUME_NONNULL_END

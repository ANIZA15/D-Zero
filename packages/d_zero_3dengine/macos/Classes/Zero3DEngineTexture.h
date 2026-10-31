#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

#include "zero_3d_engine_state.h"

NS_ASSUME_NONNULL_BEGIN

@interface Zero3DEngineTexture : NSObject<FlutterTexture>

@property (nonatomic, readonly) int64_t textureId;
@property (nonatomic, readonly, nullable) Zero3DEngineState *engineState;

- (instancetype)initWithWidth:(int32_t)width
                       height:(int32_t)height
                     registry:(NSObject<FlutterTextureRegistry> *)registry;

- (void)resizeWidth:(int32_t)width height:(int32_t)height;
- (void)startRendering;
- (void)pauseRendering;
- (void)dispose;

@end

NS_ASSUME_NONNULL_END

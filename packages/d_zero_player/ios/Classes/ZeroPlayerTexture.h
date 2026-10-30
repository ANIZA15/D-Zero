#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif
#include "zero_playback_state.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZeroPlayerTexture : NSObject <FlutterTexture>

@property (nonatomic, readonly) int64_t textureId;
@property (nonatomic, readonly) ZeroPlaybackState* playbackState;

- (instancetype)initWithURL:(NSURL *)url
                    headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                     isLive:(BOOL)isLive
                   registry:(NSObject<FlutterTextureRegistry> *)registry;

- (void)play;
- (void)pause;
- (void)seekTo:(int64_t)positionMs;
- (void)dispose;

@end

NS_ASSUME_NONNULL_END

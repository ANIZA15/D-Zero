#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Flutter/Flutter.h>
#include "zero_playback_state.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZeroPlayerTexture : NSObject <FlutterTexture>

@property (nonatomic, readonly) int64_t textureId;
@property (nonatomic, readonly) ZeroPlaybackState* playbackState;

- (instancetype)initWithURL:(NSURL *)url
                  registry:(NSObject<FlutterTextureRegistry> *)registry;

- (void)play;
- (void)pause;
- (void)seekTo:(int64_t)positionMs;
- (void)dispose;

@end

NS_ASSUME_NONNULL_END

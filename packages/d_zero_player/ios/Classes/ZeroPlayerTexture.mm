#import "ZeroPlayerTexture.h"
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static void *kZeroPlayerStatusKVOContext = &kZeroPlayerStatusKVOContext;
static const CFTimeInterval kZeroDriftSyncIntervalSec = 0.25;

@interface ZeroPlayerTexture () {
    NSObject<FlutterTextureRegistry> *_registry;
    AVPlayer *_player;
    AVPlayerItem *_playerItem;
    AVPlayerItemVideoOutput *_videoOutput;
    CADisplayLink *_displayLink;
    CVPixelBufferRef _latestPixelBuffer;
    ZeroPlaybackState *_playbackState;
    int64_t _textureId;
    os_unfair_lock _pixelBufferLock;
    CFTimeInterval _lastAnchorSyncTime;
    id _endObserver;
    BOOL _isObservingPlayer;
    BOOL _awaitingFrame;
    BOOL _isDisposed;
}
- (void)onDisplayLink:(CADisplayLink *)link;
@end

@interface _ZeroDisplayLinkProxy : NSObject {
    __weak ZeroPlayerTexture *_target;
}
- (instancetype)initWithTarget:(ZeroPlayerTexture *)target;
- (void)onDisplayLink:(CADisplayLink *)link;
@end

@implementation _ZeroDisplayLinkProxy
- (instancetype)initWithTarget:(ZeroPlayerTexture *)target {
    self = [super init];
    if (self) {
        _target = target;
    }
    return self;
}
- (void)onDisplayLink:(CADisplayLink *)link {
    ZeroPlayerTexture *strongTarget = _target;
    if (strongTarget) {
        [strongTarget onDisplayLink:link];
    } else {
        [link invalidate];
    }
}
@end

@implementation ZeroPlayerTexture

@synthesize textureId = _textureId;
@synthesize playbackState = _playbackState;

- (instancetype)initWithURL:(NSURL *)url
                    headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                     isLive:(BOOL)isLive
                   registry:(NSObject<FlutterTextureRegistry> *)registry {
    self = [super init];
    if (self) {
        _registry = registry;
        _isDisposed = NO;
        _latestPixelBuffer = nil;
        _pixelBufferLock = OS_UNFAIR_LOCK_INIT;
        _lastAnchorSyncTime = 0.0;
        _awaitingFrame = YES;
        _isObservingPlayer = NO;

        // 1. C++ 共有メモリの作成
        _playbackState = zero_create_playback_state();

        // 2. AVPlayer & AVPlayerItemVideoOutput (NV12 Metal ゼロコピーテクスチャ出力)
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange (NV12) により CPU/GPU での BGRA 変換を排除し、
        // メモリ帯域を ~62% 削減したまま Flutter Engine (Impeller Metal) のシェーダーで直接 YUV->RGB 変換する。
        NSDictionary *pixBuffAttributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferMetalCompatibilityKey : @YES,
            (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };
        _videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];

        // Phase 1: HTTP Headers & Cookie 設定
        AVURLAsset *asset = nil;
        if (headers && headers.count > 0) {
            NSDictionary *options = @{ @"AVURLAssetHTTPHeaderFieldsKey": headers };
            asset = [AVURLAsset URLAssetWithURL:url options:options];
        } else {
            asset = [AVURLAsset URLAssetWithURL:url options:nil];
        }

        _playerItem = [AVPlayerItem playerItemWithAsset:asset];
        [_playerItem addOutput:_videoOutput];

        // Phase 2: 低遅延ライブ配信（LL-HLS）のレイテンシー最適化
        if (isLive) {
            _playerItem.automaticallyPreservesTimeOffsetFromLive = YES;
            _playerItem.configuredTimeOffsetFromLive = CMTimeMakeWithSeconds(1.5, 1000);
        }

        _player = [AVPlayer playerWithPlayerItem:_playerItem];
        _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

        if (isLive) {
            _player.automaticallyWaitsToMinimizeStalling = NO;
        }

        // 3. Flutter Texture 登録
        _textureId = [_registry registerTexture:self];

        // 4. CADisplayLink による VSync 駆動（Weak Proxy で Retain Cycle を防止）
        _ZeroDisplayLinkProxy *proxy = [[_ZeroDisplayLinkProxy alloc] initWithTarget:self];
#if TARGET_OS_OSX
        NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
        _displayLink = [screen displayLinkWithTarget:proxy selector:@selector(onDisplayLink:)];
#else
        _displayLink = [CADisplayLink displayLinkWithTarget:proxy selector:@selector(onDisplayLink:)];
#endif
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        // Duration / Track フレームレート / 再生状態監視
        [self setupObservers];
    }
    return self;
}

- (void)setupObservers {
    [_player addObserver:self
              forKeyPath:@"timeControlStatus"
                 options:NSKeyValueObservingOptionNew
                 context:kZeroPlayerStatusKVOContext];
    _isObservingPlayer = YES;

    __weak ZeroPlayerTexture *weakSelf = self;
    _endObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:_playerItem
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
                    ZeroPlayerTexture *strongSelf = weakSelf;
                    if (!strongSelf || strongSelf->_isDisposed) return;
                    [strongSelf syncPositionAnchorNow];
                    zero_set_status(strongSelf->_playbackState, ZERO_STATUS_COMPLETED);
                    strongSelf->_displayLink.paused = YES;
                }];

    [_playerItem.asset loadValuesAsynchronouslyForKeys:@[@"duration", @"tracks"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            ZeroPlayerTexture *strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_isDisposed) return;
            [strongSelf applyLoadedAssetMetadata];
        });
    }];
}

- (void)applyLoadedAssetMetadata {
    CMTime duration = _playerItem.asset.duration;
    double durSec = CMTimeGetSeconds(duration);
    if (isfinite(durSec) && durSec > 0.0) {
        zero_set_duration(_playbackState, (int64_t)(durSec * 1000.0));
    }

    if (@available(iOS 15.0, macOS 14.0, *)) {
        NSArray<AVAssetTrack *> *videoTracks = [_playerItem.asset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *track = videoTracks.firstObject;
        float fps = track ? track.nominalFrameRate : 0.0f;
        if (fps >= 15.0f && fps <= 120.0f) {
            _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context != kZeroPlayerStatusKVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (_isDisposed) return;

    [self syncPositionAnchorNow];
    AVPlayerTimeControlStatus status = _player.timeControlStatus;
    if (status == AVPlayerTimeControlStatusPlaying) {
        zero_set_status(_playbackState, ZERO_STATUS_PLAYING);
        _displayLink.paused = NO;
    } else if (status == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
        zero_set_status(_playbackState, ZERO_STATUS_BUFFERING);
        _displayLink.paused = NO;
    } else {
        zero_set_status(_playbackState, ZERO_STATUS_PAUSED);
        if (!_awaitingFrame) {
            _displayLink.paused = YES;
        }
    }
}

- (void)syncPositionAnchorNow {
    if (_isDisposed || !_playbackState) return;
    if (zero_get_duration(_playbackState) <= 0 && _playerItem) {
        CMTime itemDur = _playerItem.duration;
        double durSec = CMTimeGetSeconds(itemDur);
        if (isfinite(durSec) && durSec > 0.0) {
            zero_set_duration(_playbackState, (int64_t)(durSec * 1000.0));
        }
    }
    CMTime currentTime = _player.currentTime;
    double sec = CMTimeGetSeconds(currentTime);
    int64_t currentMs = (isfinite(sec) && sec > 0.0) ? (int64_t)(sec * 1000.0) : 0;
    float rate = _player.rate;
    zero_set_position_anchor(_playbackState, currentMs, rate > 0.0f ? rate : 1.0f);
    _lastAnchorSyncTime = CACurrentMediaTime();
}

- (void)onDisplayLink:(CADisplayLink *)link {
    if (_isDisposed) return;

    CFTimeInterval now = CACurrentMediaTime();
    CMTime itemTime = [_videoOutput itemTimeForHostTime:now];
    if ([_videoOutput hasNewPixelBufferForItemTime:itemTime]) {
        CVPixelBufferRef pixelBuffer = [_videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:nil];
        if (pixelBuffer) {
            os_unfair_lock_lock(&_pixelBufferLock);
            CVPixelBufferRef oldBuffer = _latestPixelBuffer;
            _latestPixelBuffer = pixelBuffer;
            os_unfair_lock_unlock(&_pixelBufferLock);
            if (oldBuffer) {
                CVBufferRelease(oldBuffer);
            }

            size_t width = CVPixelBufferGetWidth(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);
            zero_set_video_size(_playbackState, (int32_t)width, (int32_t)height);
            zero_increment_frame(_playbackState);

            [_registry textureFrameAvailable:_textureId];

            if (_awaitingFrame) {
                _awaitingFrame = NO;
                if (_player.timeControlStatus == AVPlayerTimeControlStatusPaused) {
                    _displayLink.paused = YES;
                }
            }
        }
    }

    // 再生中は ~250ms ごとにのみアンカーを補正書き込み（毎フレーム位置は Dart 側で外挿）
    if ((now - _lastAnchorSyncTime) >= kZeroDriftSyncIntervalSec) {
        [self syncPositionAnchorNow];
    }
}

#pragma mark - FlutterTexture Protocol (Zero-Copy)

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    os_unfair_lock_lock(&_pixelBufferLock);
    CVPixelBufferRef buffer = _latestPixelBuffer;
    if (buffer) {
        CVBufferRetain(buffer);
    }
    os_unfair_lock_unlock(&_pixelBufferLock);
    return buffer;
}

#pragma mark - Playback Controls

- (void)play {
    if (_isDisposed) return;
    _displayLink.paused = NO;
    [_player play];
    [self syncPositionAnchorNow];
    zero_set_status(_playbackState, ZERO_STATUS_PLAYING);
}

- (void)pause {
    if (_isDisposed) return;
    [_player pause];
    [self syncPositionAnchorNow];
    zero_set_status(_playbackState, ZERO_STATUS_PAUSED);
    if (!_awaitingFrame) {
        _displayLink.paused = YES;
    }
}

- (void)seekTo:(int64_t)positionMs {
    if (_isDisposed) return;
    _awaitingFrame = YES;
    _displayLink.paused = NO;
    CMTime targetTime = CMTimeMake(positionMs, 1000);
    float rate = _player.rate > 0.0f ? _player.rate : 1.0f;
    zero_set_position_anchor(_playbackState, positionMs, rate);
    _lastAnchorSyncTime = CACurrentMediaTime();

    __weak ZeroPlayerTexture *weakSelf = self;
    [_player seekToTime:targetTime
        toleranceBefore:kCMTimeZero
         toleranceAfter:kCMTimeZero
      completionHandler:^(BOOL finished) {
          ZeroPlayerTexture *strongSelf = weakSelf;
          if (!strongSelf || strongSelf->_isDisposed || !finished) return;
          [strongSelf syncPositionAnchorNow];
      }];
}

- (void)dispose {
    if (_isDisposed) return;
    _isDisposed = YES;

    [_displayLink invalidate];
    _displayLink = nil;

    if (_isObservingPlayer && _player) {
        [_player removeObserver:self forKeyPath:@"timeControlStatus" context:kZeroPlayerStatusKVOContext];
        _isObservingPlayer = NO;
    }
    if (_endObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_endObserver];
        _endObserver = nil;
    }

    [_player pause];
    _player = nil;
    _playerItem = nil;
    _videoOutput = nil;

    os_unfair_lock_lock(&_pixelBufferLock);
    CVPixelBufferRef bufferToRelease = _latestPixelBuffer;
    _latestPixelBuffer = nil;
    os_unfair_lock_unlock(&_pixelBufferLock);
    if (bufferToRelease) {
        CVBufferRelease(bufferToRelease);
    }

    [_registry unregisterTexture:_textureId];

    if (_playbackState) {
        zero_destroy_playback_state(_playbackState);
        _playbackState = nullptr;
    }
}

- (void)dealloc {
    [self dispose];
}

@end

#pragma clang diagnostic pop

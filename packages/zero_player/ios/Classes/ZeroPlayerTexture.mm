#import "ZeroPlayerTexture.h"
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/CADisplayLink.h>

@interface ZeroPlayerTexture () {
    NSObject<FlutterTextureRegistry> *_registry;
    AVPlayer *_player;
    AVPlayerItem *_playerItem;
    AVPlayerItemVideoOutput *_videoOutput;
    CADisplayLink *_displayLink;
    CVPixelBufferRef _latestPixelBuffer;
    ZeroPlaybackState *_playbackState;
    int64_t _textureId;
    BOOL _isDisposed;
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

        // 1. C++ 共有メモリの作成
        _playbackState = zero_create_playback_state();

        // 2. AVPlayer & AVPlayerItemVideoOutput (Metal ゼロコピーテクスチャ出力)
        NSDictionary *pixBuffAttributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
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
            _playerItem.configuredTimeOffsetFromLive = 1.5;
        }

        _player = [AVPlayer playerWithPlayerItem:_playerItem];
        _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

        if (isLive) {
            _player.automaticallyWaitsToMinimizeStalling = NO;
        }

        // 3. Flutter Texture 登録
        _textureId = [_registry registerTexture:self];

        // 4. CADisplayLink による 120Hz/60Hz VSync 駆動
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink:)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        // Duration 監視
        [self setupObservers];
    }
    return self;
}

- (void)setupObservers {
    __weak typeof(self) weakSelf = self;
    [_playerItem.asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_isDisposed) return;

            CMTime duration = strongSelf->_playerItem.asset.duration;
            int64_t durMs = (int64_t)(CMTimeGetSeconds(duration) * 1000);
            zero_set_duration(strongSelf->_playbackState, durMs);
        });
    }];
}

- (void)onDisplayLink:(CADisplayLink *)link {
    if (_isDisposed) return;

    CMTime itemTime = [_videoOutput itemTimeForHostTime:CACurrentMediaTime()];
    if ([_videoOutput hasNewPixelBufferForItemTime:itemTime]) {
        CVPixelBufferRef pixelBuffer = [_videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:nil];
        if (pixelBuffer) {
            @synchronized (self) {
                if (_latestPixelBuffer) {
                    CVBufferRelease(_latestPixelBuffer);
                }
                _latestPixelBuffer = pixelBuffer;
            }

            // 動画サイズを取得して共有メモリに反映
            size_t width = CVPixelBufferGetWidth(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);
            zero_set_video_size(_playbackState, (int32_t)width, (int32_t)height);
            zero_increment_frame(_playbackState);

            // Flutter Engine (Impeller) に新しいフレームの描画を通知
            [_registry textureFrameAvailable:_textureId];
        }
    }

    // 【重要】再生位置を C++ 共有メモリに直接書き込み
    // Dart 側は通信なしでこの数値を 0 ナノ秒で読み取れる
    CMTime currentTime = _player.currentTime;
    int64_t currentMs = (int64_t)(CMTimeGetSeconds(currentTime) * 1000);
    zero_set_position(_playbackState, currentMs);
}

#pragma mark - FlutterTexture Protocol (Zero-Copy)

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    @synchronized (self) {
        if (_latestPixelBuffer) {
            CVBufferRetain(_latestPixelBuffer);
            return _latestPixelBuffer;
        }
    }
    return nil;
}

#pragma mark - Playback Controls

- (void)play {
    if (_isDisposed) return;
    [_player play];
    zero_set_status(_playbackState, ZERO_STATUS_PLAYING);
}

- (void)pause {
    if (_isDisposed) return;
    [_player pause];
    zero_set_status(_playbackState, ZERO_STATUS_PAUSED);
}

- (void)seekTo:(int64_t)positionMs {
    if (_isDisposed) return;
    CMTime targetTime = CMTimeMake(positionMs, 1000);
    [_player seekToTime:targetTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    zero_set_position(_playbackState, positionMs);
}

- (void)dispose {
    if (_isDisposed) return;
    _isDisposed = YES;

    [_displayLink invalidate];
    _displayLink = nil;

    [_player pause];
    _player = nil;
    _playerItem = nil;
    _videoOutput = nil;

    if (_latestPixelBuffer) {
        CVBufferRelease(_latestPixelBuffer);
        _latestPixelBuffer = nil;
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

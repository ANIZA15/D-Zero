#import "ZeroPlayerPlugin.h"
#import "ZeroPlayerTexture.h"

@interface ZeroPlayerPlugin ()
@property (nonatomic, strong) NSObject<FlutterTextureRegistry> *registry;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ZeroPlayerTexture *> *players;
@end

@implementation ZeroPlayerPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
                                     methodChannelWithName:@"com.fexcy.zero_player"
                                     binaryMessenger:[registrar messenger]];
    ZeroPlayerPlugin *instance = [[ZeroPlayerPlugin alloc] initWithRegistry:[registrar textures]];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry {
    self = [super init];
    if (self) {
        _registry = registry;
        _players = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([@"create" isEqualToString:call.method]) {
        NSString *urlStr = call.arguments[@"url"];
        if (!urlStr) {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT" message:@"URL is required" details:nil]);
            return;
        }

        NSDictionary<NSString *, NSString *> *headers = call.arguments[@"headers"];
        BOOL isLive = [call.arguments[@"isLive"] boolValue];

        NSURL *url = [NSURL URLWithString:urlStr];
        ZeroPlayerTexture *player = [[ZeroPlayerTexture alloc] initWithURL:url
                                                                   headers:headers
                                                                    isLive:isLive
                                                                  registry:_registry];
        _players[@(player.textureId)] = player;

        // Dart 側へ textureId と C++ 共有メモリアドレス(stateAddress) を返す
        int64_t stateAddress = (int64_t)player.playbackState;
        result(@{
            @"textureId": @(player.textureId),
            @"stateAddress": @(stateAddress)
        });
    } else if ([@"play" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        ZeroPlayerTexture *player = _players[@(textureId)];
        [player play];
        result(nil);
    } else if ([@"pause" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        ZeroPlayerTexture *player = _players[@(textureId)];
        [player pause];
        result(nil);
    } else if ([@"seekTo" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        int64_t positionMs = [call.arguments[@"positionMs"] longLongValue];
        ZeroPlayerTexture *player = _players[@(textureId)];
        [player seekTo:positionMs];
        result(nil);
    } else if ([@"dispose" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        ZeroPlayerTexture *player = _players[@(textureId)];
        if (player) {
            [player dispose];
            [_players removeObjectForKey:@(textureId)];
        }
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

@end

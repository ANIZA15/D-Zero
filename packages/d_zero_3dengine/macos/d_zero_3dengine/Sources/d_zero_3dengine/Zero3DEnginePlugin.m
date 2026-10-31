#import "Zero3DEnginePlugin.h"
#import "Zero3DEngineTexture.h"

@interface Zero3DEnginePlugin ()
@property (nonatomic, strong) NSObject<FlutterTextureRegistry> *registry;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, Zero3DEngineTexture *> *engines;
@end

@implementation Zero3DEnginePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
                                     methodChannelWithName:@"com.fexcy.d_zero_3dengine"
                                     binaryMessenger:[registrar messenger]];
    Zero3DEnginePlugin *instance = [[Zero3DEnginePlugin alloc] initWithRegistry:[registrar textures]];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry {
    self = [super init];
    if (self) {
        _registry = registry;
        _engines = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([@"create" isEqualToString:call.method]) {
        int32_t width = [call.arguments[@"width"] intValue];
        int32_t height = [call.arguments[@"height"] intValue];
        if (width <= 0) width = 1280;
        if (height <= 0) height = 720;

        Zero3DEngineTexture *engine = [[Zero3DEngineTexture alloc] initWithWidth:width
                                                                          height:height
                                                                        registry:_registry];
        _engines[@(engine.textureId)] = engine;

        int64_t stateAddress = (int64_t)engine.engineState;
        int64_t ecsAddress = (int64_t)engine.ecsWorld;
        result(@{
            @"textureId": @(engine.textureId),
            @"stateAddress": @(stateAddress),
            @"ecsAddress": @(ecsAddress)
        });
    } else if ([@"resize" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        int32_t width = [call.arguments[@"width"] intValue];
        int32_t height = [call.arguments[@"height"] intValue];
        Zero3DEngineTexture *engine = _engines[@(textureId)];
        [engine resizeWidth:width height:height];
        result(nil);
    } else if ([@"start" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        [_engines[@(textureId)] startRendering];
        result(nil);
    } else if ([@"pause" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        [_engines[@(textureId)] pauseRendering];
        result(nil);
    } else if ([@"dispose" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        Zero3DEngineTexture *engine = _engines[@(textureId)];
        if (engine) {
            [engine dispose];
            [_engines removeObjectForKey:@(textureId)];
        }
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    for (Zero3DEngineTexture *engine in _engines.allValues) {
        [engine dispose];
    }
    [_engines removeAllObjects];
}

@end

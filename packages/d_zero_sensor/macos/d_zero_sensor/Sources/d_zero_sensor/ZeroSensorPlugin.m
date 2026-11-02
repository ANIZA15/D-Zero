#import "ZeroSensorPlugin.h"
#import "ZeroSensorTexture.h"

@interface ZeroSensorPlugin ()
@property (nonatomic, strong) NSObject<FlutterTextureRegistry> *registry;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ZeroSensorTexture *> *cameras;
@end

@implementation ZeroSensorPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
        methodChannelWithName:@"com.fexcy.d_zero_sensor"
              binaryMessenger:[registrar messenger]];
    ZeroSensorPlugin *instance = [[ZeroSensorPlugin alloc] initWithRegistry:[registrar textures]];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry {
    self = [super init];
    if (self) {
        _registry = registry;
        _cameras = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([@"createCamera" isEqualToString:call.method]) {
        int64_t stateAddress = [call.arguments[@"stateAddress"] longLongValue];
        int32_t facing = [call.arguments[@"facing"] intValue];
        int32_t preferredFps = [call.arguments[@"preferredFps"] intValue];
        ZeroCameraSharedState *state = (ZeroCameraSharedState *)(intptr_t)stateAddress;

        ZeroSensorTexture *cam = [[ZeroSensorTexture alloc] initWithState:state
                                                                   facing:facing
                                                             preferredFps:preferredFps
                                                                 registry:_registry];
        _cameras[@(cam.textureId)] = cam;
        [cam startCapture];

        result(@{
            @"textureId": @(cam.textureId),
            @"stateAddress": @((int64_t)(intptr_t)cam.cameraState)
        });
    } else if ([@"startCamera" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        [_cameras[@(textureId)] startCapture];
        result(nil);
    } else if ([@"stopCamera" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        [_cameras[@(textureId)] stopCapture];
        result(nil);
    } else if ([@"switchCamera" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        int32_t facing = [call.arguments[@"facing"] intValue];
        int32_t preferredFps = [call.arguments[@"preferredFps"] intValue];
        [_cameras[@(textureId)] switchCameraFacing:facing preferredFps:preferredFps];
        result(nil);
    } else if ([@"disposeCamera" isEqualToString:call.method]) {
        int64_t textureId = [call.arguments[@"textureId"] longLongValue];
        ZeroSensorTexture *cam = _cameras[@(textureId)];
        if (cam) {
            [cam dispose];
            [_cameras removeObjectForKey:@(textureId)];
        }
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    for (ZeroSensorTexture *cam in _cameras.allValues) {
        [cam dispose];
    }
    [_cameras removeAllObjects];
}

@end

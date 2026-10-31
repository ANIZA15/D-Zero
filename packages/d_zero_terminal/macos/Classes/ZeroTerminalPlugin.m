#import "ZeroTerminalPlugin.h"
#include "zero_terminal_state.h"

@implementation ZeroTerminalPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    // C++ FFI シンボルがリンカによって Dead-Strip されないよう ABI バージョンを参照
    volatile uint32_t abi = zero_terminal_abi_version();
    (void)abi;
    (void)registrar;
}

@end

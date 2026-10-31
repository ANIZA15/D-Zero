#include "include/d_zero_terminal/zero_terminal_plugin_c_api.h"
#include "../src/zero_terminal_state.h"

void ZeroTerminalPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
    (void)registrar;
    volatile uint32_t abi = zero_terminal_abi_version();
    (void)abi;
}

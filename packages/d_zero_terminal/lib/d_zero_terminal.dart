/// Ultra-lightweight, zero-allocation FFI PTY terminal emulator and VT100/TrueColor
/// engine for Flutter Impeller.
library d_zero_terminal;

export 'src/terminal_state_ffi.dart'
    show
        ZeroTerminalCursorStyle,
        ZeroTerminalStatus,
        ZeroTerminalKeyCode,
        ZeroTerminalStateNative,
        ZeroTerminalStateView,
        ZeroTerminalNativeBindings;
export 'src/controller.dart';
export 'src/widgets/z_pty_terminal.dart';
export 'src/widgets/z_terminal_hud.dart';
export 'src/widgets/z_terminal_minimap.dart';

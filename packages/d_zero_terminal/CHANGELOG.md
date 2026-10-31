## 0.1.4

* Initial release of `d_zero_terminal` v0.1.4.
* Added C++17 FFI 128-byte cache-line-aligned shared memory (`ZeroTerminalState`) with zero-allocation VT100/ANSI/TrueColor parser and POSIX `forkpty` shell execution.
* Added `ZPtyTerminal` (`ZTerminalEmulator`), `ZTerminalHud` (`ZTerminalTelemetryBar`), and `ZTerminalMinimap` (`ZScrollbackRadar`) zero-rebuild widgets.

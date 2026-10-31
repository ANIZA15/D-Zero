# d_zero_terminal_example

Interactive benchmark and standalone terminal application for `d_zero_terminal`.

## Features

- **`ZPtyTerminal` (`ZTerminalEmulator`)**: Zero-rebuild, single-pass `Canvas.drawRawAtlas` rendering over 128-byte C++17 FFI shared memory (`ZeroTerminalState`).
- **Real POSIX `forkpty` Shell**: Spawn `/bin/zsh` or `/bin/sh` directly and interact with keyboard & mouse wheel scrollback.
- **`ZTerminalHud` & `ZTerminalMinimap`**: Zero-allocation telemetry bar (MB/s throughput, ns/byte parse latency, bytes & ANSI sequences parsed) and scrollback radar minimap.

# ⚡️ d_zero_terminal

**Ultra-lightweight, zero-allocation FFI PTY terminal emulator for Flutter & Impeller with C++17 VT100/ANSI/TrueColor parsing, POSIX `forkpty` execution, and single-pass `Canvas.drawRawAtlas` rendering.**

[![Pub Version](https://img.shields.io/pub/v/d_zero_terminal.svg?style=flat-square)](https://pub.dev/packages/d_zero_terminal)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Impeller: Metal & Vulkan](https://img.shields.io/badge/Impeller-Metal%20%2F%20Vulkan-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 🚀 Key Architecture

1. **128-Byte (2 Cache Lines) C++17 FFI Shared Memory (`ZeroTerminalState`)**:
   - **Cache Line 0 (`0..63`)**: Grid geometry (`cols`, `rows`), cursor position & style (`block`, `beam`, `underline`), scrollback offset, POSIX `forkpty` child PID, and Seqlock counter (`seq`).
   - **Cache Line 1 (`64..127`)**: Live telemetry (`bytesProcessed`, `escapeSeqsParsed`, `throughputMbPerSec`, `parseLatencyNs`, 128-bit `dirtyRowMask`).
   - Protected by `ZERO_TERM_MAGIC_ALIVE` (`0x5A54524D`) canary validation and registry checks for 100% Double-Free and Use-After-Free immunity.
2. **Zero-Copy SoA Viewport Buffers (`Uint32List` / `Uint8List`)**:
   - Fixed-address Structure-of-Arrays (`viewportCodepoints`, `viewportFgArgb`, `viewportBgArgb`, `viewportAttrs`) mapped directly into Dart via `Pointer.asTypedList` with **0 FFI calls per cell** and **0 heap allocations**.
3. **Zero-Channel POSIX `forkpty` + C++17 VT100/TrueColor Parser**:
   - Dedicated C++ PTY reader thread parses 16-color, 256-color, and 24-bit TrueColor (`\x1b[38;2;r;g;bm`) sequences, UTF-8 codepoints, cursor motions, and Alternate Screen (`?1049h`/`l`) off the UI thread.
   - Dart UI thread coalesces updates at VSync (120Hz/240Hz) and flushes the visible grid in a single `Canvas.drawRawAtlas` draw call.

---

## 📦 Exported `Z` Widgets & Controllers

| Widget / Class | Alias / Legacy | Description |
| :--- | :--- | :--- |
| **`ZPtyTerminal`** | `ZTerminalEmulator` (`ZeroPtyTerminal`) | Zero-rebuild, single-pass `drawRawAtlas` terminal viewport with hardware keyboard input, mouse selection, and scrollback wheel support. |
| **`ZTerminalHud`** | `ZTerminalTelemetryBar` (`ZeroTerminalHud`) | Zero-allocation telemetry HUD painting live C++ parser throughput (`MB/s`), latency (`ns/byte`), bytes parsed, and grid/cursor state via `ZeroNumberPainter`. |
| **`ZTerminalMinimap`** | `ZScrollbackRadar` (`ZeroTerminalMinimap`) | Zero-allocation 256-bin scrollback density & color radar strip with interactive drag-to-scrub lens. |
| **`ZeroPtyController`** | - | 128-byte FFI shared-memory & POSIX `forkpty` controller (`spawnShell`, `feedAnsiBytes`, `writeInputText`, `sendKey`, `resize`, `runStressBurst`). |

---

## 💻 Usage Example

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_terminal/d_zero_terminal.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final ZeroPtyController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ZeroPtyController(cols: 96, rows: 28, scrollbackCapacity: 2048);
    // Spawn a real POSIX shell (/bin/zsh) or feed ANSI sequences directly:
    _controller.spawnShell();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ZPtyTerminal(
            controller: _controller,
            autoResize: true,
          ),
        ),
        ZTerminalMinimap(controller: _controller),
      ],
    );
  }
}
```

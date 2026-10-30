# ⚡️ zero_core

**Core foundation library for zero-allocation Flutter widgets and high-performance Impeller rendering.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Key Components

* **`ZWidget` / `ZeroRenderBox`**:
  Base `LeafRenderObjectWidget` and `RenderBox` primitives that bypass `Widget.build()` and `setState()`, triggering only `markNeedsPaint()` with an automatic repaint boundary.
* **`ZeroNumberPainter`**:
  Pre-rasterized ASCII/UTF-16 glyph table renderer that draws integers, decimals, and timecodes (`00:00.00`) directly to `Canvas` without `int.toString()` or heap string allocations.
* **`FloatRingBuffer`**:
  Fixed-capacity `Float32List`-backed circular buffer for zero-allocation time-series, audio waveform, and telemetry streaming.
* **`ZeroPool<T>`**:
  Pre-warmed object pool eliminating per-frame heap allocations in 60fps/120fps render loops.
* **`ZeroFrameScheduler` & `ZeroNotifier`**:
  Lightweight V-Sync ticker and value notification primitives designed for direct RenderBox binding.

---

## 🚀 Usage

```dart
import 'package:zero_core/zero_core.dart';

// Fixed-capacity ring buffer with zero heap allocation on write
final buffer = FloatRingBuffer(1024);
buffer.push(0.42);
```

## 📄 License

MIT License © 2026 fexcy

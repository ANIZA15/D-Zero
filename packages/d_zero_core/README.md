# ⚡️ d_zero_core

**Core foundation library for zero-allocation Flutter widgets and high-performance Impeller rendering.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 💡 Architectural Overview

`d_zero_core` provides the foundational building blocks shared by all packages in the **D-Zero** ecosystem. It eliminates widget tree rebuilds (`setState`) and per-frame garbage collection (GC) stalls on 60fps/120fps hot paths.

### Key Components

| Component | Role & Zero-Allocation Mechanism |
| :--- | :--- |
| **`ZWidget` / `ZLeafWidget` / `ZSingleChildWidget`** | Base widget contracts that bypass `Element.rebuild()` cascades and bind directly to a `ZeroRenderBox`. |
| **`ZeroRenderBox`** | Base `RenderBox` with `isRepaintBoundary = true` and O(1) V-Sync slot registration via `ZeroFrameScheduler`. |
| **`ZeroNumberPainter`** | Pre-rasterizes ASCII digits (`0..9`) and symbols (`:`, `.`, `-`, `/`, `+`, `,`, `%`, `$`, `¥`, ` FPS`, ` ms`, `°`) into a reference-counted GPU `ui.Image` atlas, flushing numbers in **a single `Canvas.drawRawAtlas` call** with `0` `String` allocations. |
| **`FloatRingBuffer`** | Fixed-capacity `Float32List` circular buffer supporting $O(1)$ `push`, `min`, `max`, `average`, and `copyRangeTo` without array resizing. |
| **`ZeroPool<T>`** | Pre-warmed object pool (`acquire` / `release`) that prevents short-lived object allocations in render loops. |
| **`ZeroFrameScheduler`** | Shared single-`Ticker` V-Sync dispatcher using O(1) slot indexing (`ZeroSlottedFrameListener`) with zero iterator allocations per frame. |
| **`ZeroIntNotifier` / `ZeroDoubleNotifier`** | Lightweight reactive primitives with index-based listener dispatch and tombstone compaction (`0` closure or list copy allocations). |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_core: ^0.1.0
```

### 1. Fixed-Capacity Ring Buffer & Object Pool
```dart
import 'package:d_zero_core/d_zero_core.dart';

// O(1) circular buffer backed by Float32List (0 allocations on push)
final ringBuffer = FloatRingBuffer(128);
ringBuffer.push(0.85);

// Pre-warmed object pool for reusable render items
final pool = ZeroPool<List<double>>(
  factory: () => List<double>.filled(4, 0.0),
  reset: (list) => list.fillRange(0, 4, 0.0),
  initialCapacity: 64,
);
final item = pool.acquire();
pool.release(item);
```

### 2. Zero-Allocation Number Rendering (`ZeroNumberPainter`)
```dart
import 'package:flutter/rendering.dart';
import 'package:d_zero_core/d_zero_core.dart';

final painter = ZeroNumberPainter(
  style: const TextStyle(fontSize: 20, fontFamily: 'monospace'),
);

void paintMetrics(Canvas canvas, Offset offset) {
  // Draws integer, decimal, currency, percentage, and timecode with 0 String allocations
  painter.paintInt(canvas, offset, 120450, minDigits: 6);
  painter.paintDouble(canvas, offset + const Offset(0, 24), 98.6, fractionDigits: 1);
  painter.paintCurrency(canvas, offset + const Offset(0, 48), 64250.75);
  painter.paintPercent(canvas, offset + const Offset(0, 72), 42.5);
  painter.paintTimecode(canvas, offset + const Offset(0, 96), 125400);
}
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) directory contains an interactive benchmark comparing `d_zero_core` (`ZeroRenderBox` + `FloatRingBuffer` + `ZeroPool` + `ZeroNumberPainter`) against traditional Flutter (`setState` + `List.removeAt(0)` + `Path`), displaying live **FPS, UI CPU Load (%), RSS Memory (Current/Peak MB), Widget Rebuilds, and Heap Allocations**.

```bash
cd packages/d_zero_core/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy

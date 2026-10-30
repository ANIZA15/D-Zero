# ⚡️ d_zero_canvas

**Zero-allocation massive-element & 3D canvas widgets (`Z3DMesh`, `ZRibbon`, `ZDanmaku`, `ZInfiniteGrid`, `ZFreehandCanvas`) for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Distributed `Z` Widgets & Controllers

| Widget | Active Alias | Controller | Zero-Allocation Architecture |
| :--- | :--- | :--- | :--- |
| **`Z3DMesh`** | `Z3DGlobe` | `Zero3DMeshController` | Real-time 3D wireframe & flat-shaded sphere/torus mesh engine using SoA `Float32List` vertex buffers, in-place depth sorting, and a single `Canvas.drawVertices` / `drawRawPoints` batch. |
| **`ZRibbon`** | `ZLowLatencyInk` | `ZeroRibbonController` | 120Hz/240Hz pressure-sensitive triangle-strip ribbon trail rendered via a single `Canvas.drawVertices(VertexMode.triangleStrip)` call. |
| **`ZDanmaku`** | `ZChatStream` | `ZeroDanmakuController` | Fixed-capacity SoA (`_x`, `_y`, `_speed`, `_width` `Float32List`) + pooled `TextPainter` slots that step and render live bullet comments inside a single `ZeroRenderBox` (`0` `Positioned`/`Text` widgets). |
| **`ZInfiniteGrid`** | `ZCanvasGrid` | `ZeroViewportController` | Interactive 2D pan/zoom grid that packs visible minor/major grid lines into a pre-allocated `Float32List` and flushes them in a single `Canvas.drawRawPoints(PointMode.lines)` call with `ZeroNumberPainter` coordinate HUD. |
| **`ZFreehandCanvas`** | - | `ZeroFreehandController` | 120Hz/240Hz low-latency stylus/touch drawing canvas storing line segments in a flat `Float32List` (`0` `Path` or `Offset` allocations during pointer move). |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_canvas: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_canvas/d_zero_canvas.dart';

final danmakuCtrl = ZeroDanmakuController(capacity: 64)..emit('⚡️ 120fps Danmaku!');
final viewportCtrl = ZeroViewportController();
final freehandCtrl = ZeroFreehandController(maxSegments: 2048);

Column(
  children: [
    ZDanmaku(controller: danmakuCtrl, size: const Size(360, 120)),
    ZInfiniteGrid(controller: viewportCtrl, size: const Size(360, 180)),
    ZFreehandCanvas(controller: freehandCtrl, size: const Size(360, 180)),
  ],
);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app compares `d_zero_canvas` (`ZDanmaku` + `ZInfiniteGrid` + `ZFreehandCanvas`) against traditional `Stack` + `Positioned` + `Text` bullet streams with live **FPS, UI CPU Load (%), RSS Memory (MB), and Rebuild counters**.

```bash
cd packages/d_zero_canvas/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy

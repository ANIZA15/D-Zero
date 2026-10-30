# ⚡️ d_zero_sensor

**Zero-allocation 3D LiDAR point cloud (`Z3DPointCloud`), camera bounding-box scanner overlay (`ZBarcodeScanner`), gyroscope compass (`ZCompass`), and 2D spirit leveler (`ZLeveler`) widgets for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Distributed `Z` Widgets & Controllers

| Widget | Active Alias | Controller / Listenable | Zero-Allocation Architecture |
| :--- | :--- | :--- | :--- |
| **`Z3DPointCloud`** | `ZLidarView` | `ZeroPointCloudController` | 3D spatial depth / LiDAR point cloud viewer storing `(x, y, z, intensity)` in SoA `Float32List` arrays and flushing depth-bucketed 3D projections via `Canvas.drawRawPoints(PointMode.points)`. |
| **`ZBarcodeScanner`** | `ZCameraPreview` | `ZeroDetectionController` | Stores up to `capacity` ML/barcode bounding boxes in a flat `Float32List` (`[left, top, right, bottom, confidence]`) and renders corner reticles, animated laser scan line, and `ZeroNumberPainter.paintPercent` confidence tags with `0` per-box widgets or strings. |
| **`ZCompass`** | - | `ValueListenable<double>` | Pre-records 72 compass dial ticks into a GPU `ui.Picture` once on layout, rotates the canvas directly on heading updates, and renders center degrees (`°`) via `ZeroNumberPainter.paintWithSuffix`. |
| **`ZLeveler`** | - | `ZeroTiltController` | 2D spirit bubble leveler storing `(pitch, roll)` in a `Float32List(2)`, caching crosshair rings in a `ui.Picture`, and drawing pitch/roll degrees via `ZeroNumberPainter`. |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_sensor: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_sensor/d_zero_sensor.dart';

final detectionCtrl = ZeroDetectionController(capacity: 16)
  ..setDetection(0, 24.0, 24.0, 140.0, 96.0, 98.5);
final headingDeg = ZeroDoubleNotifier(125.0);
final tiltCtrl = ZeroTiltController(pitch: 1.5, roll: -0.8);

Row(
  children: [
    ZBarcodeScanner(controller: detectionCtrl, size: const Size(260, 160)),
    ZCompass(headingListenable: headingDeg, size: const Size(120, 120)),
    ZLeveler(controller: tiltCtrl, size: const Size(120, 120)),
  ],
);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app streams 12 simultaneous ML detection bounding boxes and 120Hz IMU compass/tilt updates, comparing `d_zero_sensor` against traditional `Stack` + `Positioned` + `Text` overlays with live **FPS, UI CPU Load (%), RSS Memory (MB), and Rebuild counters**.

```bash
cd packages/d_zero_sensor/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy

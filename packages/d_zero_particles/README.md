# ⚡️ d_zero_particles

**Ultra high-performance, zero-allocation particle simulation and batch rendering widget for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Distributed Widgets & Components

* **`ZParticles`**:
  A `LeafRenderObjectWidget` that simulates and renders thousands of particles at 120fps using a contiguous Structure-of-Arrays (`Float32List`) buffer and `Canvas.drawRawPoints` batching.
* **`ZeroParticleController`**:
  Controls burst emissions, continuous particle streams, gravity, drag, and lifecycle without triggering widget rebuilds.
* **`ZeroParticleBuffer`**:
  Contiguous typed-data particle storage with zero per-frame object allocations.

---

## 🚀 Usage

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

final controller = ZeroParticleController(maxParticles: 5000);

ZParticles(
  controller: controller,
  pointSize: 4.0,
);
```

## 📄 License

MIT License © 2026 fexcy

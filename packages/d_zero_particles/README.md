# ⚡️ d_zero_particles

**Ultra high-performance, zero-allocation SIMD particle simulation and confetti batch rendering for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 💡 Architecture: Structure-of-Arrays (SoA) & 4-Lane SIMD

Traditional object-oriented particle engines (`List<Particle>`) suffer from CPU cache misses (pointer chasing) and thousands of `Canvas.drawCircle` / `Paint` / `Offset` allocations per frame.

`d_zero_particles` eliminates both bottlenecks:
1. **Contiguous SoA Memory (`ZeroParticleBuffer`)**: Stores positions, velocities, and lifespans in flat, 16-byte aligned `Float32List` / `Float32x4List` views.
2. **Branchless 4-Lane SIMD Physics (`Float32x4`)**: Steps 2 particles (4 floats: `x0, y0, x1, y1`) per CPU instruction using vector comparisons (`lessThan`, `greaterThan`, `select`, `clamp`).
3. **Single-Call GPU Batching**: Flushes up to `10,000+` particles to Impeller in a single `Canvas.drawRawPoints(PointMode.points, positions, paint)` call.

---

## 📦 Distributed `Z` Widgets & Controllers

| Symbol | Kind | Description |
| :--- | :--- | :--- |
| **`ZParticles`** | Widget | Simulates and renders thousands of particles at 120fps in a single `Canvas.drawRawPoints` call (`legacy: ZeroParticles`). |
| **`ZeroParticleController`** | Controller | Manages `ZeroParticleBuffer` lifecycle, `ZeroParticleConfig` (gravity, bounce, friction, maxSpeed), and safe post-dispose fallbacks. |
| **`ZConfetti`** | Widget | Multi-palette celebration confetti overlay rendered in batched point/ribbon passes with zero per-frame object allocations (`legacy: ZeroConfetti`). |
| **`ZeroConfettiController`** | Controller | Triggers directional/radial confetti bursts (`burst(count: 80)`) backed by SoA `Float32List` buffers. |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_particles: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

final particleCtrl = ZeroParticleController(
  capacity: 5000,
  config: const ZeroParticleConfig(gravity: 98.0, bounce: 0.85),
);
final confettiCtrl = ZeroConfettiController(capacity: 160);

Stack(
  children: [
    ZParticles(
      controller: particleCtrl,
      color: const Color(0xFF00E5FF),
      pointSize: 2.5,
    ),
    ZConfetti(
      controller: confettiCtrl,
      isRunning: true,
    ),
  ],
);

// Trigger a celebration burst at any time with 0 heap allocations:
confettiCtrl.burst(count: 80);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app lets you switch between `2,000`, `5,000`, and `10,000` simultaneous particles comparing `ZParticles` (SIMD SoA + `drawRawPoints`) against traditional `List<Particle>` + `drawCircle`, displaying live **FPS, UI CPU Load (%), RSS Memory (MB), Rebuilds, and Allocations**.

```bash
cd packages/d_zero_particles/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy

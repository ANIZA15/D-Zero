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
3. **Single-Call GPU Batching**: Flushes up to `100,000+` particles to Impeller in a single `Canvas.drawRawPoints(PointMode.points, positions, paint)` call, with automatic `ZParticlePointStyle.square` support for extreme particle densities.

---

## 📦 Distributed `Z` Widgets & Controllers

| Symbol | Kind | Description |
| :--- | :--- | :--- |
| **`ZParticles`** | Widget | Simulates and renders up to 100,000+ particles at 120fps in a single `Canvas.drawRawPoints` call (`legacy: ZeroParticles`). |
| **`ZeroParticleController`** | Controller | Manages `ZeroParticleBuffer` lifecycle, `ZeroParticleConfig` (gravity, bounce, friction, maxSpeed), and safe post-dispose fallbacks. |
| **`ZConfetti`** | Widget | Multi-palette celebration confetti overlay rendered in batched point/ribbon passes with zero per-frame object allocations (`legacy: ZeroConfetti`). |
| **`ZeroConfettiController`** | Controller | Triggers directional/radial confetti bursts (`burst(count: 80)`) backed by SoA `Float32List` buffers. |
| **`ZReactionStream`** | Widget | Live-stream floating hearts/reactions fountain (`ZFloatingHearts`, `legacy: ZeroReactionStream`) backed by SoA `Float32List` physics and batched `Canvas.drawRawPoints`. |
| **`ZeroReactionController`** | Controller | Emits floating reaction particles (`emit(count: 4)`) and steps upward sine-wave drift in place with zero heap allocations. |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_particles: ^0.1.7
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

final particleCtrl = ZeroParticleController(
  capacity: 15000,
  config: const ZeroParticleConfig(gravity: 98.0, bounce: 0.85),
);
final confettiCtrl = ZeroConfettiController(capacity: 360);
final reactionCtrl = ZeroReactionController(capacity: 192);

Stack(
  fit: StackFit.expand,
  children: [
    ZParticles(
      controller: particleCtrl,
      color: const Color(0xFF2563EB),
      pointSize: 2.5,
      pointStyle: ZParticlePointStyle.round,
    ),
    ZConfetti(
      controller: confettiCtrl,
      isRunning: true,
    ),
    Align(
      alignment: Alignment.bottomRight,
      child: ZReactionStream(controller: reactionCtrl),
    ),
  ],
);

// Trigger celebration bursts and reactions at any time with 0 heap allocations:
confettiCtrl.burst(count: 140);
reactionCtrl.emit(count: 16);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app features a clean Material 3 light UI that lets you switch between **`3,000`, `15,000`, `50,000`, and `100,000`** simultaneous particles, comparing `D-Zero` (`ZParticles` + `ZConfetti` + `ZReactionStream` using 4-lane SIMD SoA & `Canvas.drawRawPoints`) against traditional Flutter (`List<Particle>` + `CustomPaint` + `setState`).

### Live Runtime Telemetry & Interactive Controls
- **FPS & 60-Frame Histogram** (`ZFPSMonitor`): Real-time VSync frame rate and frame-time bar chart rendered with zero widget rebuilds.
- **CPU Usage (%) & Frame Time (`ms`)** (`ZPriceTicker`): Measured directly from Flutter Engine `FrameTiming` (`buildDuration + rasterDuration`) and `Stopwatch`.
- **Active Particle Count (`ZCounter`) & Real Rebuild Count**: Tracks actual `build()` invocations (`Rebuild: N`) for both `D-Zero` and `従来` modes.
- **Action Toolbar**: Trigger additional confetti bursts (`紙吹雪バースト`), reaction streams (`リアクション追加`), or reset particle positions (`リセット`) on demand.

```bash
cd packages/d_zero_particles/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy

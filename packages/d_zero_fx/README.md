# ⚡️ d_zero_fx

**Zero-allocation, zero-`saveLayer` visual effects, Impeller GLSL 460 fragment shaders, 3D metaballs, and 3D perspective tilt (`ZShaderSurface`, `ZMetaballs3D`, `ZMeshGradient`, `Z3DTilt`, `ZShimmer`, `ZBlur`, `ZRipple`, `ZLiquidProgress`) for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 💡 Why Zero-`saveLayer` & Direct GPU Shaders Matter on Impeller

Standard Flutter effects such as `BackdropFilter` and `ShaderMask` force the GPU to allocate and flush offscreen render targets (`Canvas.saveLayer`). When multiple effects are visible on a scrolling list or live dashboard, GPU bandwidth saturates and frame rates drop below 60/120fps.

`d_zero_fx` renders visual effects, 3D transformations, and GLSL 460 shaders in a single pass with **zero `saveLayer` calls** and **zero per-frame heap allocations**:

| Widget | Active Alias | Controller | Zero-Allocation & Zero-`saveLayer` Mechanism |
| :--- | :--- | :--- | :--- |
| **`ZShaderSurface`** | `ZRuntimeShader` | `ZeroShaderController` | Direct Impeller GLSL 460 `FragmentProgram` (`shaders/z_plasma.frag`) surface updating uniforms from a fixed `Float32List(16)` with automatic software fallback. |
| **`ZMetaballs3D`** | `ZRaymarchSurface` | `ZeroMetaballsController` | 3D implicit isosurface / raymarched metaball field (`shaders/z_metaballs.frag`) backed by an SoA `Float32List` (`x, y, z, radius`). |
| **`ZMeshGradient`** | `ZFluidGradient` | `ZeroMeshGradientController` | Interactive fluid mesh gradient rendered via a single `Canvas.drawVertices(VertexMode.triangles)` call over pre-allocated `Float32List` / `Int32List` buffers. |
| **`Z3DTilt`** | `ZParallaxContainer` | `Zero3DTiltController` | 60/120fps 3D perspective tilt container reusing a single `Matrix4` buffer with a zero-`saveLayer` specular light sheen overlay. |
| **`ZShimmer`** | `ZSkeleton` | - | Pre-computes a 12-band swept highlight `Paint` table inside `Canvas.clipRRect` (`0` `ShaderMask`, `0` `LinearGradient.createShader` per frame). |
| **`ZBlur`** | `ZGlassContainer` | - | Specular frosted glass card rendered via layered translucent base, top specular highlight, and rim border (`0` `BackdropFilter` offscreen pass). |
| **`ZRipple`** | `ZInkWell` | `ZeroRippleController` | Multi-touch SoA circular buffer (`_x`, `_y`, `_progress` `Float32List`) with a 16-step alpha `Paint` lut. |
| **`ZLiquidProgress`** | `ZWaveFilter` | - | Circular wave tank drawn via a pre-allocated `Float32List` sine wave polygon (`Canvas.drawRawPoints`) + `ZeroNumberPainter.paintPercent`. |
| **`ZSwipeDeck`** | `ZTinderCards` | `ZeroSwipeDeckController` | Physics-driven 3-card stack with 2D drag/rotation transforms and `ZeroNumberPainter` card index readout (`0` widget tree rebuilds). |
| **`ZScratchCard`** | `ZScratchOff` | `ZeroScratchCardController` | Grid-bitmask scratch-off lottery surface (`Uint8List` revealed cells) with real-time `ZeroNumberPainter.paintPercent` reveal tracking (`0` `saveLayer`). |
| **`ZBeforeAfterSlider`** | `ZImageComparison` | `ValueListenable<double>` | Interactive split-screen Before/After comparison view using dual `Canvas.clipRect` regions (`0` offscreen buffers). |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_fx: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_fx/d_zero_fx.dart';

final rippleCtrl = ZeroRippleController(capacity: 16);
final liquidLevel = ZeroDoubleNotifier(0.68);

Column(
  children: [
    const ZShimmer(size: Size(220, 24), borderRadius: 8),
    const ZBlur(size: Size(200, 100), highlightIntensity: 0.25),
    ZRipple(controller: rippleCtrl, size: const Size(200, 80)),
    ZLiquidProgress(valueListenable: liquidLevel, size: const Size(110, 110)),
  ],
);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app compares `d_zero_fx` (`0` `saveLayer` passes) against traditional `BackdropFilter` (`ImageFilter.blur`) + `CircularProgressIndicator` with live **FPS, UI CPU Load (%), RSS Memory (MB), and Rebuild counters**.

```bash
cd packages/d_zero_fx/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy

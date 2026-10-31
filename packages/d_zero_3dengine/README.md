# ⚡️ d_zero_3dengine

**Zero-allocation, zero-rebuild 3D Game Engine viewport for Flutter & Impeller with Unreal Engine Nanite-style meshlet cluster culling, hardware Ray Tracing, and 120Hz / 144Hz / 240Hz / Uncapped frame scheduling.**

[![Pub Version](https://img.shields.io/pub/v/d_zero_3dengine.svg?style=flat-square)](https://pub.dev/packages/d_zero_3dengine)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Impeller: Metal 3 & DirectX 12](https://img.shields.io/badge/Engine-Metal%203%20%2F%20DX12%20%2F%20Impeller-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 🚀 Key Architecture

1. **128-Byte (2 Cache Lines) C++ FFI Shared State (`Zero3DEngineState`)**:
   - **Cache Line 0 (`0..63`)**: Dart UI / Game Logic writes camera orbit, directional lighting, Nanite screen-space error thresholds, and FPS cap (`60 / 120 / 144 / 240 / Uncapped`) with **0ns latency**.
   - **Cache Line 1 (`64..127`)**: Native Render Thread writes live `renderFps`, `frameTimeMs`, detected `displayRefreshHz`, `activeClusters`, `visibleTriangles`, and `raysTracedK` without false sharing.
   - Protected by `ZERO_3D_MAGIC_ALIVE` (`0x5A334445`) canary validation, 64-byte alignment checks, and lock-free Seqlocks verified under **Clang ASan, UBSan, and TSan**.
2. **Triple-Buffered Zero-Copy GPU Viewport**:
   - Uses 3-slot `IOSurface` (`CVMetalTextureCache`) ring buffers on macOS Metal 3 and Impeller GLSL 460 Ray Tracing shaders (`zero_3d_raytrace.frag`) so high-refresh monitors (**144Hz / 240Hz**) and **Uncapped FPS** loops never block on VSync locks.
3. **Nanite-Style Meshlet Cluster Culling & Ray Tracing**:
   - Evaluates hierarchical meshlet bounding spheres and screen-space LOD error thresholds in pre-allocated Structure-of-Arrays (`Float32List`) buffers alongside real-time ray-traced soft shadows and specular reflections.

---

## 📦 Exported `Z` Widgets & Controllers

| Widget / Class | Alias / Legacy | Description |
| :--- | :--- | :--- |
| **`ZViewport3D`** | `ZScene3D` (`ZeroViewport3D`) | Zero-copy 3D game engine viewport with interactive orbit/zoom, Nanite cluster overlay, and Ray Tracing shader pipeline. |
| **`ZEngineTelemetryHud`** | `Z3DStatsOverlay` (`ZeroEngineTelemetryHud`) | Zero-allocation `ZeroRenderBox` HUD painting live Render FPS, Monitor Refresh Hz (144/240Hz), Active Nanite Clusters, Visible Triangles, and Rays Traced via `ZeroNumberPainter`. |
| **`Zero3DEngineController`** | - | 128-byte FFI shared-memory controller managing camera, lighting, Nanite LOD threshold, and 144Hz/240Hz/Uncapped scheduling. |

---

## 💻 Usage Example

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_3dengine/d_zero_3dengine.dart';

class GameEnginePreview extends StatefulWidget {
  const GameEnginePreview({super.key});

  @override
  State<GameEnginePreview> createState() => _GameEnginePreviewState();
}

class _GameEnginePreviewState extends State<GameEnginePreview> {
  late final Zero3DEngineController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Zero3DEngineController.simulated(
      renderMode: Zero3DRenderMode.hybridNaniteRt,
      fpsMode: Zero3DFpsMode.cap144, // Supports 120Hz, 144Hz, 240Hz, and Uncapped
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ZViewport3D(
        controller: _controller,
        size: const Size(800, 480),
        showTelemetryHud: true,
      ),
    );
  }
}
```

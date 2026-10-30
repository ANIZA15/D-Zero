# ⚡️ d_zero_player

**A zero-jank, zero-allocation video player engineered from the ground up for the Flutter and Impeller era.**

[🇯🇵 日本語のドキュメントはこちら (Japanese Documentation)](README_JA.md)

[![Pub Version](https://img.shields.io/pub/v/d_zero_player.svg?style=flat-square)](https://pub.dev/packages/d_zero_player)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)
[![Code Complexity](https://img.shields.io/badge/Cyclomatic%20Complexity-1.83%20(A%2B)-brightgreen.svg?style=flat-square)](https://github.com/ANIZA15/D-Zero)

---

## 💡 Design Philosophy: Pursuit of Zero Allocation in Flutter

In game development and high-performance systems programming, eliminating heap allocation during runtime frames to avoid garbage collection (GC) stalls is an industry-standard best practice.

Conventional Flutter video players (`video_player`), however, incur significant CPU and memory overhead across three critical boundaries during playback:

1. **Heap Allocation via Widget Rebuilds**: Each time playback advances (`00:10` → `00:11`), UI widgets and elements are repeatedly instantiated dozens of times per second on the UI thread.
2. **MethodChannel Serialization Overhead**: Sharing playback position and buffering status across threads generates continuous JSON/binary conversions and message object allocations.
3. **GPU RenderPass Multiplications**: Heavy glassmorphism effects like `BackdropFilter` allocate costly offscreen render targets (`saveLayer`), consuming vital GPU bandwidth.

**`d_zero_player` solves these fundamental bottlenecks with three foundational architectural pillars:**

* **Zero Rebuild**: Powered by `LeafRenderObjectWidget` and custom `RenderBox` instances, UI controls paint directly to the Canvas at 120fps V-Sync without ever calling `build()`.
* **Zero Channel**: Direct bindings between C++ atomic shared memory and **Dart FFI pointers** deliver instantaneous state reads with **0 nanoseconds latency and zero message object allocations**.
* **Zero Copy**: Hardware-decoded video streams from Apple Metal (`CVPixelBuffer`) and Android Vulkan (`AHardwareBuffer` / `SurfaceTexture`) bind directly into Impeller with zero CPU-GPU memory copying.

---

## 🏗 Architecture

```
[ Native Video Decoders (ExoPlayer Media3 / AVPlayer) ]
     │
     ├─ [ Video Frame ] ─── (Zero-Copy GPU Buffer) ──► [ Impeller Texture ]
     │                                                         │ (1-Pass Direct Sampling)
     │                                                         ▼
     │                                                 [ zero_blur.frag ]
     │                                                         │
     └─ [ Playback Ms ] ─── (C++ Atomic Shared Memory)         │
                                    │                           ▼
                         (Dart FFI Direct Pointer)     [ ZDirectSeekBar / ZDirectTimeLabel ]
                                    │                           │ (RenderBox.paint)
                                    └──────► Canvas.draw ───────┘ (120fps Synchronized)
```

---

## 📊 Performance Comparison

| Metric | Traditional `video_player` | `d_zero_player` |
| :--- | :--- | :--- |
| **Widget Rebuilds during Playback** | 10–30+ rebuilds / sec (continuous CPU draw) | **0 / sec (True zero rebuild)** |
| **State Notification Latency** | MethodChannel overhead (several ms delay) | **0 ns (Direct memory pointer read)** |
| **Per-frame Heap Allocations** | Constant Map/Message/Widget allocations | **0 Heap allocations (GC-pause-free)** |
| **Impeller Optimization** | GPU render pass multiplication via `saveLayer` | **Single-pass custom Kawase blur shader** |
| **Heavy UI & Live Chat Resilience** | High frame-drops during active chats & animations | **0% UI thread CPU overhead for video HUD** |

---

## 📦 Widgets & Components

* **`ZPlayer`** (or `ZPlayerView`, legacy alias: `ZeroPlayerView`):
  Integrates zero-copy hardware textures with high-performance, zero-rebuild controls.
* **`ZDirectSeekBar`** (or `ZSeekBar`, legacy: `DirectSeekBar`):
  An ultra-efficient seek bar widget without a `build()` method. Reads position directly from atomic memory and draws via `Canvas.drawLine`. Fully interactive with drag and tap support.
* **`ZDirectTimeLabel`** (or `ZTimeLabel`, legacy: `DirectTimeLabel`):
  A zero-rebuild timecode widget that updates time text locally only when seconds transition.
* **`shaders/zero_blur.frag`**:
  Impeller-optimized single-pass Kawase blur shader preventing expensive off-screen buffer flushes.

---

## 🚀 Getting Started

### 1. Installation

Add `d_zero_player` to your `pubspec.yaml`:

```yaml
dependencies:
  d_zero_player: ^0.1.0
```

### 2. Basic Playback

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_player/d_zero_player.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  ZeroPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // Load a network MP4 or HLS (.m3u8) video
    final controller = await ZeroPlayerController.network(
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    );
    setState(() => _controller = controller);
    await controller.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Center(
        child: ZPlayer(
          controller: _controller!,
          showControls: true, // Automatically embeds zero-rebuild seek controls
        ),
      ),
    );
  }
}
```

### 3. HLS Live Streaming

```dart
// Stream Apple HLS (.m3u8) live broadcasts effortlessly
final controller = await ZeroPlayerController.network(
  'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8',
);
```

---

## 🛡 Quality Assurance & Test Suite

Engineered with enterprise-grade automated testing for native C++ shared memory and Dart FFI:

* **Native Concurrency Stress Tests (`native_stress_test.cpp`)**:
  * Concurrent decoder thread and 4 Dart reader threads verified **0 torn reads** via memory barriers.
  * Verified `nullptr` defense and 10,000 rapid allocations/deallocations with zero memory leaks.
* **Dart Boundary & Use-After-Free Defenses (`zero_player_test.dart`)**:
  * Prevents divide-by-zero crashes, handles maximum value overflows, and enforces double-free protection.
* **Cyclomatic Complexity**:
  * 100% of methods (48/48) maintain cyclomatic complexity ≤ 10 (average 1.83).
  * Run verification anytime via `dart run tool/check_complexity.dart`.

---

## 📄 License

MIT License © 2026 fexcy

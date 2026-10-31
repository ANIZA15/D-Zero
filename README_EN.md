# ⚡️ D-Zero (Dart Zero)

**An ultra-high-performance, zero-allocation, zero-rebuild widget suite engineered for the Flutter & Impeller era (60fps / 120fps ProMotion).**

[🇯🇵 日本語ドキュメントはこちら (README.md)](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)
[![Melos: Monorepo](https://img.shields.io/badge/Monorepo-Melos-purple.svg?style=flat-square)](https://melos.invertase.dev/)
[![Cyclomatic Complexity: <= 10 (100%)](https://img.shields.io/badge/Cyclomatic%20Complexity-%E2%89%A410%20(100%25)-brightgreen.svg?style=flat-square)](tool/check_complexity.dart)

---

## 💡 Why Zero Allocation Matters in the Impeller Era

With **120Hz ProMotion displays**, the UI thread frame budget is reduced from `16.6ms` (60fps) to **`8.33ms`**.  
While Flutter's **Impeller** engine eliminated shader compilation jank via AOT precompilation, **Dart UI thread heap allocations and generational garbage collection (GC pauses) remain the primary source of frame drops** in high-frequency UIs (video players, financial order books, real-time audio visualizers, particle systems, and live telemetry).

`D-Zero` brings game-engine memory discipline (inspired by Cysharp's `UniTask` / `ZString` and Data-Oriented Design) directly to Flutter:
1. **Zero Rebuild**: Bypasses `State.setState()` and `Widget.build()` via `ZLeafWidget` + `ZeroRenderBox` (`isRepaintBoundary = true`).
2. **Zero Allocation**: Renders dynamic numbers, currencies, percentages, and timecodes via a reference-counted GPU glyph atlas (`ZeroNumberPainter` + `Canvas.drawRawAtlas`) with **0 `String` allocations per frame**.
3. **Zero Channel**: Maps native C++ atomic playback state directly into Dart via FFI pointers (`0 ns` read latency, `0` MethodChannel serialization overhead).
4. **Zero `saveLayer`**: Replaces expensive offscreen passes (`BackdropFilter`, `ShaderMask`) with single-pass Canvas primitives and custom Impeller fragment shaders (`zero_blur.frag`).

---

## 📦 Monorepo Packages (All v0.1.0 with Interactive Benchmark Apps)

Every package under `packages/*` includes a standalone **High-Load Comparison Benchmark App (`example/`)** comparing `D-Zero` against traditional Flutter with a live **FPS, UI CPU Load (%), RSS Memory (Current/Peak MB), Widget Rebuilds, and Heap Allocations** HUD.

| Package | Version | Exported `Z` Widgets & Core Primitives | Docs | Benchmark App |
| :--- | :---: | :--- | :---: | :---: |
| **`d_zero_core`** | `0.1.3` | `ZWidget`, `ZLeafWidget`, `ZSingleChildWidget`, `ZeroRenderBox`, `ZeroNumberPainter`, `FloatRingBuffer`, `ZeroPool<T>`, `ZeroFrameScheduler`, `ZeroIntNotifier`, `ZeroDoubleNotifier` | [README](packages/d_zero_core/README.md) | [Example](packages/d_zero_core/example) |
| **`d_zero_player`** | `0.1.3` | `ZPlayer` (`ZPlayerView`), `ZDirectSeekBar` (`ZSeekBar`), `ZDirectTimeLabel` (`ZTimeLabel`), `ZVideoTimeline` (`ZThumbnailScrubber`), `ZeroPlayerController`, `ZeroTimelineController`, `zero_blur.frag` | [README](packages/d_zero_player/README.md) | [Example](packages/d_zero_player/example) |
| **`d_zero_counter`** | `0.1.3` | `ZCounter`, `ZStopwatch`, `ZCountdown`, `ZOdometer` (`ZAnimatedNumber`), `ZPriceTicker` (`ZCurrencyLabel`), `ZFPSMonitor` (`ZFrameOverlay`) | [README](packages/d_zero_counter/README.md) | [Example](packages/d_zero_counter/example) |
| **`d_zero_ui`** | `0.1.3` | `ZTerminal` (`ZLogStream`), `ZWheelPicker` (`ZDrumRollPicker`), `ZSegmentedControl` (`ZSlidingTabBar`), `ZPageIndicator` (`ZWormIndicator`), `ZRatingBar` (`ZStarRating`), `ZPullToRefresh` (`ZRefreshHeader`), `ZNumberPad` (`ZPinPad`), `ZStoryProgressBar` (`ZSegmentedProgress`), `ZStreamingMarkdown` (`ZTokenStream`), `ZCard` (`ZSurfaceCard`), `ZBadge` (`ZNotificationBadge`), `ZButton` (`ZActionButton`), `ZSwitch` (`ZToggle`), `ZSlider`, `ZRangeSlider`, `ZLinearProgress`, `ZCircularProgress`, `ZGauge` (`ZSpeedometer`), `ZJoystick` (`ZVirtualPad`), `ZKnob` (`ZRotaryDial`), `ZMarquee` (`ZRollingText`), `ZTypewriterText` | [README](packages/d_zero_ui/README.md) | [Example](packages/d_zero_ui/example) |
| **`d_zero_waveform`** | `0.1.3` | `ZWaveform` (`ZAudioVisualizer`), `ZSpectrumAnalyzer`, `ZAudioMeter` (`ZVUMeter`) | [README](packages/d_zero_waveform/README.md) | [Example](packages/d_zero_waveform/example) |
| **`d_zero_chart`** | `0.1.3` | `Z3DSurface` (`ZWaterfallChart`), `ZVirtualGrid` (`ZTimeSeriesTable`), `ZSparkline` (`ZRealtimeChart`), `ZCandlestickChart`, `ZHeatmap`, `ZOrderBook` (`ZDataGrid`), `ZActivityRings` (`ZConcentricRings`), `ZRadarChart` (`ZSpiderChart`), `ZDonutChart` (`ZPieChart`), `ZContributionGraph` (`ZHabitGrid`) | [README](packages/d_zero_chart/README.md) | [Example](packages/d_zero_chart/example) |
| **`d_zero_particles`** | `0.1.3` | `ZParticles` (SIMD `Float32x4` SoA), `ZConfetti`, `ZReactionStream` (`ZFloatingHearts`), `ZeroParticleController`, `ZeroConfettiController`, `ZeroReactionController` | [README](packages/d_zero_particles/README.md) | [Example](packages/d_zero_particles/example) |
| **`d_zero_fx`** | `0.1.3` | `ZShaderSurface` (`ZRuntimeShader`), `ZMetaballs3D` (`ZRaymarchSurface`), `ZMeshGradient` (`ZFluidGradient`), `Z3DTilt` (`ZParallaxContainer`), `ZSwipeDeck` (`ZTinderCards`), `ZScratchCard` (`ZScratchOff`), `ZBeforeAfterSlider` (`ZImageComparison`), `ZShimmer` (`ZSkeleton`), `ZBlur` (`ZGlassContainer`), `ZRipple` (`ZInkWell`), `ZLiquidProgress` (`ZWaveFilter`) | [README](packages/d_zero_fx/README.md) | [Example](packages/d_zero_fx/example) |
| **`d_zero_canvas`** | `0.1.3` | `Z3DMesh` (`Z3DGlobe`), `ZRibbon` (`ZLowLatencyInk`), `ZDanmaku` (`ZChatStream`), `ZInfiniteGrid` (`ZCanvasGrid`), `ZFreehandCanvas` | [README](packages/d_zero_canvas/README.md) | [Example](packages/d_zero_canvas/example) |
| **`d_zero_sensor`** | `0.1.3` | `Z3DPointCloud` (`ZLidarView`), `ZBarcodeScanner` (`ZCameraPreview`), `ZQRGenerator` (`ZMatrixCode`), `ZCompass`, `ZLeveler` | [README](packages/d_zero_sensor/README.md) | [Example](packages/d_zero_sensor/example) |
| **`d_zero_3dengine`** | `0.1.4` | `ZViewport3D` (`ZScene3D`), `ZEngineTelemetryHud` (`Z3DStatsOverlay`), `Zero3DEngineController`, `zero_3d_raytrace.frag` | [README](packages/d_zero_3dengine/README.md) | [Example](packages/d_zero_3dengine/example) |

---

## 🛠️ Quick Start & Verification Commands

```bash
# Resolve workspace dependencies
flutter pub get

# Run static analysis across all 10 packages, 10 examples, and benchmark apps
flutter analyze

# Verify Cyclomatic Complexity (enforces CC <= 15 across all functions)
dart run tool/check_complexity.dart

# Run all unit, lifecycle, and memory safety tests
melos run test

# Run terminal microbenchmarks
dart run benchmarks/run_benchmarks.dart
```

## 📜 License

MIT License © 2026 fexcy (ANIZA15)

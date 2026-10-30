# Changelog

All notable changes to the **D-Zero** monorepo and its packages are documented in this file.

## 0.1.0 - 2026-10-30

### 🚀 Initial Unified Monorepo Release

* **`d_zero_core` (`v0.1.0`)**:
  * Base zero-rebuild widgets (`ZWidget`, `ZLeafWidget`, `ZSingleChildWidget`) and `ZeroRenderBox` with automatic repaint boundaries (`isRepaintBoundary = true`).
  * `ZeroNumberPainter`: Shared GPU glyph atlas renderer (`Canvas.drawRawAtlas`) for zero-allocation integers, decimals, currencies, percentages, odometer digits, and timecodes.
  * `FloatRingBuffer`: Fixed-capacity `Float32List`-backed circular buffer.
  * `ZeroPool<T>`: Pre-warmed object pool eliminating per-frame GC allocations.
  * `ZeroFrameScheduler` & `ZeroNotifier` (`ZeroIntNotifier`, `ZeroDoubleNotifier`): O(1) V-Sync frame dispatcher and zero-allocation reactive value primitives.
* **`d_zero_player` (`v0.1.0`)**:
  * Zero-channel C++ atomic shared memory mapped via Dart FFI (`ZeroPlayerController`).
  * Zero-rebuild video player widgets (`ZPlayer` / `ZPlayerView`, `ZDirectSeekBar` / `ZSeekBar`, `ZDirectTimeLabel` / `ZTimeLabel`).
  * Single-pass Kawase blur fragment shader (`shaders/zero_blur.frag`).
* **`d_zero_counter` (`v0.1.0`)**:
  * `ZCounter`, `ZStopwatch`, `ZCountdown`, `ZOdometer` (`ZAnimatedNumber`), `ZPriceTicker` (`ZCurrencyLabel`), and `ZFPSMonitor` (`ZFrameOverlay`).
* **`d_zero_ui` (`v0.1.0`)**:
  * `ZCard` (`ZSurfaceCard`), `ZBadge` (`ZNotificationBadge`), `ZButton` (`ZActionButton`), `ZSwitch` (`ZToggle`), `ZSlider`, `ZRangeSlider`, `ZLinearProgress`, `ZCircularProgress`, `ZGauge` (`ZSpeedometer`), `ZJoystick` (`ZVirtualPad`), `ZKnob` (`ZRotaryDial`), `ZMarquee` (`ZRollingText`), and `ZTypewriterText`.
* **`d_zero_waveform` (`v0.1.0`)**:
  * `ZWaveform` (`ZAudioVisualizer`), `ZSpectrumAnalyzer`, and `ZAudioMeter` (`ZVUMeter`).
* **`d_zero_chart` (`v0.1.0`)**:
  * `ZSparkline` (`ZRealtimeChart`), `ZCandlestickChart`, `ZHeatmap`, and `ZOrderBook` (`ZDataGrid`).
* **`d_zero_particles` (`v0.1.0`)**:
  * `ZParticles` (SIMD `Float32x4` Structure-of-Arrays physics & `Canvas.drawRawPoints` batching) and `ZConfetti`.
* **`d_zero_fx` (`v0.1.0`)**:
  * Zero-`saveLayer` visual effects: `ZShimmer` (`ZSkeleton`), `ZBlur` (`ZGlassContainer`), `ZRipple` (`ZInkWell`), and `ZLiquidProgress` (`ZWaveFilter`).
* **`d_zero_canvas` (`v0.1.0`)**:
  * `ZDanmaku` (`ZChatStream`), `ZInfiniteGrid` (`ZCanvasGrid`), and `ZFreehandCanvas`.
* **`d_zero_sensor` (`v0.1.0`)**:
  * `ZBarcodeScanner` (`ZCameraPreview`), `ZCompass`, and `ZLeveler`.
* **Benchmark Apps & CLI Microbenchmarks**:
  * Interactive high-load comparison benchmark apps (`D-Zero` vs `Traditional Flutter`) in `apps/benchmark_app` and every `packages/*/example` displaying live FPS, UI CPU load (%), RSS Memory (Current/Peak MB), Widget Rebuilds, and Heap Allocations.

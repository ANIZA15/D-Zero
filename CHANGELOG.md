# Changelog

All notable changes to the **D-Zero** monorepo and its packages are documented in this file.

## 0.1.4 - 2026-10-31

* **`d_zero_3dengine` (`v0.1.4`)**: Added low-level 3D Game Engine viewport (`ZViewport3D` / `ZScene3D`), live telemetry HUD (`ZEngineTelemetryHud` / `Z3DStatsOverlay`), 128-byte (2 cache lines) C++ FFI shared state (`Zero3DEngineState`) with magic canary & ASan/UBSan/TSan verification, Nanite-style meshlet cluster culling, Ray Tracing shader, and 120Hz / 144Hz / 240Hz / Uncapped FPS support.
* Synchronized release of D-Zero workspace packages.

## 0.1.3 - 2026-10-30

* **18 Real-World App Zero-Allocation Widgets**:
  * **`d_zero_ui`**: Added `ZWheelPicker` (`ZDrumRollPicker`), `ZSegmentedControl` (`ZSlidingTabBar`), `ZPageIndicator` (`ZWormIndicator`), `ZRatingBar` (`ZStarRating`), `ZPullToRefresh` (`ZRefreshHeader`), `ZNumberPad` (`ZPinPad`), `ZStoryProgressBar` (`ZSegmentedProgress`), and `ZStreamingMarkdown` (`ZTokenStream`).
  * **`d_zero_chart`**: Added `ZActivityRings` (`ZConcentricRings`), `ZRadarChart` (`ZSpiderChart`), `ZDonutChart` (`ZPieChart`), and `ZContributionGraph` (`ZHabitGrid`).
  * **`d_zero_fx`**: Added `ZSwipeDeck` (`ZTinderCards`), `ZScratchCard` (`ZScratchOff`), and `ZBeforeAfterSlider` (`ZImageComparison`).
  * **`d_zero_particles`**: Added `ZReactionStream` (`ZFloatingHearts`).
  * **`d_zero_sensor`**: Added `ZQRGenerator` (`ZMatrixCode`).
  * **`d_zero_player`**: Added `ZVideoTimeline` (`ZThumbnailScrubber`).
* **Simplified Comparison Apps**: Unified all `packages/*/example` and `apps/benchmark_app` screens to display **D-Zero (`D-Zero`)**, **Traditional (`従来`)**, **FPS**, and **CPU usage (`CPU使用率`)**.
* chore(rules,tool): enforce README and pubspec sync audit for all exported Z-Widgets (eed8a3c)

## 0.1.2 - 2026-10-30

### 🚀 3D Graphics, Impeller GLSL 460 Shaders & Low-Level Widgets

* **`d_zero_fx` (`v0.1.2`)**:
  * `ZShaderSurface` (`ZRuntimeShader`) & `ZeroShaderController`: Direct Impeller GLSL 460 fragment shader (`shaders/z_plasma.frag`) surface driven by a fixed `Float32List(16)` uniform buffer with automatic software fallback.
  * `ZMetaballs3D` (`ZRaymarchSurface`) & `ZeroMetaballsController`: 3D implicit isosurface / metaball field (`shaders/z_metaballs.frag`) backed by a contiguous SoA `Float32List`.
  * `ZMeshGradient` (`ZFluidGradient`) & `ZeroMeshGradientController`: Interactive vertex-interpolated fluid mesh gradient via `Canvas.drawVertices(VertexMode.triangles)`.
  * `Z3DTilt` (`ZParallaxContainer`) & `Zero3DTiltController`: 3D perspective tilt container with zero-`saveLayer` specular light sheen.
* **`d_zero_canvas` (`v0.1.2`)**:
  * `Z3DMesh` (`Z3DGlobe`) & `Zero3DMeshController`: Real-time 3D wireframe and flat-shaded sphere/torus mesh renderer using SoA vertex buffers, in-place painter's Z-sort, and single-pass `Canvas.drawVertices` / `drawRawPoints`.
  * `ZRibbon` (`ZLowLatencyInk`) & `ZeroRibbonController`: 120Hz/240Hz triangle-strip ribbon trail rendered via `Canvas.drawVertices(VertexMode.triangleStrip)`.
* **`d_zero_chart` (`v0.1.2`)**:
  * `Z3DSurface` (`ZWaterfallChart`) & `Zero3DSurfaceController`: 3D surface plot and waterfall spectrogram (`rows × cols` `Float32List` height map) with perspective projection.
  * `ZVirtualGrid` (`ZTimeSeriesTable`) & `ZeroGridDataController`: Million-cell capable 2D virtualized numeric data grid backed by `Float64List` and rendered via `ZeroNumberPainter`.
* **`d_zero_sensor` (`v0.1.2`)**:
  * `Z3DPointCloud` (`ZLidarView`) & `ZeroPointCloudController`: 3D spatial depth / LiDAR point cloud viewer with SoA `Float32List` storage and depth-bucketed `Canvas.drawRawPoints`.
* **`d_zero_ui` (`v0.1.2`)**:
  * `ZTerminal` (`ZLogStream`) & `ZeroTerminalController`: Single-pass GPU glyph atlas (`Canvas.drawRawAtlas`) monospace terminal / high-frequency log stream backed by a circular `Uint16List` buffer.
* **CI / Release Automation & FFI Testing**:
  * Automatic macOS test `.dylib` compilation fallback in `ZeroPlayerNativeBindings` and CI quality gate integration (`tool/release.sh`, `.github/workflows/ci.yml`, `.github/workflows/release_tag.yml`).

## 0.1.1 - 2026-10-30

### 🔒 Security & Memory Safety Hardening

* **`d_zero_core` (`v0.1.1`)**:
  * `FloatRingBuffer` / `Float32RingBuffer`: Added `maxCapacity` (`1,048,576`) bounds check (CWE-789), lazy slice allocation for large capacities (`> 1024`), cached partial `contiguousView`, and strict `copyInto` range validation.
  * `ZeroNumberPainter`: Added `_safeScaledInt` and `_safeRoundToInt` guards to prevent float-to-int overflow on extreme `double` inputs (`double.maxFinite`).
* **`d_zero_player` (`v0.1.1`)**:
  * C++ `zero_playback_state.cpp`: Added saturating 64-bit integer addition and `NaN` / `Infinity` speed sanitization in `zero_get_display_position` and `zero_set_position_anchor`.
  * `ZeroPlayerNativeBindings`: Restricted relative `.dylib` fallback loading on macOS to debug/test environments (CWE-426).
  * `RenderDirectSeekBar` / `RenderDirectTimeLabel`: Enforced non-nullable `ZeroPlayerController` and render-object disposal checks before reading FFI state pointers.
  * Android `ZeroWebSocketStreamHandler`: Added 1MB pipe backpressure guard to prevent OkHttp callback thread stalls and OOM.
* **`d_zero_waveform` & `d_zero_sensor` (`v0.1.1`)**:
  * Added capacity upper bounds (`4096`) and post-disposal buffer zeroing to `ZeroSpectrumController` and `ZeroDetectionController`.

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

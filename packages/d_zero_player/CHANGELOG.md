## 0.1.1

* Synchronized release of `d_zero_player` v0.1.1.

## 0.1.0

* Unified `0.1.0` release across the `D-Zero` monorepo.
* Added high-load comparison benchmark modes (Memory RSS, UI CPU %, FPS, Rebuilds, FFI vs MethodChannel) in `example`.
* Standardized all exported widgets with `Z`-prefix (`ZPlayer`, `ZPlayerView`, `ZSeekBar`, `ZTimeLabel`, `ZDirectSeekBar`, `ZDirectTimeLabel`).

## 0.0.3

* Standardize exported widgets with `Z`-prefix (`ZPlayer`, `ZSeekBar`, `ZTimeLabel`, `ZDirectSeekBar`, `ZDirectTimeLabel`).
* Integrate with `d_zero_core` base widget and render object infrastructure.
* Enforce cyclomatic complexity limits and strengthen FFI shared-memory lifecycle tests.

## 0.0.2

* Add full Swift Package Manager (SPM) support for iOS (`Package.swift`).
* Update documentation, library-level comments, and API dartdocs.
* Add English primary documentation with Japanese mirror (`README_JA.md`).
* Refactor platform declarations and optimize package bundle size.

## 0.0.1

* Initial release of `d_zero_player`.
* High-performance, zero-jank Flutter video player optimized for Impeller (Metal & Vulkan).
* **Zero Rebuild**: RenderBox-driven `DirectSeekBar` and `DirectTimeLabel` that eliminate Widget build cycles.
* **Zero Channel**: Direct C++ atomic shared-memory mapped via Dart FFI for zero-latency position synchronization.
* **Zero Copy**: Native hardware decoding via AVPlayer (Metal) and ExoPlayer Media3 (Vulkan).
* Included single-pass Kawase blur fragment shader (`zero_blur.frag`) to avoid expensive `BackdropFilter` render passes.
* Full support for HLS live streams and progressive MP4 playback.

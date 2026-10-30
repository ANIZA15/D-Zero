## 0.1.2

* Synchronized release of `d_zero_core` v0.1.2.

## 0.1.1

* Hardened `FloatRingBuffer` and `Float32RingBuffer` with `maxCapacity` (`1,048,576`) bounds checks (CWE-789), lazy slice allocation for large capacities (`> 1024`), cached partial `contiguousView`, and strict `copyInto` range validation.
* Added float-to-int overflow guards (`_safeScaledInt`, `_safeRoundToInt`) in `ZeroNumberPainter` for extreme `double` inputs (`double.maxFinite`).

## 0.1.0

* Initial release of `d_zero_core`.
* Added `ZWidget` and `ZeroRenderBox` for zero-rebuild direct Canvas rendering.
* Added `ZeroNumberPainter` for zero-allocation numeric and timecode glyph rendering.
* Added `FloatRingBuffer` and `ZeroPool<T>` for GC-free data management in hot paths.
* Added `ZeroNotifier` and `ZeroFrameScheduler` for V-Sync synchronized updates.

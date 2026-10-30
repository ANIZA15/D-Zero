## 0.1.1

* Synchronized release of `d_zero_counter` v0.1.1.

## 0.1.0

* Unified monorepo initial release of `d_zero_counter`.
* Added `ZCounter` (legacy alias: `ZeroCounter`) for zero-allocation, zero-rebuild integer counter rendering via `ZeroNumberPainter`.
* Added `ZStopwatch` (legacy alias: `ZeroStopwatch`) for 120fps V-Sync timecode (`HH:MM:SS.cc`) rendering without heap string allocations.
* Added `ZCountdown` (legacy alias: `ZeroCountdown`) with warning threshold styling and completion callback.
* Added `ZOdometer` (`ZAnimatedNumber`, legacy alias: `ZeroOdometer`) for rolling mechanical digit transitions via Canvas clipping.
* Added `ZPriceTicker` (`ZCurrencyLabel`, legacy alias: `ZeroPriceTicker`) with directional flash background and currency glyph rendering.
* Added `ZFPSMonitor` (`ZFrameOverlay`, legacy alias: `ZeroFPSMonitor`) for zero-allocation live FPS and 60-frame rolling histogram monitoring.

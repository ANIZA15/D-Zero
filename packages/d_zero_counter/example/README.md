# ⚡️ d_zero_counter High-Load Benchmark App

Compares `d_zero_counter` (`ZCounter`, `ZStopwatch`, `ZCountdown`, `ZOdometer`, `ZPriceTicker`, `ZFPSMonitor`) against traditional `setState` + `Text` widgets across a 36-cell live financial wall.

## 📊 Live Metrics Displayed
- **FPS & Frame Histogram** (`ZFPSMonitor`)
- **CPU Load (%)** (`ZPriceTicker`)
- **RSS Memory / Peak MB** (`ZPriceTicker`)
- **D-Zero vs Traditional Rebuilds & String Allocations** (`ZCounter`)

```bash
flutter run
```

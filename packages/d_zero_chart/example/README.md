# ⚡️ d_zero_chart Financial Benchmark App

Compares `d_zero_chart` (`ZSparkline`, `ZCandlestickChart`, `ZHeatmap`, `ZOrderBook`) against traditional `CustomPaint` `Path` construction and nested `Row`/`Column`/`Text` grids under high-frequency market tick bursts.

## 📊 Live Metrics Displayed
- **FPS & Frame Histogram** (`ZFPSMonitor`)
- **CPU Load (%)** (`ZPriceTicker`)
- **RSS Memory / Peak MB** (`ZPriceTicker`)
- **D-Zero vs Traditional Rebuilds & Allocations** (`ZCounter`)

```bash
flutter run
```

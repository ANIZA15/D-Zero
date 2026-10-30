# ⚡️ d_zero_sensor ML & Gyro Benchmark App

Compares `d_zero_sensor` (`ZBarcodeScanner`, `ZCompass`, `ZLeveler`) against traditional `Stack` + `Positioned` + `Text` bounding-box overlays at 120Hz.

## 📊 Live Metrics Displayed
- **FPS & Frame Histogram** (`ZFPSMonitor`)
- **CPU Load (%)** (`ZPriceTicker`)
- **RSS Memory / Peak MB** (`ZPriceTicker`)
- **D-Zero vs Traditional Rebuilds & Allocations** (`ZCounter`)

```bash
flutter run
```

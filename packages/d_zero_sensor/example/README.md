# ⚡️ d_zero_sensor — 1000 QR Battle & ML/Gyro Benchmark App

Includes two interactive benchmark modes:
1. **🔥 1000 QR Battle (vs Tweet)**: Side-by-side split-screen race scanning 1,000 dynamic QR codes (`ZQRGenerator` + `ZBarcodeScanner` + `ZCounter` with `0` rebuilds and `0` string allocations vs. Traditional Flutter `setState` + `CustomPaint` + `Text`), with selectable **30 FPS (Tweet)**, **60 FPS**, **120 FPS**, and **Uncapped** rates.
2. **🧭 All Sensors**: Compares `d_zero_sensor` (`ZBarcodeScanner`, `ZCompass`, `ZLeveler`, `ZQRGenerator`) against traditional `Stack` + `Positioned` + `Text` bounding-box overlays at 120Hz.

## 📊 Live Metrics Displayed
- **FPS & Frame Histogram** (`ZFPSMonitor`)
- **CPU Load (%)** (`ZPriceTicker`)
- **1000 QR Counter & Elapsed Time (`s`)** (`ZCounter`, `ZPriceTicker`)
- **D-Zero vs Traditional Rebuilds, Heap Allocations (KB), and UI µs/tick**

```bash
cd packages/d_zero_sensor/example
flutter run
```

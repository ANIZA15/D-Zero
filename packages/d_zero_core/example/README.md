# ⚡️ d_zero_core High-Load Benchmark App

Interactive benchmark application for [`d_zero_core`](../README.md) comparing zero-allocation core primitives against traditional Flutter state & canvas patterns.

## 📊 Live Telemetry HUD Metrics

- **FPS**: Smoothed real-time frame rate (`ZeroNumberPainter.paintDouble`).
- **CPU (%)**: UI thread frame budget utilization (`Stopwatch` + 120Hz `8.33ms` budget ratio).
- **RSS (MB) / Peak (MB)**: Process resident memory usage (`ProcessInfo.currentRss`).
- **Z-Rebuild vs Trad-Reb**: Widget tree rebuild count (`0` in D-Zero mode).
- **Trad-Alloc**: Cumulative per-frame heap objects allocated in Traditional mode.

## 🚀 Running the Benchmark

```bash
flutter run
```

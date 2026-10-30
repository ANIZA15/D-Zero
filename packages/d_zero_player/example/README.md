# ⚡️ d_zero_player vs video_player Comparison Benchmark App

Interactive comparison benchmark application for [`d_zero_player`](../README.md) comparing FFI atomic shared-memory playback (`ZPlayer`, `ZDirectSeekBar`, `ZDirectTimeLabel`) against Flutter's standard `video_player` (`setState` + `MethodChannel`).

## 📊 Live Metrics Displayed
- **FPS & Dropped Frames**: Real-time frame rate and jank counter.
- **UI CPU Load (%) & RSS Memory (MB)**: Live UI thread CPU budget utilization and process resident memory.
- **Widget Rebuilds / Sec**: `0` in `d_zero_player` vs `10–30+ / sec` in `video_player`.
- **MethodChannel vs FFI Pointer Reads**: `0` channel messages during playback in `d_zero_player`.
- **Heavy Blur Stress Toggle**: Enables `BackdropFilter` load to test resilience under GPU stress.

## 🚀 Running the Comparison App

```bash
flutter run
```

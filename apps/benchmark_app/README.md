# ⚡️ d-zero Benchmark App

An interactive Flutter visual benchmark application that compares traditional Flutter UI practices with the `d-zero` suite.

## 🚀 Running the App

```bash
cd apps/benchmark_app
flutter run
```

Or run on macOS Desktop / iOS Simulator:

```bash
flutter run -d macos
```

## 🎯 Features

1. **Live Performance HUD**: Real-time FPS, frame duration (ms), dropped frame counter, and 120Hz detection.
2. **Counter & Stopwatch Comparison**:
   - Compares traditional `setState` + `Text` (generating thousands of String allocations and continuous widget rebuilds) vs `ZeroCounter` / `ZeroStopwatch` (zero rebuild, zero allocation direct Canvas paint).
   - Frequency control slider (30Hz to 500Hz).
3. **Buffer & Memory Pool Comparison**:
   - `FloatRingBuffer` vs `List.removeAt(0)` sliding queue throughput.
4. **Architecture & Budget Overview**:
   - Visual breakdown of the 8.33ms 120Hz budget and the 4 Pillars of Zero.

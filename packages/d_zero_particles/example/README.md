# ⚡️ d_zero_particles High-Load SIMD Benchmark App

Compares `D-Zero` (`ZParticles` 4-lane `Float32x4` SIMD + `ZConfetti` + `ZReactionStream` via `Canvas.drawRawPoints`) against traditional Flutter (`List<Particle>` + `CustomPaint` + `setState`) across **`3,000`, `15,000`, `50,000`, and `100,000`** particles in a clean Material 3 light theme UI.

## ⚔️ D-Zero vs. Traditional Implementation in [`lib/main.dart`](lib/main.dart)

| Layer | `D-Zero` Mode | `従来` (Traditional) Mode |
| :--- | :--- | :--- |
| **Data Structure** | `ZeroParticleBuffer` (`Float32List` / `Float32x4List` contiguous SoA) | `List<_TradParticle>` (individual Dart heap objects) |
| **Physics Step** | Branchless 4-lane SIMD (`Float32x4`, 2 particles/iteration) inside `RenderZParticles.onFrameTick` | Scalar loop over `_tradParticles[i].step(...)` + `setState(() {})` |
| **Rendering** | 1 batch call `canvas.drawRawPoints(PointMode.points, positions, _paint)` | `N` calls to `canvas.drawCircle(Offset(p.x, p.y), 1.8, Paint()..)` |
| **Widget Rebuilds** | `Rebuild: 1` (initial mount only; 0 rebuilds during simulation) | Increments every frame (`60`–`120` rebuilds/sec) |

## 📊 Genuine Runtime Telemetry Displayed
- **FPS & 60-Frame Histogram** (`ZFPSMonitor`)
- **CPU Usage (`%`) & Frame Time (`ms`)** (`ZPriceTicker` backed by `SchedulerBinding.instance.addTimingsCallback` / `FrameTiming` and `Stopwatch`)
- **Particle Count** (`ZCounter`)
- **Real Widget Rebuild Counter** (`Rebuild: N` measured in `build()` for both `D-Zero` and `従来` modes)

## 🎮 Interactive Controls
- **Mode Switch**: `D-Zero` vs `従来` (`SegmentedButton`)
- **Load Preset Switch**: `3,000` / `15,000` / `50,000` / `100,000` particles (`SegmentedButton`)
- **Action Buttons**: `紙吹雪バースト` (`ZeroConfettiController.burst`), `リアクション追加` (`ZeroReactionController.emit`), and `リセット` (`ZeroParticleController.reset`)

```bash
flutter run
```

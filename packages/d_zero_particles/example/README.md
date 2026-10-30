# ⚡️ d_zero_particles SIMD Benchmark App

Compares `ZParticles` (4-lane `Float32x4` SIMD + `Canvas.drawRawPoints`) and `ZConfetti` against traditional `List<Particle>` + `Canvas.drawCircle` loops at `2,000`, `5,000`, and `10,000` particles.

## 📊 Live Metrics Displayed
- **FPS & Frame Histogram** (`ZFPSMonitor`)
- **CPU Load (%)** (`ZPriceTicker`)
- **RSS Memory / Peak MB** (`ZPriceTicker`)
- **D-Zero vs Traditional Rebuilds & Per-Frame Allocations** (`ZCounter`)

```bash
flutter run
```

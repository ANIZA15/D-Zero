# ⚡️ D-Zero CLI Microbenchmarks

This directory contains standalone Dart VM microbenchmarks measuring raw CPU throughput, SIMD speedup, and heap allocation elimination between traditional Flutter/Dart patterns and `D-Zero` primitives.

---

## 🚀 Running Microbenchmarks

```bash
# Run all microbenchmarks from the repository root
dart run benchmarks/run_benchmarks.dart

# Or via Melos
melos run benchmark
```

---

## 📊 Included Benchmark Suites

| File | Target Component | Traditional Baseline | D-Zero Optimization |
| :--- | :--- | :--- | :--- |
| **[`core_pool_benchmark.dart`](core_pool_benchmark.dart)** | `ZeroPool<T>` | Continuous `new` heap object instantiation & GC scavenging | Pre-warmed `ZeroPool<T>` acquire/release (`0` heap allocations after warmup) |
| **[`ring_buffer_benchmark.dart`](ring_buffer_benchmark.dart)** | `FloatRingBuffer` | `List<double>.removeAt(0)` ($O(N)$ array shifting) | Fixed-capacity `Float32List` circular index wrap ($O(1)$ write/read) |
| **[`counter_allocation_benchmark.dart`](counter_allocation_benchmark.dart)** | `ZeroNumberPainter` | `String.padLeft()` & string interpolation (`~7` `String` objects/frame) | Base-10 arithmetic digit extraction into pre-allocated `Uint8List` (`0` `String` allocations) |
| **[`particle_benchmark.dart`](particle_benchmark.dart)** | `ZeroParticleBuffer` | AoS `List<Particle>` object pointer chasing | Contiguous `Float32List` SoA + 4-lane SIMD (`Float32x4`) branchless stepping |

---

## 📱 Interactive Flutter UI Benchmark Apps (FPS / CPU % / Memory MB)

For live 60fps/120fps visual comparisons with real-time **FPS, UI CPU Load (%), RSS Memory (Current/Peak MB), and Widget Rebuild counters**:
- **Full Monorepo Suite Benchmark App**: [`apps/benchmark_app`](../apps/benchmark_app)
- **Per-Package High-Load Benchmark Apps**: `packages/<package_name>/example`

# ⚡️ D-Zero Benchmarks

This directory contains standalone microbenchmarks measuring raw CPU performance, memory throughput, and allocation elimination between traditional Flutter/Dart practices and the `D-Zero` suite.

## 🚀 Running Microbenchmarks

```bash
# Run all microbenchmarks from repository root
dart run benchmarks/run_benchmarks.dart

# Or via Melos
melos run benchmark
```

## 📊 Benchmarks Included

1. **`core_pool_benchmark.dart`**:
   - Compares continuous heap allocations of short-lived objects against `ZeroPool<T>` recycling.
2. **`ring_buffer_benchmark.dart`**:
   - Compares sliding-window queue manipulations (`List.removeAt(0)`) against constant-time `FloatRingBuffer`.
3. **`counter_allocation_benchmark.dart`**:
   - Compares standard String formatting (`String.padLeft` & interpolation) against arithmetic digit extraction used in `ZeroNumberPainter`.

For the interactive Flutter UI benchmark comparing live FPS, frame drops, and widget rebuilds, see [`apps/benchmark_app`](../apps/benchmark_app).

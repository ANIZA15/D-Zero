import 'dart:io';
import 'core_pool_benchmark.dart';
import 'ring_buffer_benchmark.dart';
import 'counter_allocation_benchmark.dart';
import 'particle_benchmark.dart';

void main() {
  stdout.writeln('================================================================');
  stdout.writeln('⚡️ D-Zero Rigorous & Fair Performance Benchmarks');
  stdout.writeln('Evaluating Standard Dart Patterns vs. D-Zero Zero-Allocation Suite');
  stdout.writeln('================================================================');
  stdout.writeln('Environment:');
  stdout.writeln('  • Dart SDK : ${Platform.version.split(' ').first}');
  stdout.writeln('  • OS / Arch: ${Platform.operatingSystem} (${Platform.version.contains('arm64') ? 'arm64' : 'x64'})');
  stdout.writeln('  • Mode     : JIT (dart run) with Symmetrical Warmup & Median Profiling');
  stdout.writeln('  • Metric   : Symmetrical workload completion + GC allocation pressure');
  stdout.writeln('----------------------------------------------------------------\n');

  stdout.writeln('▶ [Benchmark 1/4] Sliding Window Queue: ListQueue vs FloatRingBuffer');
  runRingBufferBenchmark();
  stdout.writeln('');

  stdout.writeln('▶ [Benchmark 2/4] Object Lifecycle: Young Heap Allocation vs ZeroPool<T>');
  runCorePoolBenchmark();
  stdout.writeln('');

  stdout.writeln('▶ [Benchmark 3/4] Timecode Formatting: String.padLeft vs Direct Arithmetic');
  runCounterAllocationBenchmark();
  stdout.writeln('');

  stdout.writeln('▶ [Benchmark 4/4] 10,000 Particle Physics: AoS Heap Objects vs Flat SoA Buffer');
  runParticleBenchmark();
  stdout.writeln('');

  stdout.writeln('================================================================');
  stdout.writeln('✅ All microbenchmarks executed with symmetrical workloads.');
  stdout.writeln('================================================================');
}

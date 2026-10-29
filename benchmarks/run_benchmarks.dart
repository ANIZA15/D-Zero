import 'dart:io';
import 'core_pool_benchmark.dart';
import 'ring_buffer_benchmark.dart';
import 'counter_allocation_benchmark.dart';

void main() {
  stdout.writeln('================================================================');
  stdout.writeln('⚡️ d-zero Performance & Allocation Benchmarks');
  stdout.writeln('Comparing Standard Dart Patterns vs. d-zero Zero-Allocation Suite');
  stdout.writeln('================================================================\n');

  stdout.writeln('▶ [Benchmark 1/3] Object Allocation vs ZeroPool<T>');
  runCorePoolBenchmark();
  stdout.writeln('');

  stdout.writeln('▶ [Benchmark 2/3] Dynamic List<double> Queue vs FloatRingBuffer');
  runRingBufferBenchmark();
  stdout.writeln('');

  stdout.writeln('▶ [Benchmark 3/3] String Interpolation vs Zero-Allocation Number Rendering');
  runCounterAllocationBenchmark();
  stdout.writeln('');

  stdout.writeln('================================================================');
  stdout.writeln('✅ All microbenchmarks completed successfully.');
  stdout.writeln('================================================================');
}

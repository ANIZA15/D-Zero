import 'dart:collection';
import 'dart:io';
import 'package:d_zero_core/src/buffer/float_ring_buffer.dart';

/// Benchmarks circular buffer and sliding window performance.
///
/// Compares:
/// 1. [Fair O(1) Standard]: `dart:collection.ListQueue<double>` (Circular dynamic queue)
/// 2. [D-Zero O(1) Zero-Allocation]: `FloatRingBuffer` (`Float64List` based unboxed buffer)
/// 3. [Reference Naive]: `List.removeAt(0)` (O(N) anti-pattern for comparison)
void runRingBufferBenchmark() {
  const operations = 200000;
  const capacity = 256;
  const warmupRounds = 10000;
  const trials = 5;

  stdout.writeln('  Scenario: $operations sliding-window push operations (window size: $capacity)');
  stdout.writeln('  Evaluating O(1) Standard ListQueue vs. D-Zero TypedData FloatRingBuffer');

  // --- 1. Warmup ---
  _warmupRingBuffer(capacity, warmupRounds);

  // --- 2. Benchmark Fair Standard: ListQueue<double> (O(1)) ---
  final listQueueTimes = <double>[];
  for (int t = 0; t < trials; t++) {
    final queue = ListQueue<double>(capacity);
    final sw = Stopwatch()..start();
    for (int i = 0; i < operations; i++) {
      queue.addLast(i.toDouble());
      if (queue.length > capacity) {
        queue.removeFirst();
      }
    }
    sw.stop();
    listQueueTimes.add(sw.elapsedMicroseconds / 1000.0);
  }
  listQueueTimes.sort();
  final listQueueMedianMs = listQueueTimes[trials ~/ 2];
  final listQueueOps = (operations / (listQueueMedianMs / 1000.0)).toStringAsFixed(0);

  // --- 3. Benchmark D-Zero: FloatRingBuffer (O(1) TypedData) ---
  final ringBufferTimes = <double>[];
  for (int t = 0; t < trials; t++) {
    final ring = FloatRingBuffer(capacity);
    final sw = Stopwatch()..start();
    for (int i = 0; i < operations; i++) {
      ring.push(i.toDouble());
    }
    sw.stop();
    ringBufferTimes.add(sw.elapsedMicroseconds / 1000.0);
  }
  ringBufferTimes.sort();
  final ringBufferMedianMs = ringBufferTimes[trials ~/ 2];
  final ringOps = (operations / (ringBufferMedianMs / 1000.0)).toStringAsFixed(0);

  // --- 4. Benchmark Reference: Naive List.removeAt(0) (O(N) copy) ---
  final naiveSw = Stopwatch()..start();
  final naiveList = <double>[];
  for (int i = 0; i < operations; i++) {
    naiveList.add(i.toDouble());
    if (naiveList.length > capacity) {
      naiveList.removeAt(0);
    }
  }
  naiveSw.stop();
  final naiveMs = naiveSw.elapsedMicroseconds / 1000.0;

  // --- Results Summary ---
  final fairSpeedup = (listQueueMedianMs / ringBufferMedianMs).toStringAsFixed(2);
  final naiveSpeedup = (naiveMs / ringBufferMedianMs).toStringAsFixed(1);

  stdout.writeln('  📊 Results (Median of $trials runs):');
  stdout.writeln('    - Standard ListQueue<double> (O(1)) : ${listQueueMedianMs.toStringAsFixed(2)} ms ($listQueueOps ops/sec) [Boxed objects]');
  stdout.writeln('    - D-Zero FloatRingBuffer     (O(1)) : ${ringBufferMedianMs.toStringAsFixed(2)} ms ($ringOps ops/sec) [Unboxed Float64List, Zero GC]');
  stdout.writeln('    - [Ref] Naive List.removeAt  (O(N)) : ${naiveMs.toStringAsFixed(2)} ms (Array shift anti-pattern)');
  stdout.writeln('  ⚡️ Fair Comparison: FloatRingBuffer is ${fairSpeedup}x faster than ListQueue due to CPU cache locality and zero boxing.');
  stdout.writeln('  ℹ️ Note: Compared to naive List.removeAt(0), FloatRingBuffer is ${naiveSpeedup}x faster (avoiding O(N) array copy).');
}

void _warmupRingBuffer(int capacity, int count) {
  final q = ListQueue<double>(capacity);
  final r = FloatRingBuffer(capacity);
  for (int i = 0; i < count; i++) {
    q.addLast(i.toDouble());
    if (q.length > capacity) q.removeFirst();
    r.push(i.toDouble());
  }
}

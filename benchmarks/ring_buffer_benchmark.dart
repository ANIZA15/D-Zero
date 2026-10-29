import 'dart:io';
import 'package:zero_core/src/buffer/float_ring_buffer.dart';

void runRingBufferBenchmark() {
  const operations = 100000;
  const capacity = 256;
  stdout.writeln('  Test: $operations stream pushes into a fixed window of $capacity elements');

  // 1. Traditional List<double> sliding window (add + removeAt(0))
  final standardList = <double>[];
  final swStandard = Stopwatch()..start();
  for (int i = 0; i < operations; i++) {
    standardList.add(i.toDouble());
    if (standardList.length > capacity) {
      standardList.removeAt(0); // O(N) array copy / shift & heap reallocations
    }
  }
  swStandard.stop();
  final standardMs = swStandard.elapsedMicroseconds / 1000.0;
  final standardOps = (operations / (standardMs / 1000.0)).toStringAsFixed(0);

  // 2. d-zero FloatRingBuffer (O(1) circular buffer, Float64List)
  final ringBuffer = FloatRingBuffer(capacity);
  final swRing = Stopwatch()..start();
  for (int i = 0; i < operations; i++) {
    ringBuffer.push(i.toDouble()); // O(1) in-place write, zero allocation
  }
  swRing.stop();
  final ringMs = swRing.elapsedMicroseconds / 1000.0;
  final ringOps = (operations / (ringMs / 1000.0)).toStringAsFixed(0);

  final speedup = (standardMs / ringMs).toStringAsFixed(2);

  stdout.writeln('  - Standard List.removeAt(0) : ${standardMs.toStringAsFixed(2)} ms ($standardOps ops/sec)');
  stdout.writeln('  - d-zero FloatRingBuffer    : ${ringMs.toStringAsFixed(2)} ms ($ringOps ops/sec) [True O(1), Zero GC allocation]');
  stdout.writeln('  🔥 Result: FloatRingBuffer is ${speedup}x faster.');
}

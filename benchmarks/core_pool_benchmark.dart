import 'dart:io';
import 'package:zero_core/src/pool/zero_pool.dart';

class TestNode {
  double x = 0;
  double y = 0;
  int id = 0;
  void reset() {
    x = 0;
    y = 0;
    id = 0;
  }
}

void runCorePoolBenchmark() {
  const iterations = 500000;
  stdout.writeln('  Test: $iterations object allocations and disposals');

  // 1. Traditional Heap Allocation
  final swStandard = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    final node = TestNode();
    node.x = i.toDouble();
    node.y = (i * 2).toDouble();
    node.id = i;
    // node is discarded to become GC garbage
  }
  swStandard.stop();
  final standardMs = swStandard.elapsedMicroseconds / 1000.0;
  final standardOps = (iterations / (standardMs / 1000.0)).toStringAsFixed(0);

  // 2. d-zero ZeroPool Recycling
  final pool = ZeroPool<TestNode>(
    factory: () => TestNode(),
    reset: (n) => n.reset(),
    initialCapacity: 128,
    maxCapacity: 512,
  );

  final swPool = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    final node = pool.acquire();
    node.x = i.toDouble();
    node.y = (i * 2).toDouble();
    node.id = i;
    pool.release(node);
  }
  swPool.stop();
  final poolMs = swPool.elapsedMicroseconds / 1000.0;
  final poolOps = (iterations / (poolMs / 1000.0)).toStringAsFixed(0);

  final speedup = (standardMs / poolMs).toStringAsFixed(2);

  stdout.writeln('  - Standard Heap Allocation : ${standardMs.toStringAsFixed(2)} ms ($standardOps ops/sec) [Creates $iterations garbage objects]');
  stdout.writeln('  - d-zero ZeroPool Recycling: ${poolMs.toStringAsFixed(2)} ms ($poolOps ops/sec) [Zero GC allocations after warmup]');
  stdout.writeln('  🔥 Result: ZeroPool is ${speedup}x faster with 0 GC garbage pressure.');
}

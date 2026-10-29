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
  stdout.writeln('  Test: $iterations object lifecycles with state consumption');

  // Warmup to trigger JIT optimization
  final warmupPool = ZeroPool<TestNode>(
    factory: () => TestNode(),
    reset: (n) => n.reset(),
    initialCapacity: 128,
    maxCapacity: 512,
  );
  for (int i = 0; i < 5000; i++) {
    final n = warmupPool.acquire();
    warmupPool.release(n);
  }

  // 1. Traditional Heap Allocation (with field consumption to prevent Dead Code Elimination)
  double standardChecksum = 0;
  final swStandard = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    final node = TestNode();
    node.x = i.toDouble();
    node.y = (i * 2).toDouble();
    node.id = i;
    // Consume fields so the compiler cannot discard the allocation loop
    standardChecksum += node.x + node.y + node.id;
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

  double poolChecksum = 0;
  final swPool = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    final node = pool.acquire();
    node.x = i.toDouble();
    node.y = (i * 2).toDouble();
    node.id = i;
    poolChecksum += node.x + node.y + node.id;
    pool.release(node);
  }
  swPool.stop();
  final poolMs = swPool.elapsedMicroseconds / 1000.0;
  final poolOps = (iterations / (poolMs / 1000.0)).toStringAsFixed(0);

  stdout.writeln('  - Standard Heap Allocation : ${standardMs.toStringAsFixed(2)} ms ($standardOps ops/sec) [Creates $iterations garbage objects, sum: ${standardChecksum.toStringAsFixed(0)}]');
  stdout.writeln('  - d-zero ZeroPool Recycling: ${poolMs.toStringAsFixed(2)} ms ($poolOps ops/sec) [Zero GC allocations after warmup, sum: ${poolChecksum.toStringAsFixed(0)}]');
  
  if (poolMs <= standardMs) {
    final speedup = (standardMs / poolMs).toStringAsFixed(2);
    stdout.writeln('  🔥 Result: ZeroPool is ${speedup}x faster with 0 GC garbage pressure.');
  } else {
    final diff = (poolMs - standardMs).toStringAsFixed(2);
    stdout.writeln('  🔥 Result: ZeroPool eliminates 100% of $iterations heap garbage objects at stable throughput (overhead: +${diff}ms over $iterations calls).');
  }
}


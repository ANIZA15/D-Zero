import 'dart:io';
import 'package:zero_core/src/pool/zero_pool.dart';

class NodeItem {
  double x = 0;
  double y = 0;
  int id = 0;

  void reset() {
    x = 0;
    y = 0;
    id = 0;
  }
}

/// Benchmarks Object Pooling (ZeroPool) vs. Standard Heap Allocation.
///
/// Demonstrates the architectural trade-off:
/// - Heap Allocation: Extremely fast single-threaded bump-pointer allocation in Dart's Young Space,
///   but generates massive amounts of GC garbage (Stop-The-World jank risk in 60/120fps UI loops).
/// - ZeroPool: Recycles pre-allocated memory structures, achieving 0 heap allocations and 0 GC pressure
///   at the cost of pool tracking overhead.
void runCorePoolBenchmark() {
  const batchSize = 32;
  const totalBatches = 15000;
  const totalLifecycles = batchSize * totalBatches; // 480,000 objects
  const trials = 3;

  stdout.writeln('  Scenario: Realistic frame-workload with $totalLifecycles object lifecycles ($totalBatches batches x $batchSize active)');
  stdout.writeln('  Evaluating CPU throughput vs. GC Garbage Pressure');

  // --- 1. Symmetrical Warmup ---
  _warmupPoolBenchmark(batchSize);

  // --- 2. Standard Heap Allocation ---
  final heapTimes = <double>[];
  double heapChecksum = 0;
  for (int t = 0; t < trials; t++) {
    heapChecksum = 0;
    final sw = Stopwatch()..start();
    for (int b = 0; b < totalBatches; b++) {
      final batch = <NodeItem>[];
      for (int i = 0; i < batchSize; i++) {
        final node = NodeItem();
        node.x = (b + i).toDouble();
        node.y = (b * 2 + i).toDouble();
        node.id = i;
        batch.add(node);
      }
      for (int i = 0; i < batchSize; i++) {
        heapChecksum += batch[i].x + batch[i].y + batch[i].id;
      }
    }
    sw.stop();
    heapTimes.add(sw.elapsedMicroseconds / 1000.0);
  }
  heapTimes.sort();
  final heapMedianMs = heapTimes[trials ~/ 2];
  final heapOps = (totalLifecycles / (heapMedianMs / 1000.0)).toStringAsFixed(0);

  // --- 3. d-zero ZeroPool Recycling ---
  final pool = ZeroPool<NodeItem>(
    factory: () => NodeItem(),
    reset: (n) => n.reset(),
    initialCapacity: batchSize * 2,
    maxCapacity: batchSize * 4,
  );

  final poolTimes = <double>[];
  double poolChecksum = 0;
  final pooledBatch = List<NodeItem?>.filled(batchSize, null);

  for (int t = 0; t < trials; t++) {
    poolChecksum = 0;
    final sw = Stopwatch()..start();
    for (int b = 0; b < totalBatches; b++) {
      // Acquire active batch
      for (int i = 0; i < batchSize; i++) {
        final node = pool.acquire();
        node.x = (b + i).toDouble();
        node.y = (b * 2 + i).toDouble();
        node.id = i;
        pooledBatch[i] = node;
      }
      // Consume and release batch
      for (int i = 0; i < batchSize; i++) {
        final node = pooledBatch[i]!;
        poolChecksum += node.x + node.y + node.id;
        pool.release(node);
      }
    }
    sw.stop();
    poolTimes.add(sw.elapsedMicroseconds / 1000.0);
  }
  poolTimes.sort();
  final poolMedianMs = poolTimes[trials ~/ 2];
  final poolOps = (totalLifecycles / (poolMedianMs / 1000.0)).toStringAsFixed(0);

  // Approximate memory footprint: 1 Dart object ~ 32-48 bytes minimum on 64-bit VM
  const approxBytesPerNode = 40;
  final estimatedGarbageMb = (totalLifecycles * approxBytesPerNode) / (1024 * 1024);

  // --- Results Summary ---
  stdout.writeln('  📊 Results (Median of $trials runs, $totalLifecycles objects):');
  stdout.writeln('    - Standard Heap Allocation : ${heapMedianMs.toStringAsFixed(2)} ms ($heapOps ops/sec)');
  stdout.writeln('      ↳ Discards ~${estimatedGarbageMb.toStringAsFixed(1)} MB garbage across $totalLifecycles instances (sum: ${heapChecksum.toStringAsFixed(0)})');
  stdout.writeln('    - d-zero ZeroPool Recycling: ${poolMedianMs.toStringAsFixed(2)} ms ($poolOps ops/sec)');
  stdout.writeln('      ↳ Heap garbage: 0 MB / 0 objects after initial buffer allocation (sum: ${poolChecksum.toStringAsFixed(0)})');

  _printAnalysis(heapMedianMs, poolMedianMs, totalLifecycles, estimatedGarbageMb);
}

void _warmupPoolBenchmark(int batchSize) {
  final warmupPool = ZeroPool<NodeItem>(
    factory: () => NodeItem(),
    reset: (n) => n.reset(),
    initialCapacity: batchSize,
  );
  for (int b = 0; b < 100; b++) {
    final nodes = <NodeItem>[];
    for (int i = 0; i < batchSize; i++) {
      nodes.add(NodeItem());
      final p = warmupPool.acquire();
      warmupPool.release(p);
    }
  }
}

void _printAnalysis(double heapMs, double poolMs, int totalObjects, double garbageMb) {
  stdout.writeln('  🔬 Engineering Analysis:');
  stdout.writeln('    • Dart VM bump-pointer allocator is highly optimized for short-lived young objects in raw CPU time.');
  if (poolMs <= heapMs) {
    final speedup = (heapMs / poolMs).toStringAsFixed(2);
    stdout.writeln('    • ZeroPool is ${speedup}x faster while completely eliminating GC pressure.');
  } else {
    final overhead = (poolMs - heapMs).toStringAsFixed(2);
    stdout.writeln('    • ZeroPool incurs an explicit management overhead (+${overhead}ms over $totalObjects lifecycles),');
    stdout.writeln('      in exchange for eliminating ~${garbageMb.toStringAsFixed(1)} MB of garbage that triggers Scavenge / GC Pause spikes in 120fps UI rendering.');
  }
}

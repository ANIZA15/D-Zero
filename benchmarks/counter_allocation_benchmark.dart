import 'dart:io';
import 'dart:typed_data';

/// Benchmarks Timecode formatting and decomposition.
///
/// Compares two approaches that accomplish the exact same outcome:
/// Producing an 8-character ASCII glyph sequence ("HH:MM:SS") ready for Canvas rendering.
///
/// 1. Traditional Flutter/Dart Approach:
///    - Uses String interpolation with padLeft: `"${h.toString().padLeft(2, '0')}:..."`
///    - Produces intermediate String allocations (hours, minutes, seconds, padded strings, merged string)
///    - Extracts `codeUnits` for layout/rendering.
///
/// 2. d-zero Zero-Allocation Direct Arithmetic Approach:
///    - Employs `ZeroNumberPainter` algorithm.
///    - Computes character codes directly via modulo/division arithmetic.
///    - Writes directly into a reusable `Uint8List(8)` buffer. Zero String allocations.
void runCounterAllocationBenchmark() {
  const count = 300000;
  const trials = 3;

  stdout.writeln('  Scenario: Generate 8-character ASCII glyph stream ("HH:MM:SS") for $count frames');
  stdout.writeln('  Task: Transform raw integer time into 8-character buffer representation for canvas rendering');

  // --- 1. Symmetrical Warmup ---
  _warmupCounter(5000);

  // --- 2. Traditional String Interpolation + CodeUnits extraction ---
  final traditionalTimes = <double>[];
  int traditionalChecksum = 0;

  for (int t = 0; t < trials; t++) {
    traditionalChecksum = 0;
    final sw = Stopwatch()..start();
    for (int i = 0; i < count; i++) {
      final s = i % 60;
      final m = (i ~/ 60) % 60;
      final h = (i ~/ 3600);

      // Allocates multiple intermediate Strings per frame:
      // toString() x 3, padLeft() x 3, template String concatenation x 1 = ~7 Heap Objects
      final formatted = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      
      // Complete fair work: Consume character codes as a render engine would
      final units = formatted.codeUnits;
      for (int c = 0; c < units.length; c++) {
        traditionalChecksum += units[c];
      }
    }
    sw.stop();
    traditionalTimes.add(sw.elapsedMicroseconds / 1000.0);
  }
  traditionalTimes.sort();
  final traditionalMedianMs = traditionalTimes[trials ~/ 2];
  final traditionalOps = (count / (traditionalMedianMs / 1000.0)).toStringAsFixed(0);

  // --- 3. d-zero Zero-Allocation Direct Arithmetic ---
  final zeroTimes = <double>[];
  int zeroChecksum = 0;
  // Reusable scratch buffer (fixed 8 bytes for "HH:MM:SS", exactly like ZeroNumberPainter)
  final buffer = Uint8List(8);

  for (int t = 0; t < trials; t++) {
    zeroChecksum = 0;
    final sw = Stopwatch()..start();
    for (int i = 0; i < count; i++) {
      final s = i % 60;
      final m = (i ~/ 60) % 60;
      final h = (i ~/ 3600);

      // Direct integer arithmetic into fixed buffer: 0 String allocations
      buffer[0] = 0x30 + ((h ~/ 10) % 10);
      buffer[1] = 0x30 + (h % 10);
      buffer[2] = 0x3A; // ':'
      buffer[3] = 0x30 + ((m ~/ 10) % 10);
      buffer[4] = 0x30 + (m % 10);
      buffer[5] = 0x3A; // ':'
      buffer[6] = 0x30 + ((s ~/ 10) % 10);
      buffer[7] = 0x30 + (s % 10);

      // Complete identical fair work: Consume the resulting character buffer
      for (int c = 0; c < 8; c++) {
        zeroChecksum += buffer[c];
      }
    }
    sw.stop();
    zeroTimes.add(sw.elapsedMicroseconds / 1000.0);
  }
  zeroTimes.sort();
  final zeroMedianMs = zeroTimes[trials ~/ 2];
  final zeroOps = (count / (zeroMedianMs / 1000.0)).toStringAsFixed(0);

  final speedup = (traditionalMedianMs / zeroMedianMs).toStringAsFixed(2);
  final approxStringsCreated = count * 7;

  // --- Results Summary ---
  stdout.writeln('  📊 Results (Median of $trials runs, $count frames):');
  stdout.writeln('    - Traditional String.padLeft : ${traditionalMedianMs.toStringAsFixed(2)} ms ($traditionalOps ops/sec)');
  stdout.writeln('      ↳ Heap allocation: ~$approxStringsCreated String instances discarded to GC (checksum: $traditionalChecksum)');
  stdout.writeln('    - d-zero Direct Arithmetic   : ${zeroMedianMs.toStringAsFixed(2)} ms ($zeroOps ops/sec)');
  stdout.writeln('      ↳ Heap allocation: 0 String instances, in-place Uint8List buffer (checksum: $zeroChecksum)');
  stdout.writeln('  ⚡️ Fair Speedup: Direct arithmetic is ${speedup}x faster with 100% eliminated String allocation.');
  stdout.writeln('  💡 Integrity Check: Output checksums match perfectly (${traditionalChecksum == zeroChecksum ? "MATCHED ✅" : "MISMATCH ❌"}).');
}

void _warmupCounter(int count) {
  final buf = Uint8List(8);
  for (int i = 0; i < count; i++) {
    final s = i % 60;
    final m = (i ~/ 60) % 60;
    final h = (i ~/ 3600);
    final str = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    buf[0] = str.codeUnitAt(0);

    buf[0] = 0x30 + ((h ~/ 10) % 10);
  }
}

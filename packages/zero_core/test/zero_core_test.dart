import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_core/zero_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatRingBuffer Tests', () {
    test('push and index access correctly retrieve circular values', () {
      final buffer = FloatRingBuffer(3);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, equals(0));

      buffer.push(10.0);
      buffer.push(20.0);
      expect(buffer.length, equals(2));
      expect(buffer[0], equals(10.0));
      expect(buffer[1], equals(20.0));

      buffer.push(30.0);
      expect(buffer.isFull, isTrue);
      expect(buffer.length, equals(3));
      expect(buffer[0], equals(10.0));
      expect(buffer[1], equals(20.0));
      expect(buffer[2], equals(30.0));

      // Overwrite oldest (10.0)
      buffer.push(40.0);
      expect(buffer.length, equals(3));
      expect(buffer[0], equals(20.0));
      expect(buffer[1], equals(30.0));
      expect(buffer[2], equals(40.0));
    });

    test('clear resets buffer state without shrinking storage', () {
      final buffer = FloatRingBuffer(5);
      buffer.pushAll([1.0, 2.0, 3.0]);
      expect(buffer.length, equals(3));

      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, equals(0));
      expect(buffer.rawData.length, equals(5));
    });
  });

  group('ZeroPool Tests', () {
    test('acquires and releases items without reallocating', () {
      int creations = 0;
      final pool = ZeroPool<List<int>>(
        factory: () {
          creations++;
          return <int>[];
        },
        reset: (list) => list.clear(),
        initialCapacity: 2,
      );

      expect(creations, equals(2));
      expect(pool.availableCount, equals(2));

      final item1 = pool.acquire();
      expect(pool.availableCount, equals(1));
      item1.add(42);

      pool.release(item1);
      expect(pool.availableCount, equals(2));
      expect(item1.isEmpty, isTrue); // reset called
      expect(creations, equals(2)); // No extra allocations
    });
  });

  group('ZeroNumberPainter Tests', () {
    test('initializes and formats numbers without string allocation in loop', () {
      final painter = ZeroNumberPainter();
      expect(painter.height, greaterThan(0));
      expect(painter.maxDigitWidth, greaterThan(0));

      // Test against dummy canvas (record operations)
      final pictureRecorder = PictureRecorder();
      final canvas = Canvas(pictureRecorder);

      final w1 = painter.paintInt(canvas, Offset.zero, 12345);
      expect(w1, greaterThan(0));

      final w2 = painter.paintTimecode(canvas, Offset.zero, 65000); // 01:05
      expect(w2, greaterThan(0));

      pictureRecorder.endRecording();
      painter.dispose();
    });
  });
}

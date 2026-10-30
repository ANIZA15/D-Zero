import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_core/zero_core.dart';
import 'package:zero_sensor/zero_sensor.dart';

void main() {
  group('ZeroDetectionController & ZBarcodeScanner', () {
    test('ZeroDetectionController survives double dispose and post-dispose calls', () {
      final ZeroDetectionController controller = ZeroDetectionController(capacity: 8);
      controller.setDetection(0, 10.0, 20.0, 120.0, 80.0, 0.98);
      expect(controller.activeCount, equals(1));
      expect(controller.isActiveAt(0), isTrue);

      controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(() => controller.dispose(), returnsNormally);
      expect(controller.activeCount, equals(0));
      expect(controller.isActiveAt(0), isFalse);
      expect(() => controller.setDetection(0, 0, 0, 10, 10, 0.5), returnsNormally);
    });

    testWidgets('ZBarcodeScanner renders detections and cleans up on unmount', (tester) async {
      final ZeroDetectionController controller = ZeroDetectionController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZBarcodeScanner(
              controller: controller,
              size: const Size(300.0, 200.0),
            ),
          ),
        ),
      );

      controller.setDetection(0, 40.0, 40.0, 180.0, 120.0, 0.96);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => controller.clearDetections(), returnsNormally);
      controller.dispose();
    });
  });

  group('ZCompass', () {
    testWidgets('ZCompass rotates dial and unsubscribes on unmount', (tester) async {
      final ZeroDoubleNotifier heading = ZeroDoubleNotifier(45.0);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZCompass(
              headingListenable: heading,
              size: const Size(150.0, 150.0),
            ),
          ),
        ),
      );

      heading.value = 180.0;
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(heading.hasListeners, isFalse);
      expect(() => heading.value = 270.0, returnsNormally);
      heading.dispose();
    });
  });

  group('ZeroTiltController & ZLeveler', () {
    test('ZeroTiltController survives double dispose and clamps angles', () {
      final ZeroTiltController controller = ZeroTiltController();
      controller.updateTilt(120.0, -110.0);
      expect(controller.pitch, equals(90.0));
      expect(controller.roll, equals(-90.0));

      controller.dispose();
      expect(() => controller.dispose(), returnsNormally);
      expect(controller.pitch, equals(0.0));
      expect(controller.roll, equals(0.0));
    });

    testWidgets('ZLeveler renders bubble and cleans up on unmount', (tester) async {
      final ZeroTiltController controller = ZeroTiltController(pitch: 2.5, roll: -3.0);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZLeveler(
              controller: controller,
              size: const Size(150.0, 150.0),
            ),
          ),
        ),
      );

      controller.updateTilt(0.2, -0.1);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => controller.updateTilt(15.0, 15.0), returnsNormally);
      controller.dispose();
    });
  });
}

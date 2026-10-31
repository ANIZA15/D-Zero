import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_sensor/d_zero_sensor.dart';

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

  group('ZeroPointCloudController & Z3DPointCloud', () {
    test('ZeroPointCloudController unprojects camera depth frames, measures metric distances, and survives double-dispose', () {
      final controller = ZeroPointCloudController(maxPoints: 512);
      // Simulate a 4x4 depth frame at 2.25m distance
      final depthFrame = List<double>.filled(16, 2.25);
      controller.ingestDepthFrame(depthFrame, width: 4, height: 4);

      expect(controller.pointCount, equals(16));
      expect(controller.centerDistanceMeters, closeTo(2.25, 1e-4));
      expect(controller.distanceAtPoint(0), greaterThan(2.25));

      controller.clear();
      controller.addPoint(0.0, 0.0, 1.0);
      controller.addPoint(3.0, 4.0, 1.0);
      expect(controller.measureDistanceBetween(0, 1), closeTo(5.0, 1e-4));

      controller.dispose();
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(controller.pointCount, equals(0));
      expect(controller.centerDistanceMeters, equals(0.0));
      expect(controller.measureDistanceBetween(0, 1), equals(0.0));
    });

    testWidgets('Z3DPointCloud renders depth-bucketed LiDAR cloud and rangefinder HUD', (tester) async {
      final controller = ZeroPointCloudController(maxPoints: 256);
      addTearDown(controller.dispose);
      final depthFrame = List<double>.generate(64, (i) => 1.2 + (i % 8) * 0.35);
      controller.ingestDepthFrame(depthFrame, width: 8, height: 8);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZLidarView(
              controller: controller,
              size: const Size(280.0, 200.0),
            ),
          ),
        ),
      );
      expect(controller.hasListeners, isTrue);

      await tester.drag(find.byType(Z3DPointCloud), const Offset(40.0, -25.0));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });

  group('ZQRGenerator & ZeroQRCodeController', () {
    test('ZeroQRCodeController regenerates matrix and survives double-dispose', () {
      final controller = ZeroQRCodeController(gridSize: 21, initialToken: 123456);
      expect(controller.moduleAt(0, 0), isTrue);
      controller.updateToken(654321);
      expect(controller.tokenValue, equals(654321));

      controller.dispose();
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(controller.tokenValue, equals(0));
      expect(controller.moduleAt(0, 0), isFalse);
    });

    testWidgets('ZQRGenerator renders matrix code and detaches on unmount', (tester) async {
      final controller = ZeroQRCodeController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZMatrixCode(controller: controller),
          ),
        ),
      );
      expect(controller.hasListeners, isTrue);

      controller.updateToken(999999);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });
}

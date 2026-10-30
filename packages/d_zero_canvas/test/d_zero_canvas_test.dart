import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_canvas/d_zero_canvas.dart';

void main() {
  group('ZeroDanmakuController & ZDanmaku', () {
    test('ZeroDanmakuController survives double dispose and post-dispose calls', () {
      final ZeroDanmakuController controller = ZeroDanmakuController(capacity: 8);
      controller.emit('Hello d-zero!', speed: 150.0);
      expect(controller.activeCount, equals(1));
      expect(controller.step(0.1), isTrue);

      controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(() => controller.dispose(), returnsNormally);
      expect(controller.activeCount, equals(0));
      expect(() => controller.emit('After dispose'), returnsNormally);
      expect(controller.step(0.1), isFalse);
    });

    testWidgets('ZDanmaku renders pooled comments and unsubscribes on unmount', (tester) async {
      final ZeroDanmakuController controller = ZeroDanmakuController(capacity: 16);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZDanmaku(
              controller: controller,
              size: const Size(320.0, 160.0),
            ),
          ),
        ),
      );

      controller.emit('120fps Danmaku');
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.xAt(0), lessThan(320.0));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => controller.emit('Post unmount'), returnsNormally);
      controller.dispose();
    });
  });

  group('ZeroViewportController & ZInfiniteGrid', () {
    test('ZeroViewportController survives double dispose and clamps zoom', () {
      final ZeroViewportController viewport = ZeroViewportController();
      viewport.pan(25.0, -15.0);
      viewport.setZoom(10.0);
      expect(viewport.panX, equals(25.0));
      expect(viewport.panY, equals(-15.0));
      expect(viewport.zoom, equals(4.0));

      viewport.dispose();
      expect(() => viewport.dispose(), returnsNormally);
      expect(viewport.panX, equals(0.0));
      expect(viewport.panY, equals(0.0));
      expect(viewport.zoom, equals(1.0));
    });

    testWidgets('ZInfiniteGrid renders and pans via drag', (tester) async {
      final ZeroViewportController viewport = ZeroViewportController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZInfiniteGrid(
              controller: viewport,
              size: const Size(300.0, 200.0),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ZInfiniteGrid), const Offset(40.0, 20.0));
      await tester.pump();
      expect(viewport.panX, closeTo(40.0, 0.1));
      expect(viewport.panY, closeTo(20.0, 0.1));

      await tester.pumpWidget(const SizedBox.shrink());
      viewport.dispose();
    });
  });

  group('ZeroFreehandController & ZFreehandCanvas', () {
    test('ZeroFreehandController survives double dispose and records segments', () {
      final ZeroFreehandController controller = ZeroFreehandController(maxSegments: 64);
      controller.addPoint(10.0, 10.0);
      controller.addPoint(20.0, 25.0);
      controller.addPoint(30.0, 40.0);
      controller.endStroke();
      expect(controller.pointCount, equals(3));
      expect(controller.segmentCount, equals(2));

      controller.dispose();
      expect(() => controller.dispose(), returnsNormally);
      expect(controller.pointCount, equals(0));
      expect(controller.segmentCount, equals(0));
    });

    testWidgets('ZFreehandCanvas captures pointer drag and cleans up on unmount', (tester) async {
      final ZeroFreehandController controller = ZeroFreehandController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZFreehandCanvas(
              controller: controller,
              size: const Size(300.0, 200.0),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ZFreehandCanvas), const Offset(60.0, 30.0));
      await tester.pump();
      expect(controller.pointCount, greaterThan(1));
      expect(controller.segmentCount, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  });
}

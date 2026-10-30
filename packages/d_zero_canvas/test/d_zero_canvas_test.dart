import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_canvas/d_zero_canvas.dart';

void main() {
  group('ZeroDanmakuController & ZDanmaku', () {
    test('ZeroDanmakuController survives double dispose and post-dispose calls', () {
      final ZeroDanmakuController controller = ZeroDanmakuController(capacity: 8);
      controller.emit('Hello D-Zero!', speed: 150.0);
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

  group('ZeroRibbonController & ZRibbon', () {
    test('ZeroRibbonController extrudes triangle strip with degenerate bridges and survives double-dispose', () {
      final controller = ZeroRibbonController(maxSamples: 64);
      controller.addSample(10.0, 10.0, pressure: 0.3);
      controller.addSample(25.0, 20.0, pressure: 0.7);
      controller.addSample(45.0, 35.0, pressure: 0.9);
      controller.endStroke();
      expect(controller.sampleCount, equals(3));
      expect(controller.vertexCount, equals(6));

      // Second stroke adds 2 degenerate bridge vertices + 2 start vertices + 2 move vertices = +6
      controller.addSample(80.0, 80.0, pressure: 0.5);
      controller.addSample(100.0, 95.0, pressure: 0.8);
      controller.endStroke();
      expect(controller.sampleCount, equals(5));
      expect(controller.vertexCount, equals(12));

      controller.clear();
      expect(controller.vertexCount, equals(0));

      controller.dispose();
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      controller.addSample(10.0, 20.0);
      expect(controller.vertexCount, equals(0));
    });

    testWidgets('ZRibbon renders triangle strip ink on drag and detaches on unmount', (tester) async {
      final controller = ZeroRibbonController(maxSamples: 256);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZLowLatencyInk(
              controller: controller,
              size: const Size(300.0, 180.0),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ZRibbon), const Offset(80.0, 40.0));
      await tester.pump();
      expect(controller.sampleCount, greaterThan(1));
      expect(controller.vertexCount, greaterThanOrEqualTo(4));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => controller.addSample(50.0, 50.0), returnsNormally);
    });
  });

  group('Zero3DMeshController & Z3DMesh', () {
    test('Zero3DMeshController builds sphere/torus/cube, culls backfaces, and survives double-dispose', () {
      final sphere = Zero3DMeshController.sphere(latSegments: 8, lonSegments: 12);
      final torus = Zero3DMeshController.torus(majorSegments: 10, minorSegments: 6);
      final cube = Zero3DMeshController.cube();
      expect(sphere.vertexCount, equals(9 * 13));
      expect(sphere.triangleCount, equals(8 * 12 * 2));
      expect(torus.triangleCount, equals(120));
      expect(cube.triangleCount, equals(12));

      sphere.rotateBy(0.25, 0.5);
      expect(sphere.rotationX, greaterThan(0.35));

      torus.dispose();
      cube.dispose();
      sphere.dispose();
      sphere.dispose();
      expect(sphere.isDisposed, isTrue);
      expect(sphere.vertexCount, equals(0));
      expect(sphere.triangleCount, equals(0));
    });

    testWidgets('Z3DMesh depth-sorts and renders 3D globe via Vertices.raw and detaches on unmount', (tester) async {
      final controller = Zero3DMeshController.sphere(latSegments: 10, lonSegments: 14);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Z3DGlobe(
              controller: controller,
              size: const Size(240.0, 240.0),
            ),
          ),
        ),
      );

      final renderMesh = tester.renderObject<RenderZ3DMesh>(find.byType(Z3DMesh));
      expect(renderMesh.isRepaintBoundary, isTrue);
      expect(renderMesh.lastVisibleTriangles, greaterThan(0));
      expect(renderMesh.lastVisibleTriangles, lessThan(controller.triangleCount));

      await tester.drag(find.byType(Z3DMesh), const Offset(45.0, -30.0));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });
}

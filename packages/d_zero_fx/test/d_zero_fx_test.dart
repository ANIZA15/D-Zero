import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_fx/d_zero_fx.dart';

void main() {
  group('ZShimmer & ZBlur', () {
    testWidgets('ZShimmer renders and stops ticker on unmount', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZShimmer(
              size: Size(200.0, 28.0),
              borderRadius: 8.0,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      final RenderZShimmer renderObj = tester.renderObject(find.byType(ZShimmer));
      expect(renderObj.isRepaintBoundary, isTrue);
      expect(renderObj.phase, greaterThan(0.0));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ZBlur renders glass surface and updates properties', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZGlassContainer(
              size: Size(180.0, 90.0),
              highlightIntensity: 0.25,
            ),
          ),
        ),
      );
      final RenderZBlur renderObj = tester.renderObject(find.byType(ZBlur));
      expect(renderObj.isRepaintBoundary, isTrue);
      expect(renderObj.highlightIntensity, closeTo(0.25, 0.001));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('ZeroRippleController & ZRipple', () {
    test('ZeroRippleController survives double dispose and post-dispose access', () {
      final ZeroRippleController controller = ZeroRippleController(capacity: 8);
      controller.trigger(20.0, 30.0);
      expect(controller.activeCount, equals(1));
      expect(controller.step(0.1), isTrue);

      controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(() => controller.dispose(), returnsNormally);
      expect(controller.activeCount, equals(0));
      expect(controller.xAt(0), equals(0.0));
      expect(controller.yAt(0), equals(0.0));
      expect(controller.progressAt(0), equals(0.0));
      expect(() => controller.trigger(10.0, 10.0), returnsNormally);
      expect(controller.step(0.1), isFalse);
    });

    testWidgets('ZRipple spawns ripple on tap and cleans up on unmount', (tester) async {
      final ZeroRippleController controller = ZeroRippleController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZRipple(
              controller: controller,
              size: const Size(200.0, 80.0),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ZRipple));
      expect(controller.activeCount, equals(1));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.progressAt(0), greaterThan(0.0));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => controller.trigger(50.0, 20.0), returnsNormally);
      controller.dispose();
    });
  });

  group('ZLiquidProgress', () {
    testWidgets('ZLiquidProgress updates without rebuild and unsubscribes on unmount', (tester) async {
      final ZeroDoubleNotifier progress = ZeroDoubleNotifier(0.35);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZLiquidProgress(
              valueListenable: progress,
              size: const Size(120.0, 120.0),
            ),
          ),
        ),
      );

      progress.value = 0.75;
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(progress.hasListeners, isFalse);
      expect(() => progress.value = 0.95, returnsNormally);
      progress.dispose();
    });
  });

  group('ZMeshGradient & Z3DTilt', () {
    testWidgets('ZMeshGradient animates raw vertex mesh and stops on unmount', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZFluidGradient(
              size: Size(240.0, 140.0),
              warpIntensity: 0.35,
              borderRadius: 12.0,
            ),
          ),
        ),
      );

      final renderMesh = tester.renderObject<RenderZMeshGradient>(find.byType(ZMeshGradient));
      expect(renderMesh.isRepaintBoundary, isTrue);

      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.drag(find.byType(ZMeshGradient), const Offset(30.0, 20.0));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Z3DTilt updates TransformLayer without rebuilding child and unsubscribes on unmount', (tester) async {
      final tilt = ValueNotifier<Offset>(Offset.zero);
      addTearDown(tilt.dispose);
      int childBuilds = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZParallaxContainer(
              tiltListenable: tilt,
              child: Builder(
                builder: (context) {
                  childBuilds++;
                  return const SizedBox(width: 180.0, height: 120.0);
                },
              ),
            ),
          ),
        ),
      );

      final renderTilt = tester.renderObject<RenderZ3DTilt>(find.byType(Z3DTilt));
      expect(renderTilt.isRepaintBoundary, isTrue);
      expect(childBuilds, equals(1));

      tilt.value = const Offset(0.5, -0.4);
      await tester.pump();
      expect(renderTilt.normalizedTiltX, closeTo(0.5, 1e-3));
      expect(renderTilt.normalizedTiltY, closeTo(-0.4, 1e-3));
      expect(childBuilds, equals(1));

      await tester.drag(find.byType(Z3DTilt), const Offset(25.0, -15.0));
      await tester.pump();
      expect(childBuilds, equals(1));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => tilt.value = const Offset(0.9, 0.9), returnsNormally);
    });
  });

  group('ZShaderSurface & ZMetaballs3D', () {
    test('ZeroShaderController manages uniform slots and survives double-dispose', () {
      final controller = ZeroShaderController(uniformCount: 8);
      controller.setUniform(0, 1.25);
      controller.setUniformColor(1, const Color(0xFF00FF88));
      expect(controller.uniformAt(0), closeTo(1.25, 1e-4));
      expect(controller.uniformAt(2), closeTo(1.0, 1e-3));

      controller.dispose();
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      controller.setUniform(0, 9.0);
      expect(controller.uniformAt(0), equals(0.0));
    });

    testWidgets('ZShaderSurface & ZMetaballs3D render 3D surfaces and clean up on unmount', (tester) async {
      final shaderCtrl = ZeroShaderController(uniformCount: 6);
      addTearDown(shaderCtrl.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              ZRuntimeShader(
                controller: shaderCtrl,
                size: const Size(240.0, 120.0),
              ),
              const ZRaymarchSurface(
                size: Size(240.0, 140.0),
                smoothness: 0.4,
              ),
            ],
          ),
        ),
      );

      expect(shaderCtrl.hasListeners, isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.drag(find.byType(ZShaderSurface), const Offset(20.0, 15.0));
      await tester.drag(find.byType(ZMetaballs3D), const Offset(-20.0, 10.0));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(shaderCtrl.hasListeners, isFalse);
    });
  });

  group('ZSwipeDeck, ZScratchCard & ZBeforeAfterSlider', () {
    test('ZeroSwipeDeckController & ZeroScratchCardController survive double-dispose', () {
      final swipe = ZeroSwipeDeckController(cardCount: 5);
      swipe.setDrag(45.0, -10.0);
      expect(swipe.dragDx, closeTo(45.0, 1e-4));
      swipe.swipeNext();
      expect(swipe.topIndex, equals(1));
      swipe.dispose();
      swipe.dispose();
      expect(swipe.topIndex, equals(0));

      final scratch = ZeroScratchCardController(cols: 8, rows: 6);
      scratch.scratchAtNormalized(0.5, 0.5);
      expect(scratch.scratchPercent, greaterThan(0.0));
      scratch.reset();
      expect(scratch.scratchPercent, equals(0.0));
      scratch.dispose();
      scratch.dispose();
      scratch.scratchAtNormalized(0.2, 0.2);
      expect(scratch.scratchPercent, equals(0.0));
    });

    testWidgets('Interactive FX widgets handle pointer drag and unmount cleanly', (tester) async {
      final swipe = ZeroSwipeDeckController();
      final scratch = ZeroScratchCardController();
      final split = ValueNotifier<double>(0.5);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              ZTinderCards(controller: swipe),
              ZScratchOff(controller: scratch),
              ZImageComparison(splitListenable: split, controller: split),
            ],
          ),
        ),
      );

      await tester.drag(find.byType(ZSwipeDeck), const Offset(60.0, 0.0));
      await tester.drag(find.byType(ZScratchCard), const Offset(30.0, 20.0));
      await tester.drag(find.byType(ZBeforeAfterSlider), const Offset(25.0, 0.0));
      await tester.pump();

      expect(scratch.scratchPercent, greaterThan(0.0));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(swipe.hasListeners, isFalse);
      expect(scratch.hasListeners, isFalse);

      swipe.dispose();
      scratch.dispose();
      split.dispose();
    });
  });
}

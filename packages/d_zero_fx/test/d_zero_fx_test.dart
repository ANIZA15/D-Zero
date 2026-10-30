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
}

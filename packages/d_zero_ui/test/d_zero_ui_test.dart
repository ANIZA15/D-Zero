import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_ui/d_zero_ui.dart';

void main() {
  group('ZMarquee & ZTypewriterText', () {
    testWidgets('ZMarquee scrolls on frame ticks and unmounts cleanly', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 150,
              height: 30,
              child: ZMarquee(
                text: 'Zero Allocation Marquee Stream',
                velocity: 80.0,
                gap: 32.0,
              ),
            ),
          ),
        ),
      );

      final renderObj = tester.renderObject<RenderZMarquee>(find.byType(ZMarquee));
      expect(renderObj.isRepaintBoundary, isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      expect(renderObj.scrollOffset, greaterThan(0.0));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ZTypewriterText reveals characters progressively and unmounts cleanly', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 30,
              child: ZTypewriterText(
                text: 'Hello Impeller!',
                charDuration: Duration(milliseconds: 20),
              ),
            ),
          ),
        ),
      );

      final renderObj =
          tester.renderObject<RenderZTypewriterText>(find.byType(ZTypewriterText));
      expect(renderObj.isRepaintBoundary, isTrue);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 100));
      expect(renderObj.visibleChars, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('ZLinearProgress & ZCircularProgress', () {
    testWidgets('updates without widget rebuilds and cleans up listeners on unmount', (tester) async {
      final progress = ValueNotifier<double>(0.25);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              SizedBox(
                width: 200,
                height: 24,
                child: ZLinearProgress(
                  valueListenable: progress,
                  showPercentage: true,
                ),
              ),
              SizedBox(
                width: 64,
                height: 64,
                child: ZCircularProgress(
                  valueListenable: progress,
                  showPercentage: true,
                ),
              ),
            ],
          ),
        ),
      );

      progress.value = 0.75;
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      // Updating after unmount must not throw or trigger detached render objects.
      progress.value = 1.0;
      progress.dispose();
    });
  });

  group('ZSlider & ZRangeSlider', () {
    testWidgets('ZSlider handles pointer drag and updates controller', (tester) async {
      final controller = ValueNotifier<double>(0.1);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 240,
              height: 40,
              child: ZSlider(
                controller: controller,
                min: 0.0,
                max: 100.0,
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ZSlider), const Offset(80.0, 0.0));
      await tester.pump();
      expect(controller.value, greaterThan(10.0));

      await tester.pumpWidget(const SizedBox.shrink());
      controller.value = 50.0;
      controller.dispose();
    });

    testWidgets('ZRangeSlider and ZeroRangeValuesController handle drag and double-dispose safety', (tester) async {
      final rangeController = ZeroRangeValuesController(20.0, 80.0);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 240,
              height: 44,
              child: ZRangeSlider(
                controller: rangeController,
                min: 0.0,
                max: 100.0,
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(tester.getTopLeft(find.byType(ZRangeSlider)) + const Offset(20.0, 15.0));
      await tester.pump();
      expect(rangeController.start, lessThan(20.0));

      await tester.pumpWidget(const SizedBox.shrink());

      // Double-dispose and post-dispose access safety
      rangeController.dispose();
      rangeController.dispose();
      expect(rangeController.isDisposed, isTrue);
      expect(rangeController.start, equals(0.0));
      expect(rangeController.end, equals(0.0));
      rangeController.setRange(10.0, 90.0);
      expect(rangeController.start, equals(0.0));
    });
  });

  group('ZGauge, ZJoystick & ZKnob', () {
    testWidgets('ZGauge renders cached dial Picture and disposes cleanly', (tester) async {
      final speed = ValueNotifier<double>(42.0);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: ZGauge(
                valueListenable: speed,
                min: 0.0,
                max: 120.0,
              ),
            ),
          ),
        ),
      );

      speed.value = 88.5;
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      speed.value = 100.0;
      speed.dispose();
    });

    testWidgets('ZJoystick & ZeroJoystickController handle pointer drag, reset, and double-dispose', (tester) async {
      final joystick = ZeroJoystickController();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZJoystick(
              controller: joystick,
              size: const Size(120, 120),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ZJoystick));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(30.0, -20.0));
      await tester.pump();

      expect(joystick.dx, greaterThan(0.0));
      expect(joystick.dy, lessThan(0.0));
      expect(joystick.magnitude, greaterThan(0.0));

      await gesture.up();
      await tester.pump();
      expect(joystick.dx, equals(0.0));
      expect(joystick.dy, equals(0.0));

      await tester.pumpWidget(const SizedBox.shrink());

      joystick.update(0.5, 0.5);
      joystick.dispose();
      joystick.dispose();
      expect(joystick.isDisposed, isTrue);
      expect(joystick.dx, equals(0.0));
      expect(joystick.dy, equals(0.0));
      expect(joystick.magnitude, equals(0.0));
      joystick.update(1.0, 1.0);
      expect(joystick.dx, equals(0.0));
    });

    testWidgets('ZKnob updates value on vertical drag and unmounts cleanly', (tester) async {
      final knob = ValueNotifier<double>(50.0);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZKnob(
              controller: knob,
              min: 0.0,
              max: 100.0,
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ZKnob), const Offset(0.0, -30.0));
      await tester.pump();
      expect(knob.value, greaterThan(50.0));

      await tester.pumpWidget(const SizedBox.shrink());
      knob.value = 25.0;
      knob.dispose();
    });
  });
}

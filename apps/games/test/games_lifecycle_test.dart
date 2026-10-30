import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:games/main.dart';

void main() {
  group('ZERO OVERDRIVE — Z-Widget & Engine Switching Verification', () {
    test('ZGameStage implements ZWidget with isZeroAllocation == true', () {
      final ctrl = ZeroGameController();
      addTearDown(ctrl.dispose);

      final widget = ZGameStage(controller: ctrl);
      expect(widget, isA<ZWidget>());
      expect(widget.isZeroAllocation, isTrue);
    });

    testWidgets(
      'App boots in D-Zero mode and switches to Flutter mode while preserving state',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ctrl = ZeroGameController();
        addTearDown(ctrl.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ZeroOverdriveScreen(controller: ctrl),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        expect(ctrl.engineMode, equals(GameEngineMode.dZero));
        expect(find.byType(ZGameStage), findsOneWidget);
        expect(find.byType(FlutterGameStage), findsNothing);
        expect(ctrl.dZeroRebuildsNotifier.value, equals(0));

        // Trigger Overdrive Nova & Chaos Burst in D-Zero mode
        ctrl.triggerOverdriveNova();
        ctrl.spawnChaosBurst();
        ctrl.step(0.016);
        final int scoreBeforeSwitch = ctrl.scoreNotifier.value;
        final int entitiesBeforeSwitch = ctrl.activeEntitiesNotifier.value;
        expect(entitiesBeforeSwitch, greaterThan(3000));

        // Switch to Traditional Flutter Engine
        ctrl.setEngineMode(GameEngineMode.flutter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(ctrl.engineMode, equals(GameEngineMode.flutter));
        expect(find.byType(FlutterGameStage), findsOneWidget);
        expect(find.byType(ZGameStage), findsNothing);
        expect(ctrl.scoreNotifier.value, greaterThanOrEqualTo(scoreBeforeSwitch));
        expect(ctrl.flutterRebuildsNotifier.value, greaterThan(0));
        expect(ctrl.flutterHeapAllocsNotifier.value, greaterThan(0));

        // Switch back to D-Zero Engine
        ctrl.setEngineMode(GameEngineMode.dZero);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(ctrl.engineMode, equals(GameEngineMode.dZero));
        expect(find.byType(ZGameStage), findsOneWidget);
      },
    );
  });

  group('Memory Lifecycle, Unmount & Double-Dispose Resilience', () {
    testWidgets(
      'ZGameStage & ZeroOverdriveScreen detach cleanly on unmount without leaks',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ctrl = ZeroGameController();
        addTearDown(ctrl.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ZeroOverdriveScreen(controller: ctrl),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));

        // Unmount entire screen
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // Stepping or mutating controller after unmount must not throw
        expect(() {
          ctrl.step(0.016);
          ctrl.triggerOverdriveNova();
          ctrl.toggleEngineMode();
        }, returnsNormally);
      },
    );

    test('ZeroGameController and SoA pools survive double-dispose and post-dispose access', () {
      final ctrl = ZeroGameController();
      ctrl.step(0.016);
      ctrl.dispose();

      // Double-dispose must be a safe no-op
      expect(ctrl.dispose, returnsNormally);
      expect(ctrl.isDisposed, isTrue);

      // Post-dispose mutations & reads must return safe defaults and never throw
      expect(() {
        ctrl.step(0.016);
        ctrl.triggerOverdriveNova();
        ctrl.spawnChaosBurst();
        ctrl.setEngineMode(GameEngineMode.flutter);
        ctrl.applyPreset(ParticleStressPreset.extreme);
        ctrl.updateArenaSize(800, 600);
      }, returnsNormally);

      expect(ctrl.playerX, equals(0.0));
      expect(ctrl.projectiles.activeCount, equals(0));
      expect(ctrl.enemies.activeCount, equals(0));
      expect(ctrl.sparks.activeCount, equals(0));
      expect(ctrl.projectiles.playerBoltSegments, isEmpty);
      expect(ctrl.sparks.bucketSegments(0), isEmpty);
    });

    test('Hot-path stress test: 2,500 simulation frames & bursts without buffer overflow', () {
      final ctrl = ZeroGameController();
      addTearDown(ctrl.dispose);

      ctrl.applyPreset(ParticleStressPreset.heavy);
      for (int i = 0; i < 2500; i++) {
        if (i % 250 == 0) {
          ctrl.triggerOverdriveNova();
        }
        if (i % 400 == 0) {
          ctrl.spawnChaosBurst();
        }
        ctrl.step(1.0 / 120.0);
      }

      expect(ctrl.scoreNotifier.value, greaterThan(0));
      expect(ctrl.killCountNotifier.value, greaterThan(0));
      expect(ctrl.dZeroRebuildsNotifier.value, equals(0));
    });
  });
}

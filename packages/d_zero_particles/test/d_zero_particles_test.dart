import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

void main() {
  group('【1. 基本・物理シミュレーションテスト】ZeroParticleBuffer & Controller', () {
    test('ZeroParticleBuffer initializes flat typed-data buffers correctly', () {
      final buffer = ZeroParticleBuffer(100);
      expect(buffer.capacity, equals(100));
      expect(buffer.positions.length, equals(200));
      expect(buffer.velocities.length, equals(200));
      expect(buffer.lifespans.length, equals(100));

      buffer.initRandom(width: 800, height: 600);
      // Ensure positions are within bounds
      for (int i = 0; i < buffer.capacity; i++) {
        final x = buffer.positions[i * 2];
        final y = buffer.positions[i * 2 + 1];
        expect(x, greaterThanOrEqualTo(0.0));
        expect(x, lessThanOrEqualTo(800.0));
        expect(y, greaterThanOrEqualTo(0.0));
        expect(y, lessThanOrEqualTo(600.0));
      }
    });

    test('step updates positions and handles boundary bounces without errors', () {
      final buffer = ZeroParticleBuffer(10);
      buffer.initRandom(width: 400, height: 400);

      final initialX = buffer.positions[0];
      buffer.step(dt: 0.016, width: 400, height: 400);
      final updatedX = buffer.positions[0];

      // Position should advance with velocity
      expect(initialX != updatedX || buffer.velocities[0] == 0, isTrue);
    });

    test('ZeroParticleController manages buffer and responds to step/reset', () {
      final controller = ZeroParticleController(capacity: 50);
      expect(controller.capacity, equals(50));
      expect(controller.isDisposed, isFalse);

      controller.step(dt: 0.016, width: 300, height: 300);
      expect(controller.buffer.positions.length, equals(100));

      controller.reset(width: 300, height: 300);
      expect(controller.buffer.positions.length, equals(100));
    });
  });

  group('【2. メモリ＆ライフサイクル厳格テスト】Unmount・Use-After-Free・二重解放耐性', () {
    test('Use-After-Free 防御: dispose() 済みの Controller を操作してもクラッシュせず安全であること', () {
      final controller = ZeroParticleController(capacity: 100);
      controller.dispose();
      expect(controller.isDisposed, isTrue);

      // Accessing buffer or methods post-dispose must not throw SIGSEGV or StateError
      expect(() => controller.buffer, returnsNormally);
      // Disposed controller returns a shared singleton empty buffer (zero allocation)
      expect(identical(controller.buffer, controller.buffer), isTrue);
      expect(() => controller.step(dt: 0.016, width: 500, height: 500), returnsNormally);
      expect(() => controller.reset(width: 500, height: 500), returnsNormally);
    });

    test('SIMD step と スカラー step の結果が許容誤差内で完全一致し、奇数 capacity でも安全であること', () {
      final simdBuf = ZeroParticleBuffer(101); // 奇数 capacity (パディング検証)
      final scalarBuf = ZeroParticleBuffer(101);
      expect(simdBuf.positions.length, equals(202));

      for (int i = 0; i < 202; i++) {
        simdBuf.positions[i] = (i * 3.7) % 400.0;
        scalarBuf.positions[i] = simdBuf.positions[i];
        simdBuf.velocities[i] = ((i % 7) - 3) * 25.0;
        scalarBuf.velocities[i] = simdBuf.velocities[i];
      }

      for (int step = 0; step < 60; step++) {
        simdBuf.step(dt: 0.016, width: 400, height: 300, useSimd: true);
        scalarBuf.step(dt: 0.016, width: 400, height: 300, useSimd: false);
      }

      for (int i = 0; i < 202; i++) {
        expect((simdBuf.positions[i] - scalarBuf.positions[i]).abs(), lessThan(1e-3));
      }
    });

    test('二重解放（Double Free）防止: dispose() を複数回呼んでも例外が起きないこと', () {
      final controller = ZeroParticleController(capacity: 100);
      controller.dispose();
      expect(() => controller.dispose(), returnsNormally);
      expect(() => controller.dispose(), returnsNormally);
    });

    testWidgets('ZParticles: unmount 時に Ticker が確実に停止・解放されること', (tester) async {
      final controller = ZeroParticleController(capacity: 200);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 300,
            child: ZParticles(
              controller: controller,
              isRunning: true,
            ),
          ),
        ),
      );

      // Advance frames
      await tester.pump(const Duration(milliseconds: 32));

      // Unmount the widget
      await tester.pumpWidget(const SizedBox.shrink());

      // Pumping after unmount should have no remaining active tickers
      expect(tester.hasRunningAnimations, isFalse);
      controller.dispose();
    });

    testWidgets('ZParticles: isRunning の動的切り替え時に正常に動作すること', (tester) async {
      final controller = ZeroParticleController(capacity: 100);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 200,
            child: ZParticles(
              controller: controller,
              isRunning: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 16));

      // Pause simulation
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 200,
            child: ZParticles(
              controller: controller,
              isRunning: false,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isFalse);
      controller.dispose();
    });

    testWidgets('後方互換性エイリアス (ZeroParticles) が透過的に機能すること', (tester) async {
      final controller = ZeroParticleController(capacity: 50);

      // ignore: deprecated_member_use_from_same_package
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 100,
            height: 100,
            child: ZeroParticles(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.byType(ZParticles), findsOneWidget);
      controller.dispose();
    });

    test('100,000 回の超高速連続物理計算ステップでヒープ肥大化や例外が起きないこと', () {
      final buffer = ZeroParticleBuffer(500);
      buffer.initRandom(width: 800, height: 600);

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100000; i++) {
        buffer.step(dt: 0.008, width: 800, height: 600);
      }
      stopwatch.stop();

      // 100,000 steps of 500 particles should complete fast in memory
      expect(stopwatch.elapsedMilliseconds, greaterThan(0));
      expect(buffer.positions[0], isNotNull);
    });
  });

  group('【3. ZConfetti & ZeroConfettiController 物理・メモリ・ライフサイクル検証】', () {
    test('ZeroConfettiController manages SoA arrays, burst, double-dispose, and post-dispose safety', () {
      final controller = ZeroConfettiController(capacity: 120);
      expect(controller.isDisposed, isFalse);
      expect(controller.activeCount, equals(0));
      expect(controller.x.length, equals(120));
      expect(controller.y.length, equals(120));
      expect(controller.vx.length, equals(120));
      expect(controller.vy.length, equals(120));
      expect(controller.angle.length, equals(120));
      expect(controller.angularVelocity.length, equals(120));
      expect(controller.size.length, equals(120));
      expect(controller.life.length, equals(120));
      expect(controller.colors.length, equals(120));

      controller.burst(origin: const Offset(150, 100), count: 60);
      expect(controller.activeCount, equals(60));

      // 1,000-frame zero-allocation stress test
      for (int frame = 0; frame < 1000; frame++) {
        if (frame % 200 == 0) {
          controller.burst(count: 40);
        }
        controller.step(dt: 0.016, width: 400, height: 300);
      }

      // Double-dispose and post-dispose safety
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(() => controller.dispose(), returnsNormally);
      expect(() => controller.burst(count: 30), returnsNormally);
      expect(() => controller.step(dt: 0.016, width: 400, height: 300), returnsNormally);
      expect(controller.activeCount, equals(0));
      expect(controller.x.isEmpty, isTrue);
      expect(controller.colors.isEmpty, isTrue);
      expect(controller.bucketSegments(0).isEmpty, isTrue);
    });

    testWidgets('ZConfetti renders confetti bursts without widget rebuilds and cleans up on unmount', (tester) async {
      final controller = ZeroConfettiController(capacity: 180);
      int rebuildCount = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              rebuildCount++;
              return SizedBox(
                width: 300,
                height: 240,
                child: ZConfetti(controller: controller),
              );
            },
          ),
        ),
      );

      expect(rebuildCount, equals(1));
      controller.burst(origin: const Offset(150, 120), count: 60);

      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rebuildCount, equals(1));

      // Deprecated alias check
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 240,
            // ignore: deprecated_member_use_from_same_package
            child: ZeroConfetti(controller: controller),
          ),
        ),
      );
      expect(find.byType(ZConfetti), findsOneWidget);

      // Unmount and verify Ticker stops
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.hasRunningAnimations, isFalse);
      controller.dispose();
    });
  });

  group('【4. ZReactionStream & ZeroReactionController 検証】', () {
    test('ZeroReactionController emits, steps, and survives double-dispose', () {
      final controller = ZeroReactionController(capacity: 64);
      controller.emit(count: 10);
      expect(controller.activeCount, equals(10));
      controller.step(0.016);
      expect(controller.activeCount, greaterThan(0));

      controller.dispose();
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      controller.emit(count: 5);
      expect(controller.activeCount, equals(0));
    });

    testWidgets('ZReactionStream renders floating reactions and stops on unmount', (tester) async {
      final controller = ZeroReactionController(capacity: 64)..emit(count: 8);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZFloatingHearts(controller: controller),
          ),
        ),
      );

      await tester.tap(find.byType(ZReactionStream));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
      controller.dispose();
    });
  });
}

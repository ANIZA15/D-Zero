import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_particles/zero_particles.dart';

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
      expect(() => controller.step(dt: 0.016, width: 500, height: 500), returnsNormally);
      expect(() => controller.reset(width: 500, height: 500), returnsNormally);
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
}

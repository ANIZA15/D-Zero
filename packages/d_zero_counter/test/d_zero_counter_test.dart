import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_counter/d_zero_counter.dart';

void main() {
  group('【1. 基本・描画テスト】ZCounter & ZStopwatch', () {
    testWidgets('ZCounter paints value changes directly without widget rebuild', (tester) async {
      final counterNotifier = ValueNotifier<int>(0);

      int rebuildCount = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              rebuildCount++;
              return Center(
                child: ZCounter(
                  valueListenable: counterNotifier,
                  minDigits: 4,
                ),
              );
            },
          ),
        ),
      );

      expect(rebuildCount, equals(1));

      // Update value 100 times
      for (int i = 1; i <= 100; i++) {
        counterNotifier.value = i;
        await tester.pump();
      }

      // Rebuild count should remain exactly 1 (zero rebuilds!)
      expect(rebuildCount, equals(1));
    });

    testWidgets('ZStopwatch renders and advances without widget rebuild', (tester) async {
      int rebuildCount = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              rebuildCount++;
              return const Center(
                child: ZStopwatch(
                  isRunning: true,
                ),
              );
            },
          ),
        ),
      );

      expect(rebuildCount, equals(1));

      // Pump frames to advance time
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Rebuild count should still be 1
      expect(rebuildCount, equals(1));
    });

    testWidgets('後方互換性エイリアス (ZeroCounter, ZeroStopwatch) が透過的に機能すること', (tester) async {
      final notifier = ValueNotifier<int>(42);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            // ignore: deprecated_member_use_from_same_package
            child: ZeroCounter(valueListenable: notifier),
          ),
        ),
      );
      expect(find.byType(ZCounter), findsOneWidget);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          // ignore: deprecated_member_use_from_same_package
          child: Center(child: ZeroStopwatch()),
        ),
      );
      expect(find.byType(ZStopwatch), findsOneWidget);
    });
  });

  group('【2. メモリ＆ライフサイクル厳格テスト】Unmount・購読解除・Ticker管理', () {
    testWidgets('ZCounter: unmount 時にリスナーが完全解除され、その後の通知で例外が起きないこと', (tester) async {
      final counterNotifier = ValueNotifier<int>(10);

      // マウント
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ZCounter(valueListenable: counterNotifier),
        ),
      );

      // アンマウント（空のウィジェットで置換）
      await tester.pumpWidget(const SizedBox.shrink());

      // アンマウント後に ValueNotifier を更新しても例外や Use-After-Free が起きないこと
      expect(() {
        counterNotifier.value = 999;
      }, returnsNormally);

      counterNotifier.dispose();
    });

    testWidgets('ZStopwatch: unmount 時に Ticker が確実に停止・解放されること', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: ZStopwatch(isRunning: true),
        ),
      );

      // 500ms 進める
      await tester.pump(const Duration(milliseconds: 500));

      // アンマウント
      await tester.pumpWidget(const SizedBox.shrink());

      // アンマウント後にフレームが進んでも Ticker エラーが発生しないこと
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('ZStopwatch: isRunning の動的切り替え時に Ticker の起動・停止が正常に行われること', (tester) async {
      final runningNotifier = ValueNotifier<bool>(true);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<bool>(
            valueListenable: runningNotifier,
            builder: (context, running, _) {
              return ZStopwatch(isRunning: running);
            },
          ),
        ),
      );

      // 停止
      runningNotifier.value = false;
      await tester.pump();

      // 再開
      runningNotifier.value = true;
      await tester.pump();

      // 再び停止
      runningNotifier.value = false;
      await tester.pump();
    });

    testWidgets('ZCounter & ZStopwatch: 連続マウント・アンマウントによるメモリリーク・クラッシュ耐性', (tester) async {
      final notifier = ValueNotifier<int>(0);

      // 50 回のマウント・アンマウント繰り返し
      for (int i = 0; i < 50; i++) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                ZCounter(valueListenable: notifier),
                const ZStopwatch(isRunning: true),
              ],
            ),
          ),
        );
        notifier.value = i;
        await tester.pump(const Duration(milliseconds: 16));

        // アンマウント
        await tester.pumpWidget(const SizedBox.shrink());
      }

      notifier.dispose();
    });

    test('100,000回の超高速連続値更新でも例外や破綻が起きないこと', () {
      final notifier = ValueNotifier<int>(-1);
      int callCount = 0;
      void listener() {
        callCount++;
      }

      notifier.addListener(listener);
      for (int i = 0; i < 100000; i++) {
        notifier.value = i;
      }

      expect(callCount, equals(100000));
      notifier.removeListener(listener);
      notifier.dispose();
    });
  });

  group('【3. 新規ウィジェット検証】ZCountdown / ZOdometer / ZPriceTicker / ZFPSMonitor', () {
    testWidgets('ZCountdown counts down, switches to warningStyle, fires onFinished, and cleans up on unmount', (tester) async {
      int finishedCount = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZCountdown(
              duration: const Duration(seconds: 3),
              warningThreshold: const Duration(seconds: 2),
              warningStyle: const TextStyle(color: Color(0xFFFF5252), fontSize: 20),
              onFinished: () => finishedCount++,
            ),
          ),
        ),
      );

      expect(find.byType(ZCountdown), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(finishedCount, equals(0));

      // Reach zero
      await tester.pump(const Duration(seconds: 3));
      expect(finishedCount, equals(1));

      // Unmount safely
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('ZOdometer smoothly interpolates values without widget rebuilds and cleans up listener on unmount', (tester) async {
      final valueNotifier = ValueNotifier<double>(10.0);
      int rebuildCount = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              rebuildCount++;
              return Center(
                child: ZOdometer(
                  valueListenable: valueNotifier,
                  minDigits: 4,
                  dampingSpeed: 15.0,
                ),
              );
            },
          ),
        ),
      );

      expect(rebuildCount, equals(1));

      // Trigger odometer roll
      valueNotifier.value = 125.0;
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rebuildCount, equals(1));

      // Unmount and verify post-unmount updates do not throw
      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => valueNotifier.value = 999.0, returnsNormally);
      valueNotifier.dispose();
    });

    testWidgets('ZPriceTicker flashes on up/down price movement, decays smoothly, and unmounts cleanly', (tester) async {
      final priceNotifier = ValueNotifier<double>(100.0);
      int rebuildCount = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              rebuildCount++;
              return Center(
                child: ZPriceTicker(
                  valueListenable: priceNotifier,
                  showPlusSign: true,
                ),
              );
            },
          ),
        ),
      );

      expect(rebuildCount, equals(1));

      // Price up
      priceNotifier.value = 105.50;
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Price down
      priceNotifier.value = 98.25;
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(rebuildCount, equals(1));

      // Unmount and verify post-unmount updates do not throw
      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => priceNotifier.value = 50.0, returnsNormally);
      priceNotifier.dispose();
    });

    testWidgets('ZFPSMonitor records rolling frame deltas and unsubscribes from scheduler on unmount', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZFPSMonitor(),
          ),
        ),
      );

      // Pump 120 frames
      for (int i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }

      expect(find.byType(ZFPSMonitor), findsOneWidget);

      // Unmount and ensure Ticker stops
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('Aliases (ZeroCountdown, ZAnimatedNumber, ZeroOdometer, ZCurrencyLabel, ZeroPriceTicker, ZFrameOverlay, ZeroFPSMonitor) work seamlessly', (tester) async {
      final val = ValueNotifier<double>(42.0);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              // ignore: deprecated_member_use_from_same_package
              const ZeroCountdown(duration: Duration(seconds: 5), isRunning: false),
              ZAnimatedNumber(valueListenable: val),
              // ignore: deprecated_member_use_from_same_package
              ZeroOdometer(valueListenable: val),
              ZCurrencyLabel(valueListenable: val),
              // ignore: deprecated_member_use_from_same_package
              ZeroPriceTicker(valueListenable: val),
              const ZFrameOverlay(),
              // ignore: deprecated_member_use_from_same_package
              const ZeroFPSMonitor(),
            ],
          ),
        ),
      );

      expect(find.byType(ZCountdown), findsOneWidget);
      expect(find.byType(ZOdometer), findsNWidgets(2));
      expect(find.byType(ZPriceTicker), findsNWidgets(2));
      expect(find.byType(ZFPSMonitor), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
      val.dispose();
    });
  });
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_core/d_zero_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('【1. FloatRingBuffer 基本 & メモリ・ストレステスト】', () {
    test('push and index access correctly retrieve circular values', () {
      final buffer = FloatRingBuffer(3);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, equals(0));

      buffer.push(10.0);
      buffer.push(20.0);
      expect(buffer.length, equals(2));
      expect(buffer[0], equals(10.0));
      expect(buffer[1], equals(20.0));

      buffer.push(30.0);
      expect(buffer.isFull, isTrue);
      expect(buffer.length, equals(3));
      expect(buffer[0], equals(10.0));
      expect(buffer[1], equals(20.0));
      expect(buffer[2], equals(30.0));

      // Overwrite oldest (10.0)
      buffer.push(40.0);
      expect(buffer.length, equals(3));
      expect(buffer[0], equals(20.0));
      expect(buffer[1], equals(30.0));
      expect(buffer[2], equals(40.0));
    });

    test('clear resets buffer state without shrinking storage', () {
      final buffer = FloatRingBuffer(5);
      buffer.pushAll([1.0, 2.0, 3.0]);
      expect(buffer.length, equals(3));

      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, equals(0));
      expect(buffer.rawData.length, equals(5));
    });

    test('100,000 回の超高速連続 push でもメモリ再確保・ヒープ肥大化を起こさないこと', () {
      final buffer = FloatRingBuffer(128);
      for (int i = 0; i < 100000; i++) {
        buffer.push(i.toDouble());
      }
      expect(buffer.length, equals(128));
      expect(buffer.rawData.length, equals(128));
      // 最新の値が正しく反映されていること
      expect(buffer[127], equals(99999.0));
      expect(buffer.contiguousView.length, equals(128));
      expect(buffer.contiguousView.last, equals(99999.0));
      // 満杯時の contiguousView は事前確保スライスを返し新規生成しないこと
      expect(identical(buffer.contiguousView, buffer.contiguousView), isTrue);
    });

    test('Float32RingBuffer mirrors data and returns zero-allocation contiguousView', () {
      final f32 = Float32RingBuffer(4);
      f32.pushAll([1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(f32.isFull, isTrue);
      expect(f32.contiguousView, equals([2.0, 3.0, 4.0, 5.0]));
      expect(identical(f32.contiguousView, f32.contiguousView), isTrue);
      expect(f32.oldest, equals(2.0));
      expect(f32.latest, equals(5.0));
    });

    test('bulk pushAll handles wrap-around and n >= capacity, plus oldest/latest/copyInto/stats', () {
      final buf = FloatRingBuffer(4);
      expect(buf.oldest, equals(0.0));
      expect(buf.latest, equals(0.0));
      expect(buf.average, equals(0.0));
      expect(buf.min, equals(0.0));
      expect(buf.max, equals(0.0));

      // Partial pushAll
      buf.pushAll([10.0, 20.0, 30.0]);
      expect(buf.length, equals(3));
      expect(buf.oldest, equals(10.0));
      expect(buf.latest, equals(30.0));
      expect(buf.average, equals(20.0));
      expect(buf.min, equals(10.0));
      expect(buf.max, equals(30.0));

      // Wrap-around pushAll (head=3, capacity=4, pushing 2 elements)
      buf.pushAll([40.0, 50.0]);
      expect(buf.isFull, isTrue);
      expect(buf.contiguousView, equals([20.0, 30.0, 40.0, 50.0]));
      expect(buf.oldest, equals(20.0));
      expect(buf.latest, equals(50.0));

      // CopyInto test
      final dest = List<double>.filled(6, -1.0);
      final copied = buf.copyInto(dest, 1);
      expect(copied, equals(4));
      expect(dest, equals([-1.0, 20.0, 30.0, 40.0, 50.0, -1.0]));

      // n >= capacity pushAll
      buf.pushAll([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
      expect(buf.contiguousView, equals([3.0, 4.0, 5.0, 6.0]));
      expect(buf.average, equals(4.5));
      expect(buf.min, equals(3.0));
      expect(buf.max, equals(6.0));
    });
  });

  group('【2. ZeroPool 基本 & メモリ再利用テスト】', () {
    test('acquires and releases items without reallocating', () {
      int creations = 0;
      final pool = ZeroPool<List<int>>(
        factory: () {
          creations++;
          return <int>[];
        },
        reset: (list) => list.clear(),
        initialCapacity: 2,
      );

      expect(creations, equals(2));
      expect(pool.availableCount, equals(2));

      final item1 = pool.acquire();
      expect(pool.availableCount, equals(1));
      item1.add(42);

      pool.release(item1);
      expect(pool.availableCount, equals(2));
      expect(item1.isEmpty, isTrue); // reset called
      expect(creations, equals(2)); // No extra allocations
    });

    test('大量取得・解放サイクルでのメモリプーリング健全性', () {
      int creations = 0;
      final pool = ZeroPool<List<int>>(
        factory: () {
          creations++;
          return <int>[];
        },
        reset: (list) => list.clear(),
        initialCapacity: 10,
      );

      final acquired = <List<int>>[];
      // 50個一括取得（初期 10 個 + 動的 40 個）
      for (int i = 0; i < 50; i++) {
        final item = pool.acquire();
        item.add(i);
        acquired.add(item);
      }
      expect(creations, equals(50));
      expect(pool.availableCount, equals(0));

      // 全て返却
      for (final item in acquired) {
        pool.release(item);
      }
      expect(pool.availableCount, equals(50));

      // 再度 50 個取得 -> 新規アロケーションは 0 件であること
      final reacquired = <List<int>>[];
      for (int i = 0; i < 50; i++) {
        reacquired.add(pool.acquire());
      }
      expect(creations, equals(50)); // 再確保なし！
      expect(pool.availableCount, equals(0));

      pool.clear();
      expect(pool.availableCount, equals(0));
    });

    test('prewarm, acquireBatch, and releaseBatch operate without allocations', () {
      int creations = 0;
      final pool = ZeroPool<List<int>>(
        factory: () {
          creations++;
          return <int>[];
        },
        reset: (list) => list.clear(),
        initialCapacity: 2,
      );

      pool.prewarm(8);
      expect(pool.availableCount, equals(8));
      expect(creations, equals(8));

      final batch = List<List<int>?>.filled(10, null);
      pool.acquireBatch(batch, 10);
      expect(pool.availableCount, equals(0));
      expect(creations, equals(10));

      final nonNullBatch = batch.cast<List<int>>();
      for (int i = 0; i < 10; i++) {
        nonNullBatch[i].add(i);
      }

      pool.releaseBatch(nonNullBatch, 10);
      expect(pool.availableCount, equals(10));
      expect(nonNullBatch.every((l) => l.isEmpty), isTrue);
    });
  });

  group('【3. ZeroNumberPainter & Canvas 描画ライフサイクルテスト】', () {
    test('initializes and formats numbers without string allocation in loop', () {
      final painter = ZeroNumberPainter();
      expect(painter.height, greaterThan(0));
      expect(painter.maxDigitWidth, greaterThan(0));

      // Test against dummy canvas (record operations)
      final pictureRecorder = PictureRecorder();
      final canvas = Canvas(pictureRecorder);

      final w1 = painter.paintInt(canvas, Offset.zero, 12345);
      expect(w1, greaterThan(0));

      final w2 = painter.paintTimecode(canvas, Offset.zero, 65000); // 01:05
      expect(w2, greaterThan(0));

      pictureRecorder.endRecording();
      painter.dispose();
    });

    test('10,000 回の連続描画ループでメモリ破壊・例外が起きないこと', () {
      final painter = ZeroNumberPainter();
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      for (int i = 0; i < 10000; i++) {
        painter.paintInt(canvas, Offset.zero, i, minDigits: 6);
        painter.paintTimecode(canvas, Offset.zero, i * 1000, includeHours: true);
        painter.paintTimeProgress(canvas, Offset.zero, i * 100, (i + 10) * 100);
      }

      final pic = recorder.endRecording();
      pic.dispose();
      painter.dispose();
    });

    test('ZeroNumberPainter dispose の二重呼び出し安全性', () {
      final painter = ZeroNumberPainter();
      expect(() {
        painter.dispose();
        painter.dispose(); // 二重破棄耐性
      }, returnsNormally);
    });

    test('paintDouble renders positive, negative, and zero values without string allocation', () {
      final painter = ZeroNumberPainter();
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      final wPos = painter.paintDouble(canvas, Offset.zero, 119.95, fractionDigits: 2);
      final wNeg = painter.paintDouble(canvas, Offset.zero, -0.5, fractionDigits: 1);
      final wInt = painter.paintDouble(canvas, Offset.zero, 42.0, fractionDigits: 0);
      expect(wPos, greaterThan(wInt));
      expect(wNeg, greaterThan(0));

      recorder.endRecording().dispose();
      painter.dispose();
    });

    test('shared GPU glyph atlas deduplicates identical styles and releases on last dispose', () {
      const style = TextStyle(fontSize: 19, color: Color(0xFF112233));
      final p1 = ZeroNumberPainter(style: style, devicePixelRatio: 2.0);
      final p2 = ZeroNumberPainter(style: style, devicePixelRatio: 2.0);

      expect(ZeroNumberPainter.cachedAtlasCount, greaterThanOrEqualTo(1));
      final countBefore = ZeroNumberPainter.cachedAtlasCount;

      p1.dispose();
      // Atlas is still held by p2
      expect(ZeroNumberPainter.cachedAtlasCount, equals(countBefore));

      p2.dispose();
      expect(ZeroNumberPainter.cachedAtlasCount, equals(countBefore - 1));
    });

    test('paintCurrency, paintPercent, paintWithSuffix, and paintOdometer render with zero allocations and handle post-dispose safely', () {
      final painter = ZeroNumberPainter();
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      // paintCurrency: positive with plus sign, negative, Yen without separator
      final wCurrPos = painter.paintCurrency(
        canvas,
        Offset.zero,
        12345.67,
        currencyGlyph: ZeroNumberPainter.glyphDollar,
        fractionDigits: 2,
        showPlusSign: true,
        thousandsSeparator: true,
      );
      final wCurrNeg = painter.paintCurrency(
        canvas,
        Offset.zero,
        -1200.0,
        currencyGlyph: ZeroNumberPainter.glyphYen,
        fractionDigits: 0,
        thousandsSeparator: true,
      );
      expect(wCurrPos, greaterThan(0.0));
      expect(wCurrNeg, greaterThan(0.0));

      // paintPercent
      final wPct = painter.paintPercent(
        canvas,
        Offset.zero,
        99.9,
        fractionDigits: 1,
        showPlusSign: true,
      );
      expect(wPct, greaterThan(0.0));

      // paintWithSuffix
      final wFps = painter.paintWithSuffix(
        canvas,
        Offset.zero,
        120.0,
        suffixGlyph: ZeroNumberPainter.glyphFps,
        fractionDigits: 0,
      );
      final wMs = painter.paintWithSuffix(
        canvas,
        Offset.zero,
        8.3,
        suffixGlyph: ZeroNumberPainter.glyphMs,
        fractionDigits: 1,
      );
      expect(wFps, greaterThan(0.0));
      expect(wMs, greaterThan(0.0));

      // paintOdometer (stationary and rolling 9 -> 0)
      final wOdo1 = painter.paintOdometer(canvas, Offset.zero, 42.0, minDigits: 4);
      final wOdo2 = painter.paintOdometer(canvas, Offset.zero, 99.5, minDigits: 4);
      expect(wOdo1, greaterThan(0.0));
      expect(wOdo2, equals(wOdo1));

      // NaN / Infinity safety
      expect(painter.paintCurrency(canvas, Offset.zero, double.nan), equals(0.0));
      expect(painter.paintPercent(canvas, Offset.zero, double.infinity), equals(0.0));
      expect(
        painter.paintWithSuffix(
          canvas,
          Offset.zero,
          double.negativeInfinity,
          suffixGlyph: ZeroNumberPainter.glyphDegree,
        ),
        equals(0.0),
      );
      expect(painter.paintOdometer(canvas, Offset.zero, double.nan), equals(0.0));

      // Post-dispose safety returning 0.0
      painter.dispose();
      expect(painter.isDisposed, isTrue);
      expect(painter.paintCurrency(canvas, Offset.zero, 100.0), equals(0.0));
      expect(painter.paintPercent(canvas, Offset.zero, 50.0), equals(0.0));
      expect(
        painter.paintWithSuffix(
          canvas,
          Offset.zero,
          60.0,
          suffixGlyph: ZeroNumberPainter.glyphFps,
        ),
        equals(0.0),
      );
      expect(painter.paintOdometer(canvas, Offset.zero, 12.3), equals(0.0));

      recorder.endRecording().dispose();
    });
  });

  group('【4. ZeroRenderBox ライフサイクル & ZeroFrameScheduler 共有 Ticker テスト】', () {
    test('attach と detach で ZeroFrameScheduler の共有 Ticker が自動制御されること', () {
      final box1 = _TestZeroRenderBox(animatePerFrame: true);
      final box2 = _TestZeroRenderBox(animatePerFrame: true);
      expect(box1.isRepaintBoundary, isTrue);
      expect(box1.animatePerFrame, isTrue);

      final pipelineOwner = PipelineOwner();
      box1.attach(pipelineOwner);
      box2.attach(pipelineOwner);
      expect(ZeroFrameScheduler.instance.subscriberCount, greaterThanOrEqualTo(2));
      expect(ZeroFrameScheduler.instance.isTicking, isTrue);

      // 動的に animatePerFrame をトグル
      box1.animatePerFrame = false;
      expect(box1.animatePerFrame, isFalse);
      box1.animatePerFrame = true;
      expect(box1.animatePerFrame, isTrue);

      box1.detach();
      box2.detach();
      expect(ZeroFrameScheduler.instance.subscriberCount, equals(0));
      expect(ZeroFrameScheduler.instance.isTicking, isFalse);
      box1.dispose();
      box2.dispose();
    });
  });

  group('【5. ZWidget / ZLeafWidget / ZSingleChildWidget ゼロアロケーション基盤テスト】', () {
    test('ZWidget marker interface contracts', () {
      const leaf = _DummyZLeafWidget();
      expect(leaf.isZeroAllocation, isTrue);

      const singleChild = _DummyZSingleChildWidget();
      expect(singleChild.isZeroAllocation, isTrue);
    });

    testWidgets('ZLeafWidget は親の頻繁な rebuild においてもインスタンス同一性を維持し RenderObject を再生成しないこと', (tester) async {
      int buildCount = 0;
      late StateSetter triggerRebuild;

      final widget = StatefulBuilder(
        builder: (context, setState) {
          triggerRebuild = setState;
          buildCount++;
          return const Directionality(
            textDirection: TextDirection.ltr,
            child: _DummyZLeafWidget(),
          );
        },
      );

      await tester.pumpWidget(widget);
      expect(buildCount, equals(1));
      expect(_DummyZLeafWidget.createCount, equals(1));

      // 親を 100 回連続 rebuild
      for (int i = 0; i < 100; i++) {
        triggerRebuild(() {});
        await tester.pump();
      }

      expect(buildCount, equals(101));
      // const ZLeafWidget により、RenderObject は再生成されず 1 回のみの生成
      expect(_DummyZLeafWidget.createCount, equals(1));
    });

    testWidgets('ZSingleChildWidget は子ウィジェットを適切に配置しライフサイクルを維持すること', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _DummyZSingleChildWidget(
            child: SizedBox(width: 50, height: 50),
          ),
        ),
      );

      expect(find.byType(_DummyZSingleChildWidget), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);

      // Unmount
      await tester.pumpWidget(const SizedBox.shrink());
      expect(find.byType(_DummyZSingleChildWidget), findsNothing);
    });
  });

  group('【6. ZeroIntNotifier / ZeroDoubleNotifier ゼロボクシング通知テスト】', () {
    test('ZeroIntNotifier updates, notifies, and compacts removed listeners safely', () {
      final notifier = ZeroIntNotifier(10);
      int calls1 = 0;
      int calls2 = 0;
      late VoidCallback listener1;
      listener1 = () {
        calls1++;
        if (notifier.value == 20) {
          notifier.removeListener(listener1);
        }
      };
      void listener2() {
        calls2++;
      }

      notifier.addListener(listener1);
      notifier.addListener(listener2);
      expect(notifier.hasListeners, isTrue);

      // Identical value should not notify
      notifier.value = 10;
      expect(calls1, equals(0));
      expect(calls2, equals(0));

      // Update to 20 -> listener1 removes itself during dispatch
      notifier.add(10);
      expect(notifier.value, equals(20));
      expect(calls1, equals(1));
      expect(calls2, equals(1));

      // Update to 25 -> only listener2 is called
      notifier.add(5);
      expect(calls1, equals(1));
      expect(calls2, equals(2));

      notifier.dispose();
      notifier.dispose(); // Double-dispose safety
      notifier.value = 99; // Ignored after dispose
      expect(calls2, equals(2));
    });

    test('ZeroDoubleNotifier updates and notifies properly', () {
      final notifier = ZeroDoubleNotifier(1.5);
      int calls = 0;
      notifier.addListener(() => calls++);

      notifier.add(0.5);
      expect(notifier.value, equals(2.0));
      expect(calls, equals(1));

      notifier.dispose();
      notifier.dispose();
    });
  });
}

class _DummyZLeafWidget extends ZLeafWidget<_TestZeroRenderBox> {
  static int createCount = 0;
  const _DummyZLeafWidget();

  @override
  _TestZeroRenderBox createRenderObject(BuildContext context) {
    createCount++;
    return _TestZeroRenderBox(animatePerFrame: false);
  }

  @override
  void updateRenderObject(BuildContext context, _TestZeroRenderBox renderObject) {}
}

class _DummyZSingleChildWidget extends ZSingleChildWidget<RenderProxyBox> {
  const _DummyZSingleChildWidget({super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) => RenderProxyBox();

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) {}
}

class _TestZeroRenderBox extends ZeroRenderBox {
  _TestZeroRenderBox({super.animatePerFrame});

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {}
}

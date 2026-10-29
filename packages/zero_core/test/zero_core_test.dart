import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_core/zero_core.dart';

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

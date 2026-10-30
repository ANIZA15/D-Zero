import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_chart/d_zero_chart.dart';

void main() {
  group('ZSparkline & ZeroChartController', () {
    test('controller tracks min/max/latest/average and survives double-dispose', () {
      final controller = ZeroChartController(capacity: 4);
      expect(controller.length, 0);
      expect(controller.min, 0.0);
      expect(controller.max, 0.0);

      controller.push(10.0);
      controller.push(20.0);
      controller.push(30.0);
      expect(controller.length, 3);
      expect(controller.min, 10.0);
      expect(controller.max, 30.0);
      expect(controller.latest, 30.0);
      expect(controller.average, 20.0);

      controller.pushBatch(const [40.0, 50.0]);
      expect(controller.length, 4);
      expect(controller.valueAt(0), 20.0);
      expect(controller.latest, 50.0);

      controller.clear();
      expect(controller.length, 0);

      controller.dispose();
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      controller.push(99.0);
      expect(controller.length, 0);
      expect(controller.latest, 0.0);
      expect(controller.valueAt(0), 0.0);
    });

    testWidgets('ZSparkline renders 300 ticks and unsubscribes on unmount',
        (tester) async {
      final controller = ZeroChartController(capacity: 120);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZRealtimeChart(controller: controller),
          ),
        ),
      );
      expect(controller.hasListeners, isTrue);

      for (int i = 0; i < 300; i++) {
        controller.push(100.0 + (i % 25) * 0.5);
        await tester.pump(const Duration(milliseconds: 8));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });

  group('ZCandlestickChart & ZeroCandlestickBuffer', () {
    test('SoA buffer stores OHLC candles and survives double-dispose', () {
      final buffer = ZeroCandlestickBuffer(capacity: 4);
      expect(buffer.count, 0);
      expect(buffer.minPrice, 0.0);
      expect(buffer.maxPrice, 0.0);

      buffer.addCandle(100.0, 110.0, 95.0, 105.0);
      buffer.addCandle(105.0, 115.0, 102.0, 103.0);
      expect(buffer.count, 2);
      expect(buffer.minPrice, 95.0);
      expect(buffer.maxPrice, 115.0);
      expect(buffer.openAt(0), 100.0);
      expect(buffer.closeAt(1), 103.0);

      buffer.updateLastCandle(105.0, 120.0, 101.0, 118.0);
      expect(buffer.maxPrice, 120.0);
      expect(buffer.closeAt(1), 118.0);

      buffer.clear();
      expect(buffer.count, 0);

      buffer.dispose();
      buffer.dispose();
      buffer.addCandle(100.0, 110.0, 90.0, 105.0);
      expect(buffer.count, 0);
      expect(buffer.openAt(0), 0.0);
    });

    testWidgets('ZCandlestickChart renders candles and cleans up on unmount',
        (tester) async {
      final buffer = ZeroCandlestickBuffer(capacity: 32);
      addTearDown(buffer.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZCandlestickChart(buffer: buffer),
          ),
        ),
      );
      expect(buffer.hasListeners, isTrue);

      for (int i = 0; i < 64; i++) {
        final double base = 100.0 + (i % 10);
        buffer.addCandle(base, base + 4.0, base - 3.0, base + ((i.isEven) ? 2.0 : -1.5));
        await tester.pump(const Duration(milliseconds: 8));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(buffer.hasListeners, isFalse);
    });
  });

  group('ZHeatmap & ZeroHeatmapBuffer', () {
    test('matrix buffer clamps cells and survives double-dispose', () {
      final buffer = ZeroHeatmapBuffer(rows: 4, cols: 4);
      buffer.setCell(1, 2, 0.75);
      buffer.setCell(0, 0, 2.5);
      buffer.setCell(0, 1, -1.0);
      expect(buffer.cellAt(1, 2), closeTo(0.75, 1e-5));
      expect(buffer.cellAt(0, 0), 1.0);
      expect(buffer.cellAt(0, 1), 0.0);

      buffer.clear();
      expect(buffer.cellAt(1, 2), 0.0);

      buffer.dispose();
      buffer.dispose();
      buffer.setCell(1, 2, 0.9);
      expect(buffer.cellAt(1, 2), 0.0);
      expect(buffer.length, 0);
    });

    testWidgets('ZHeatmap renders quantized palette cells and unsubscribes on unmount',
        (tester) async {
      final buffer = ZeroHeatmapBuffer(rows: 6, cols: 8);
      addTearDown(buffer.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZHeatmap(buffer: buffer),
          ),
        ),
      );
      expect(buffer.hasListeners, isTrue);

      for (int frame = 0; frame < 120; frame++) {
        buffer.setCell(frame % 6, frame % 8, (frame % 32) / 31.0);
        await tester.pump(const Duration(milliseconds: 8));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(buffer.hasListeners, isFalse);
    });
  });

  group('ZOrderBook & ZeroOrderBookController', () {
    test('SoA order book updates levels and survives double-dispose', () {
      final controller = ZeroOrderBookController(maxDepth: 5);
      controller.updateBid(0, 50000.0, 2.5);
      controller.updateAsk(0, 50001.0, 4.0);
      expect(controller.bidPriceAt(0), 50000.0);
      expect(controller.bidSizeAt(0), 2.5);
      expect(controller.askPriceAt(0), 50001.0);
      expect(controller.askSizeAt(0), 4.0);
      expect(controller.maxLevelSize, 4.0);

      controller.clear();
      expect(controller.bidSizeAt(0), 0.0);

      controller.dispose();
      controller.dispose();
      controller.updateBid(0, 50000.0, 10.0);
      expect(controller.bidPriceAt(0), 0.0);
      expect(controller.bidSizeAt(0), 0.0);
    });

    testWidgets('ZOrderBook renders L2 depth and unsubscribes on unmount',
        (tester) async {
      final controller = ZeroOrderBookController(maxDepth: 8);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZDataGrid(controller: controller),
          ),
        ),
      );
      expect(controller.hasListeners, isTrue);

      for (int tick = 0; tick < 200; tick++) {
        final int lvl = tick % 8;
        controller.updateBid(lvl, 100.0 - lvl * 0.1, (tick % 15) + 1.0);
        controller.updateAsk(lvl, 100.1 + lvl * 0.1, (tick % 12) + 1.5);
        await tester.pump(const Duration(milliseconds: 8));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });

  group('ZVirtualGrid & ZeroVirtualGridController', () {
    test('ZeroVirtualGridController stores 2D numeric matrix and survives double-dispose', () {
      final controller = ZeroVirtualGridController(rows: 100, cols: 6);
      expect(controller.length, equals(600));
      controller.setCell(10, 3, 42.75);
      controller.updateRow(20, const [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
      expect(controller.cellAt(10, 3), closeTo(42.75, 1e-4));
      expect(controller.cellAt(20, 5), closeTo(6.0, 1e-4));

      controller.clear();
      expect(controller.cellAt(10, 3), equals(0.0));

      controller.dispose();
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      controller.setCell(0, 0, 99.0);
      expect(controller.cellAt(0, 0), equals(0.0));
      expect(controller.length, equals(0));
    });

    testWidgets('ZVirtualGrid culls and renders visible cells and unsubscribes on unmount', (tester) async {
      final controller = ZeroVirtualGridController(rows: 500, cols: 8);
      addTearDown(controller.dispose);
      for (int r = 0; r < 50; r++) {
        for (int c = 0; c < 8; c++) {
          controller.setCell(r, c, (r * 10 + c) * 1.25);
        }
      }

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZTimeSeriesTable(
              controller: controller,
              size: const Size(320.0, 180.0),
            ),
          ),
        ),
      );
      expect(controller.hasListeners, isTrue);

      final renderGrid = tester.renderObject<RenderZVirtualGrid>(find.byType(ZVirtualGrid));
      expect(renderGrid.isRepaintBoundary, isTrue);

      await tester.drag(find.byType(ZVirtualGrid), const Offset(-60.0, -120.0));
      await tester.pump();
      expect(renderGrid.scrollX, greaterThan(0.0));
      expect(renderGrid.scrollY, greaterThan(0.0));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });
}

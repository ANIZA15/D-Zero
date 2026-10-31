import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_chart/d_zero_chart.dart';
import 'package:d_zero_ui/d_zero_ui.dart';

import 'package:benchmark_app/main.dart';
import 'package:benchmark_app/suite_switch_demo_view.dart';

void main() {
  testWidgets(
      'Suite comparison demo switches between D-Zero and traditional widgets with FPS & CPU usage only',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DZeroBenchmarkApp());
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // Verify FPS & CPU usage HUD and D-Zero default view
    expect(find.byType(ZFPSMonitor), findsOneWidget);
    expect(find.text('CPU使用率'), findsOneWidget);
    expect(find.text('D-Zero Suite'), findsOneWidget);
    expect(find.text('従来 (Traditional Flutter Widgets)'), findsNothing);
    expect(find.byType(ZSparkline), findsOneWidget);
    expect(find.byType(ZCandlestickChart), findsOneWidget);
    expect(find.byType(ZOrderBook), findsOneWidget);
    expect(find.byType(ZHeatmap), findsOneWidget);
    expect(find.byType(ZGauge), findsOneWidget);
    expect(find.byType(ZActivityRings), findsOneWidget);
    expect(find.byType(ZWheelPicker), findsOneWidget);

    // Switch to Traditional mode
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<SuiteRenderMode>),
        matching: find.text('従来'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('従来 (Traditional Flutter Widgets)'), findsOneWidget);
    expect(find.text('D-Zero Suite'), findsNothing);

    // Unmount and verify clean disposal
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

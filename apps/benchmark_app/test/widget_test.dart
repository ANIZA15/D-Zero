// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_particles/d_zero_particles.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_chart/d_zero_chart.dart';
import 'package:d_zero_ui/d_zero_ui.dart';

import 'package:benchmark_app/main.dart';
import 'package:benchmark_app/particles_benchmark_view.dart';
import 'package:benchmark_app/suite_switch_demo_view.dart';

void main() {
  testWidgets('Suite comparison demo switches between d-zero and traditional widgets with FPS & memory HUD', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DZeroBenchmarkApp());
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // Verify FPS & Memory HUD and pure d-zero mode default
    expect(find.byType(ZFPSMonitor), findsWidgets);
    expect(find.textContaining('Live FPS & Memory Diagnostics HUD'), findsOneWidget);
    expect(find.textContaining('ZWidget Verification'), findsOneWidget);
    expect(find.text('⚡️ d-zero Pure Suite (All Z* Widgets)'), findsOneWidget);
    expect(find.text('❌ Traditional Flutter Widgets'), findsNothing);
    expect(find.byType(ZSparkline), findsOneWidget);
    expect(find.byType(ZCandlestickChart), findsOneWidget);
    expect(find.byType(ZOrderBook), findsOneWidget);
    expect(find.byType(ZHeatmap), findsOneWidget);
    expect(find.byType(ZGauge), findsOneWidget);

    // Switch to Traditional Widgets mode
    await tester.tap(find.descendant(
      of: find.byType(SegmentedButton<SuiteRenderMode>),
      matching: find.text('❌ 通常の Widget (高負荷)'),
    ));
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('❌ Traditional Flutter Widgets'), findsOneWidget);
    expect(find.text('⚡️ d-zero Pure Suite (All Z* Widgets)'), findsNothing);

    // Switch to Side-by-Side mode
    await tester.tap(find.descendant(
      of: find.byType(SegmentedButton<SuiteRenderMode>),
      matching: find.text('⚖️ 2画面同時比較'),
    ));
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('⚡️ d-zero Pure Suite (All Z* Widgets)'), findsOneWidget);
    expect(find.text('❌ Traditional Flutter Widgets'), findsOneWidget);

    // Unmount and verify clean disposal (no leaked tickers or listeners)
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Benchmark app smoke test and narrow screen particle motion test', (WidgetTester tester) async {
    // Use realistic mobile screen dimensions (360x780 logical = 1080x2340 @ 3x)
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Build our app and trigger frames on Tab 0 while Tab 2 ZParticles is offstage in IndexedStack
    await tester.pumpWidget(const DZeroBenchmarkApp());
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // Verify header exists.
    expect(find.text('⚡️ d-zero'), findsOneWidget);

    // Switch to Particle Stress tab
    await tester.ensureVisible(find.text('Particle Stress'));
    await tester.tap(find.text('Particle Stress'));
    await tester.pump();

    // Verify Particle Stress view rendered and ZParticles actively steps physics every frame
    expect(find.text('レンダリング方式の切り替え'), findsOneWidget);
    expect(find.text('⚡️ d-zero Suite'), findsOneWidget);
    expect(find.text('❌ Traditional'), findsOneWidget);

    final renderParticles = tester.renderObject<RenderZParticles>(find.byType(ZParticles));
    final initialX = renderParticles.controller.buffer.positions[0];
    final initialY = renderParticles.controller.buffer.positions[1];

    for (int i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }

    final updatedX = renderParticles.controller.buffer.positions[0];
    final updatedY = renderParticles.controller.buffer.positions[1];
    expect(initialX != updatedX || initialY != updatedY, isTrue);

    // Switch to d-zero single view
    await tester.tap(find.descendant(
      of: find.byType(SegmentedButton<ParticleRenderMode>),
      matching: find.text('⚡️ d-zero'),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('⚡️ d-zero Suite'), findsOneWidget);
    expect(find.text('❌ Traditional'), findsNothing);

    // Switch to Traditional single view
    await tester.tap(find.descendant(
      of: find.byType(SegmentedButton<ParticleRenderMode>),
      matching: find.text('❌ 従来'),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('❌ Traditional'), findsOneWidget);
    expect(find.text('⚡️ d-zero Suite'), findsNothing);
  });
}

// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:benchmark_app/main.dart';

void main() {
  testWidgets('Benchmark app smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Build our app and trigger a frame.
    await tester.pumpWidget(const DZeroBenchmarkApp());

    // Verify header exists.
    expect(find.text('⚡️ d-zero Benchmark Suite'), findsOneWidget);

    // Switch to Particle Stress tab
    await tester.tap(find.text('Particle Stress'));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Particle Stress view rendered
    expect(find.text('レンダリング方式の切り替え'), findsOneWidget);
    expect(find.text('⚡️ d-zero Suite'), findsOneWidget);
    expect(find.text('❌ Traditional Flutter'), findsOneWidget);

    // Switch to d-zero single view
    await tester.tap(find.text('⚡️ d-zero'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('⚡️ d-zero Suite'), findsOneWidget);
    expect(find.text('❌ Traditional Flutter'), findsNothing);

    // Switch to Traditional single view
    await tester.tap(find.text('❌ 従来'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('❌ Traditional Flutter'), findsOneWidget);
    expect(find.text('⚡️ d-zero Suite'), findsNothing);
  });
}

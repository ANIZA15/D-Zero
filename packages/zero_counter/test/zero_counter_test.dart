import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_counter/zero_counter.dart';

void main() {
  testWidgets('ZeroCounter paints value changes directly without widget rebuild', (tester) async {
    final counterNotifier = ValueNotifier<int>(0);

    int rebuildCount = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            rebuildCount++;
            return Center(
              child: ZeroCounter(
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

  testWidgets('ZeroStopwatch renders and advances without widget rebuild', (tester) async {
    int rebuildCount = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            rebuildCount++;
            return const Center(
              child: ZeroStopwatch(
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
}

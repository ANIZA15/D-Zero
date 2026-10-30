import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_waveform/d_zero_waveform.dart';

void main() {
  group('ZWaveform & ZeroWaveformController', () {
    test('controller stores clamped samples and survives double-dispose', () {
      final controller = ZeroWaveformController(capacity: 8);
      expect(controller.length, 0);
      expect(controller.rms, 0.0);

      controller.pushSample(0.5);
      controller.pushSample(2.5); // clamped to 1.0
      controller.pushSample(-2.0); // clamped to -1.0
      expect(controller.length, 3);
      expect(controller.sampleAt(0), 0.5);
      expect(controller.sampleAt(1), 1.0);
      expect(controller.sampleAt(2), -1.0);
      expect(controller.latest, -1.0);
      expect(controller.rms, greaterThan(0.0));

      controller.pushSamples(const [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
      expect(controller.length, 8);

      controller.clear();
      expect(controller.length, 0);

      controller.dispose();
      controller.dispose(); // Double-dispose safe
      expect(controller.isDisposed, isTrue);
      controller.pushSample(0.9);
      expect(controller.length, 0);
      expect(controller.sampleAt(0), 0.0);
      expect(controller.latest, 0.0);
      expect(controller.rms, 0.0);
    });

    testWidgets('ZWaveform mounts, paints polyline & bars, and unsubscribes on unmount',
        (tester) async {
      final controller = ZeroWaveformController(capacity: 64);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZWaveform(
              controller: controller,
              style: ZWaveformStyle.polyline,
            ),
          ),
        ),
      );
      expect(controller.hasListeners, isTrue);

      for (int frame = 0; frame < 200; frame++) {
        controller.pushSample(math.sin(frame * 0.1));
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZAudioVisualizer(
              controller: controller,
              style: ZWaveformStyle.bars,
              backgroundColor: const Color(0xFF101010),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });

  group('ZSpectrumAnalyzer & ZeroSpectrumController', () {
    test('controller updates bins, decays peaks, and survives double-dispose', () {
      final controller = ZeroSpectrumController(binCount: 8, peakDecayPerStep: 0.1);
      controller.updateBins(const [0.8, 1.5, -0.2, 0.4]);
      expect(controller.binAt(0), closeTo(0.8, 1e-5));
      expect(controller.binAt(1), closeTo(1.0, 1e-5));
      expect(controller.binAt(2), closeTo(0.0, 1e-5));
      expect(controller.peakAt(0), closeTo(0.8, 1e-5));

      controller.updateBins(const [0.2, 0.2, 0.0, 0.0]);
      expect(controller.binAt(0), closeTo(0.2, 1e-5));
      expect(controller.peakAt(0), closeTo(0.7, 1e-5));

      controller.decayStep();
      expect(controller.peakAt(0), lessThan(0.7));

      controller.clear();
      expect(controller.binAt(0), 0.0);

      controller.dispose();
      controller.dispose();
      expect(controller.isDisposed, isTrue);
      controller.updateBins(const [1.0, 1.0]);
      expect(controller.binAt(0), 0.0);
      expect(controller.peakAt(0), 0.0);
    });

    testWidgets('ZSpectrumAnalyzer renders 300 frames and cleans up on unmount',
        (tester) async {
      final controller = ZeroSpectrumController(binCount: 16);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZSpectrumAnalyzer(controller: controller),
          ),
        ),
      );
      expect(controller.hasListeners, isTrue);

      final bins = List<double>.filled(16, 0.0);
      for (int frame = 0; frame < 300; frame++) {
        _fillSyntheticBins(bins, frame);
        controller.updateBins(bins);
        await tester.pump(const Duration(milliseconds: 8));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });

  group('ZAudioMeter & ZeroAudioMeterController', () {
    test('controller tracks RMS, peak hold, dBFS, clip flag, and double-dispose', () {
      final controller = ZeroAudioMeterController(peakDecayPerUpdate: 0.05);
      expect(controller.peakDb, -60.0);

      controller.updateLevels(leftRms: 0.5, rightRms: 0.8);
      expect(controller.leftRms, closeTo(0.5, 1e-5));
      expect(controller.rightRms, closeTo(0.8, 1e-5));
      expect(controller.isClipping, isFalse);
      expect(controller.peakDb, greaterThan(-60.0));

      controller.updateLevels(leftRms: 1.0, rightRms: 0.95);
      expect(controller.isClipping, isTrue);
      controller.resetClip();
      expect(controller.isClipping, isFalse);

      controller.clear();
      expect(controller.leftRms, 0.0);

      controller.dispose();
      controller.dispose();
      controller.updateLevels(leftRms: 1.0, rightRms: 1.0);
      expect(controller.leftRms, 0.0);
      expect(controller.isClipping, isFalse);
      expect(controller.peakDb, -60.0);
    });

    testWidgets('ZAudioMeter renders stereo/mono + dB readout across 500 frames',
        (tester) async {
      final controller = ZeroAudioMeterController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZVUMeter(controller: controller, stereo: true),
          ),
        ),
      );
      expect(controller.hasListeners, isTrue);

      for (int frame = 0; frame < 500; frame++) {
        final double level = (frame % 100) / 100.0;
        controller.updateLevels(leftRms: level, rightRms: level * 0.9);
        await tester.pump(const Duration(milliseconds: 8));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasListeners, isFalse);
    });
  });
}

void _fillSyntheticBins(List<double> bins, int frame) {
  for (int i = 0; i < bins.length; i++) {
    bins[i] = ((frame + i * 7) % 100) / 100.0;
  }
}

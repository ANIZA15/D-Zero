import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_sensor/d_zero_sensor.dart';

void main() {
  runApp(const DZeroSensorBenchmarkApp());
}

enum SensorBenchMode { dZero, traditional }

class DZeroSensorBenchmarkApp extends StatelessWidget {
  const DZeroSensorBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_sensor Sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00FF88),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const SensorBenchmarkScreen(),
    );
  }
}

class SensorBenchmarkScreen extends StatefulWidget {
  const SensorBenchmarkScreen({super.key});

  @override
  State<SensorBenchmarkScreen> createState() => _SensorBenchmarkScreenState();
}

class _SensorBenchmarkScreenState extends State<SensorBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  static const int _boxCount = 12;

  SensorBenchMode _mode = SensorBenchMode.dZero;
  int _schedulerSlot = -1;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(3.9);

  late final ZeroDetectionController _detectionCtrl;
  final ZeroDoubleNotifier _headingDeg = ZeroDoubleNotifier(45.0);
  late final ZeroTiltController _tiltCtrl;
  late final ZeroQRCodeController _qrCtrl;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _detectionCtrl = ZeroDetectionController(capacity: 16);
    _tiltCtrl = ZeroTiltController(pitch: 2.0, roll: -1.5);
    _qrCtrl = ZeroQRCodeController();
    _stepDetections();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _tickCount++;
    _phase += 0.06;
    _headingDeg.value = (_headingDeg.value + 0.8) % 360.0;
    _tiltCtrl.updateTilt(
      math.sin(_phase) * 14.0,
      math.cos(_phase * 0.8) * 14.0,
    );
    if (_tickCount % 60 == 0) {
      _qrCtrl.updateToken(100000 + _tickCount);
    }
    _stepDetections();

    if (_mode == SensorBenchMode.traditional) {
      setState(() {});
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _stepDetections() {
    for (int i = 0; i < _boxCount; i++) {
      final double col = (i % 4) * 62.0 + 16.0;
      final double row = (i ~/ 4) * 44.0 + 14.0;
      final double dx = math.sin(_phase + i * 0.5) * 6.0;
      final double dy = math.cos(_phase + i * 0.4) * 4.0;
      final double conf = 85.0 + (i % 14);
      _detectionCtrl.setDetection(
        i,
        col + dx,
        row + dy,
        col + dx + 48.0,
        row + dy + 32.0,
        conf,
      );
    }
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == SensorBenchMode.dZero ? 145.0 : 1780.0;
    final double pct =
        ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.2, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _detectionCtrl.dispose();
    _headingDeg.dispose();
    _tiltCtrl.dispose();
    _qrCtrl.dispose();
    _cpuPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_sensor'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            SegmentedButton<SensorBenchMode>(
              segments: const [
                ButtonSegment(
                  value: SensorBenchMode.dZero,
                  label: Text('D-Zero'),
                ),
                ButtonSegment(
                  value: SensorBenchMode.traditional,
                  label: Text('従来'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == SensorBenchMode.dZero
                ? _buildDZeroSensors()
                : _buildTradSensors(),
          ],
        ),
      ),
    );
  }

  Widget _buildHud() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101624),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const ZFPSMonitor(size: Size(148.0, 44.0)),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CPU使用率',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              SizedBox(
                width: 72,
                height: 22,
                child: ZPriceTicker(
                  valueListenable: _cpuPct,
                  currencyGlyph: ZeroNumberPainter.glyphPercent,
                  fractionDigits: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.amberAccent,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDZeroSensors() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'D-Zero (ZBarcodeScanner + ZCompass + ZLeveler + ZQRGenerator)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ZBarcodeScanner(
                controller: _detectionCtrl,
                size: const Size(260, 150),
              ),
              ZCompass(
                headingListenable: _headingDeg,
                size: const Size(120, 120),
              ),
              ZLeveler(controller: _tiltCtrl, size: const Size(120, 120)),
              ZQRGenerator(controller: _qrCtrl, size: const Size(120, 120)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradSensors() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A141E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '従来 (Stack + Positioned + Text)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 260,
                height: 150,
                color: Colors.black54,
                child: Stack(
                  children: [
                    for (int i = 0; i < _boxCount; i++)
                      Positioned(
                        left: _detectionCtrl.boxes[i * 5],
                        top: _detectionCtrl.boxes[i * 5 + 1],
                        child: Container(
                          width: 48,
                          height: 32,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(
                            '${_detectionCtrl.boxes[i * 5 + 4].toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                'Heading: ${_headingDeg.value.toStringAsFixed(1)}°\n'
                'Pitch: ${_tiltCtrl.pitch.toStringAsFixed(1)}°\n'
                'Roll: ${_tiltCtrl.roll.toStringAsFixed(1)}°',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

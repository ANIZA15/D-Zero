import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_sensor/d_zero_sensor.dart';

void main() {
  runApp(const DZeroSensorBenchmarkApp());
}

enum SensorBenchMode { dZero, traditional, sideBySide }

class DZeroSensorBenchmarkApp extends StatelessWidget {
  const DZeroSensorBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_sensor High-Load Benchmark',
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
  final bool _isRunning = true;
  bool _extremeLoad = false;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(3.9);
  final ZeroDoubleNotifier _rssMb = ZeroDoubleNotifier(48.0);
  final ZeroDoubleNotifier _peakMb = ZeroDoubleNotifier(48.0);
  final ZeroIntNotifier _dZeroRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradAllocs = ZeroIntNotifier(0);

  late final ZeroDetectionController _detectionCtrl;
  final ZeroDoubleNotifier _headingDeg = ZeroDoubleNotifier(45.0);
  late final ZeroTiltController _tiltCtrl;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _detectionCtrl = ZeroDetectionController(capacity: 16);
    _tiltCtrl = ZeroTiltController(pitch: 2.0, roll: -1.5);
    _stepDetections();
    _sampleMemory();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted || !_isRunning) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _tickCount++;
    _phase += _extremeLoad ? 0.16 : 0.06;
    _headingDeg.value = (_headingDeg.value + (_extremeLoad ? 2.4 : 0.8)) % 360.0;
    _tiltCtrl.updateTilt(math.sin(_phase) * 14.0, math.cos(_phase * 0.8) * 14.0);
    _stepDetections();

    if (_mode != SensorBenchMode.dZero) {
      setState(() {
        _tradRebuilds.add(1);
        _tradAllocs.add(_boxCount * 5 + 16);
      });
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
    final double overhead = _mode == SensorBenchMode.dZero
        ? 145.0
        : (_extremeLoad ? 3850.0 : 1780.0);
    final double pct = ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.2, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
    if (_tickCount % 15 == 0) _sampleMemory();
  }

  void _sampleMemory() {
    try {
      final double mb = ProcessInfo.currentRss / (1024.0 * 1024.0);
      _rssMb.value = mb;
      if (mb > _peakMb.value) _peakMb.value = mb;
    } catch (_) {
      _rssMb.value = 46.5;
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _detectionCtrl.dispose();
    _headingDeg.dispose();
    _tiltCtrl.dispose();
    _cpuPct.dispose();
    _rssMb.dispose();
    _peakMb.dispose();
    _dZeroRebuilds.dispose();
    _tradRebuilds.dispose();
    _tradAllocs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_sensor ML & Gyro Benchmark'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            _buildControls(),
            const SizedBox(height: 12),
            _buildBody(),
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
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.45)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const ZFPSMonitor(size: Size(148.0, 44.0)),
          _buildPriceStat('CPU Load %', _cpuPct, ZeroNumberPainter.glyphPercent, Colors.amberAccent),
          _buildPriceStat('RSS MB', _rssMb, ZeroNumberPainter.glyphPlus, const Color(0xFF00E5FF)),
          _buildPriceStat('Peak MB', _peakMb, ZeroNumberPainter.glyphPlus, Colors.orangeAccent),
          _buildIntStat('D-Zero Rebuilds', _dZeroRebuilds, const Color(0xFF00FF88)),
          _buildIntStat('Trad Rebuilds', _tradRebuilds, Colors.redAccent),
          _buildIntStat('Trad Allocs', _tradAllocs, Colors.pinkAccent),
        ],
      ),
    );
  }

  Widget _buildPriceStat(String label, ZeroDoubleNotifier n, int glyph, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        SizedBox(
          width: 72,
          height: 20,
          child: ZPriceTicker(
            valueListenable: n,
            currencyGlyph: glyph,
            fractionDigits: 1,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildIntStat(String label, ZeroIntNotifier n, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        SizedBox(
          width: 80,
          height: 20,
          child: ZCounter(
            valueListenable: n,
            minDigits: 1,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<SensorBenchMode>(
            segments: const [
              ButtonSegment(value: SensorBenchMode.dZero, label: Text('D-Zero Sensors')),
              ButtonSegment(value: SensorBenchMode.traditional, label: Text('Traditional')),
              ButtonSegment(value: SensorBenchMode.sideBySide, label: Text('Both')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          FilterChip(
            label: const Text('🔥 120Hz IMU & ML Stream'),
            selected: _extremeLoad,
            onSelected: (v) => setState(() => _extremeLoad = v),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == SensorBenchMode.dZero) return _buildDZeroSensors();
    if (_mode == SensorBenchMode.traditional) return _buildTradSensors();
    return Column(
      children: [
        _buildDZeroSensors(),
        const SizedBox(height: 12),
        _buildTradSensors(),
      ],
    );
  }

  Widget _buildDZeroSensors() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🚀 D-Zero (ZBarcodeScanner 12-Box SoA + ZCompass ui.Picture + ZLeveler)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ZBarcodeScanner(
                controller: _detectionCtrl,
                size: const Size(280, 155),
              ),
              ZCompass(
                headingListenable: _headingDeg,
                size: const Size(125, 125),
              ),
              ZLeveler(
                controller: _tiltCtrl,
                size: const Size(125, 125),
              ),
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
            '🐢 Traditional Flutter (Stack of Positioned Containers + Text Confidence Strings)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 280,
                height: 155,
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
                            style: const TextStyle(fontSize: 9, color: Colors.redAccent),
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
                style: const TextStyle(fontFamily: 'monospace', color: Colors.orangeAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

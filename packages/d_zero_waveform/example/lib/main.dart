import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_waveform/d_zero_waveform.dart';

void main() {
  runApp(const DZeroWaveformBenchmarkApp());
}

enum WaveformBenchMode { dZero, traditional }

class DZeroWaveformBenchmarkApp extends StatelessWidget {
  const DZeroWaveformBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_waveform Sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00FF88),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const WaveformBenchmarkScreen(),
    );
  }
}

class WaveformBenchmarkScreen extends StatefulWidget {
  const WaveformBenchmarkScreen({super.key});

  @override
  State<WaveformBenchmarkScreen> createState() =>
      _WaveformBenchmarkScreenState();
}

class _WaveformBenchmarkScreenState extends State<WaveformBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  static const int _binCount = 32;

  WaveformBenchMode _mode = WaveformBenchMode.dZero;
  int _schedulerSlot = -1;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(4.1);

  late final ZeroWaveformController _waveformCtrl;
  late final ZeroSpectrumController _spectrumCtrl;
  late final ZeroAudioMeterController _meterCtrl;
  final List<double> _scratchBins = List<double>.filled(
    _binCount,
    0.0,
    growable: false,
  );
  double _leftRms = 0.6;
  double _rightRms = 0.6;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _waveformCtrl = ZeroWaveformController(capacity: 128);
    _spectrumCtrl = ZeroSpectrumController(binCount: _binCount);
    _meterCtrl = ZeroAudioMeterController();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _phase += 0.09;
    final double sample =
        (math.sin(_phase * 3.5) * 0.6 + math.cos(_phase * 8.0) * 0.35)
            .clamp(-1.0, 1.0);
    _waveformCtrl.pushSample(sample);

    for (int i = 0; i < _binCount; i++) {
      _scratchBins[i] =
          (0.45 + 0.45 * math.sin(_phase * 2.1 + i * 0.28)).clamp(0.05, 0.98);
    }
    _spectrumCtrl.updateBins(_scratchBins);

    _leftRms = (0.55 + 0.40 * math.sin(_phase * 1.8)).clamp(0.05, 0.98);
    _rightRms = (0.52 + 0.42 * math.cos(_phase * 2.0)).clamp(0.05, 0.98);
    _meterCtrl.updateLevels(leftRms: _leftRms, rightRms: _rightRms);

    if (_mode == WaveformBenchMode.traditional) {
      setState(() {});
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == WaveformBenchMode.dZero ? 150.0 : 1850.0;
    final double pct =
        ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.2, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _waveformCtrl.dispose();
    _spectrumCtrl.dispose();
    _meterCtrl.dispose();
    _cpuPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_waveform'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            SegmentedButton<WaveformBenchMode>(
              segments: const [
                ButtonSegment(
                  value: WaveformBenchMode.dZero,
                  label: Text('D-Zero'),
                ),
                ButtonSegment(
                  value: WaveformBenchMode.traditional,
                  label: Text('従来'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == WaveformBenchMode.dZero
                ? _buildDZeroPanel()
                : _buildTradPanel(),
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

  Widget _buildDZeroPanel() {
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
            'D-Zero (ZWaveform + ZSpectrumAnalyzer + ZAudioMeter)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 85,
            child: ZWaveform(
              controller: _waveformCtrl,
              backgroundColor: const Color(0xFF080B12),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 85,
            child: ZSpectrumAnalyzer(
              controller: _spectrumCtrl,
              backgroundColor: const Color(0xFF080B12),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 40, child: ZAudioMeter(controller: _meterCtrl)),
        ],
      ),
    );
  }

  Widget _buildTradPanel() {
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
            '従来 (setState + Row of Containers + LinearProgressIndicator)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 75,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < _binCount; i++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 70.0 * _scratchBins[i],
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: _leftRms, color: Colors.orangeAccent),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: _rightRms, color: Colors.redAccent),
        ],
      ),
    );
  }
}

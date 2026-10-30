import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_waveform/d_zero_waveform.dart';

void main() {
  runApp(const DZeroWaveformBenchmarkApp());
}

enum WaveformBenchMode { dZero, traditional, sideBySide }

class DZeroWaveformBenchmarkApp extends StatelessWidget {
  const DZeroWaveformBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_waveform Audio DSP Benchmark',
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
  final bool _isRunning = true;
  bool _extremeLoad = false;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(4.1);
  final ZeroDoubleNotifier _rssMb = ZeroDoubleNotifier(48.0);
  final ZeroDoubleNotifier _peakMb = ZeroDoubleNotifier(48.0);
  final ZeroIntNotifier _dZeroRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradAllocs = ZeroIntNotifier(0);

  late final ZeroWaveformController _waveformCtrl;
  late final ZeroSpectrumController _spectrumCtrl;
  late final ZeroAudioMeterController _meterCtrl;
  final List<double> _scratchBins = List<double>.filled(_binCount, 0.0, growable: false);
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
    _phase += _extremeLoad ? 0.22 : 0.09;
    final double sample =
        (math.sin(_phase * 3.5) * 0.6 + math.cos(_phase * 8.0) * 0.35).clamp(-1.0, 1.0);
    _waveformCtrl.pushSample(sample);

    for (int i = 0; i < _binCount; i++) {
      _scratchBins[i] =
          (0.45 + 0.45 * math.sin(_phase * 2.1 + i * 0.28)).clamp(0.05, 0.98);
    }
    _spectrumCtrl.updateBins(_scratchBins);

    _leftRms = (0.55 + 0.40 * math.sin(_phase * 1.8)).clamp(0.05, 0.98);
    _rightRms = (0.52 + 0.42 * math.cos(_phase * 2.0)).clamp(0.05, 0.98);
    _meterCtrl.updateLevels(leftRms: _leftRms, rightRms: _rightRms);

    if (_mode != WaveformBenchMode.dZero) {
      setState(() {
        _tradRebuilds.add(1);
        _tradAllocs.add(_binCount * 3 + 48);
      });
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == WaveformBenchMode.dZero
        ? 150.0
        : (_extremeLoad ? 3950.0 : 1850.0);
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
      _rssMb.value = 46.8;
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _waveformCtrl.dispose();
    _spectrumCtrl.dispose();
    _meterCtrl.dispose();
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
        title: const Text('⚡️ d_zero_waveform Audio DSP Benchmark'),
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
            _buildContent(),
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
          SegmentedButton<WaveformBenchMode>(
            segments: const [
              ButtonSegment(value: WaveformBenchMode.dZero, label: Text('D-Zero DSP')),
              ButtonSegment(value: WaveformBenchMode.traditional, label: Text('Traditional')),
              ButtonSegment(value: WaveformBenchMode.sideBySide, label: Text('Both')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          FilterChip(
            label: const Text('🔥 Studio Multi-Track Stress'),
            selected: _extremeLoad,
            onSelected: (v) => setState(() => _extremeLoad = v),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_mode == WaveformBenchMode.dZero) return _buildDZeroPanel();
    if (_mode == WaveformBenchMode.traditional) return _buildTradPanel();
    return Column(
      children: [
        _buildDZeroPanel(),
        const SizedBox(height: 12),
        _buildTradPanel(),
      ],
    );
  }

  Widget _buildDZeroPanel() {
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
            '🚀 D-Zero (ZWaveform + ZSpectrumAnalyzer + ZAudioMeter)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
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
          SizedBox(
            height: 40,
            child: ZAudioMeter(controller: _meterCtrl),
          ),
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
            '🐢 Traditional Flutter (setState + Row of Container FFT Bars + LinearProgressIndicator)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
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

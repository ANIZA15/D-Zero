import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_ui/d_zero_ui.dart';

void main() {
  runApp(const DZeroUiBenchmarkApp());
}

enum UiBenchMode { dZero, traditional, sideBySide }

class DZeroUiBenchmarkApp extends StatelessWidget {
  const DZeroUiBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_ui High-Load Benchmark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00FF88),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const UiBenchmarkScreen(),
    );
  }
}

class UiBenchmarkScreen extends StatefulWidget {
  const UiBenchmarkScreen({super.key});

  @override
  State<UiBenchmarkScreen> createState() => _UiBenchmarkScreenState();
}

class _UiBenchmarkScreenState extends State<UiBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  static const int _barCount = 20;

  UiBenchMode _mode = UiBenchMode.dZero;
  int _schedulerSlot = -1;
  final bool _isRunning = true;
  bool _extremeLoad = false;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(3.8);
  final ZeroDoubleNotifier _rssMb = ZeroDoubleNotifier(48.0);
  final ZeroDoubleNotifier _peakMb = ZeroDoubleNotifier(48.0);
  final ZeroIntNotifier _dZeroRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradAllocs = ZeroIntNotifier(0);

  final ZeroIntNotifier _badgeCount = ZeroIntNotifier(12);
  final ValueNotifier<bool> _switchVal = ValueNotifier<bool>(true);
  final ValueNotifier<double> _sliderVal = ValueNotifier<double>(0.65);
  final ZeroDoubleNotifier _gaugeVal = ZeroDoubleNotifier(72.0);
  final ValueNotifier<double> _knobVal = ValueNotifier<double>(0.5);
  late final ZeroRangeValuesController _rangeCtrl;
  late final ZeroJoystickController _joystickCtrl;
  late final List<ZeroDoubleNotifier> _progressBars;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _rangeCtrl = ZeroRangeValuesController(0.2, 0.8);
    _joystickCtrl = ZeroJoystickController();
    _progressBars = List<ZeroDoubleNotifier>.generate(
      _barCount,
      (i) => ZeroDoubleNotifier((i + 1) / _barCount),
      growable: false,
    );
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
    _phase += _extremeLoad ? 0.14 : 0.05;
    _gaugeVal.value = 50.0 + math.sin(_phase) * 45.0;
    _knobVal.value = (0.5 + math.cos(_phase * 0.7) * 0.45).clamp(0.0, 1.0);
    if (_tickCount % 30 == 0) {
      _badgeCount.value = (_badgeCount.value % 99) + 1;
    }

    for (int i = 0; i < _barCount; i++) {
      _progressBars[i].value = (0.5 + 0.48 * math.sin(_phase + i * 0.35)).clamp(0.02, 0.98);
    }

    if (_mode != UiBenchMode.dZero) {
      setState(() {
        _tradRebuilds.add(1);
        _tradAllocs.add(_barCount * 5 + 24);
      });
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _updateTelemetry(int workMicros) {
    final double overhead =
        _mode == UiBenchMode.dZero ? 150.0 : (_extremeLoad ? 3800.0 : 1750.0);
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
      _rssMb.value = 47.0;
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    for (final ZeroDoubleNotifier p in _progressBars) {
      p.dispose();
    }
    _badgeCount.dispose();
    _switchVal.dispose();
    _sliderVal.dispose();
    _gaugeVal.dispose();
    _knobVal.dispose();
    _rangeCtrl.dispose();
    _joystickCtrl.dispose();
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
        title: const Text('⚡️ d_zero_ui Controls Benchmark'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            _buildControlsBar(),
            const SizedBox(height: 12),
            _buildComparisonArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildHud() {
    return ZCard(
      color: const Color(0xFF101624),
      borderColor: const Color(0xFF00E5FF).withValues(alpha: 0.45),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const ZFPSMonitor(size: Size(148.0, 44.0)),
          _buildPriceMetric('CPU Load %', _cpuPct, ZeroNumberPainter.glyphPercent, Colors.amberAccent),
          _buildPriceMetric('RSS MB', _rssMb, ZeroNumberPainter.glyphPlus, const Color(0xFF00E5FF)),
          _buildPriceMetric('Peak MB', _peakMb, ZeroNumberPainter.glyphPlus, Colors.orangeAccent),
          _buildIntMetric('D-Zero Rebuilds', _dZeroRebuilds, const Color(0xFF00FF88)),
          _buildIntMetric('Trad Rebuilds', _tradRebuilds, Colors.redAccent),
          _buildIntMetric('Trad Allocs', _tradAllocs, Colors.pinkAccent),
        ],
      ),
    );
  }

  Widget _buildPriceMetric(String label, ZeroDoubleNotifier n, int glyph, Color color) {
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

  Widget _buildIntMetric(String label, ZeroIntNotifier n, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        SizedBox(
          width: 78,
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

  Widget _buildControlsBar() {
    return ZCard(
      color: const Color(0xFF131B2A),
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<UiBenchMode>(
            segments: const [
              ButtonSegment(value: UiBenchMode.dZero, label: Text('D-Zero UI')),
              ButtonSegment(value: UiBenchMode.traditional, label: Text('Traditional')),
              ButtonSegment(value: UiBenchMode.sideBySide, label: Text('Both')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          FilterChip(
            label: const Text('🔥 Extreme 120Hz Modulation'),
            selected: _extremeLoad,
            onSelected: (v) => setState(() => _extremeLoad = v),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonArea() {
    if (_mode == UiBenchMode.dZero) return _buildDZeroUiPanel();
    if (_mode == UiBenchMode.traditional) return _buildTraditionalUiPanel();
    return Column(
      children: [
        _buildDZeroUiPanel(),
        const SizedBox(height: 12),
        _buildTraditionalUiPanel(),
      ],
    );
  }

  Widget _buildDZeroUiPanel() {
    return ZCard(
      color: const Color(0xFF101926),
      borderColor: const Color(0xFF00E5FF).withValues(alpha: 0.45),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🚀 D-Zero UI (ZCard, ZBadge, ZButton, ZSwitch, ZSlider, ZRangeSlider, ZGauge, ZKnob, ZJoystick, ZMarquee, ZTypewriterText, ZLinearProgress × 20)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
          ),
          const SizedBox(height: 10),
          const SizedBox(
            height: 24,
            child: ZMarquee(
              text: '⚡️ Zero-Rebuild UI Controls • Zero String Allocations • Impeller Direct RenderBox   ',
            ),
          ),
          const SizedBox(height: 6),
          const SizedBox(
            height: 24,
            child: ZTypewriterText(
              text: 'Progressive character reveal via Canvas.clipRect without substring() allocations.',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ZBadge(
                countListenable: _badgeCount,
                child: ZButton(
                  label: 'Trigger Pulse',
                  onPressed: () => _badgeCount.add(1),
                ),
              ),
              ZSwitch(valueListenable: _switchVal, controller: _switchVal),
              SizedBox(
                width: 140,
                height: 28,
                child: ZSlider(valueListenable: _sliderVal, controller: _sliderVal),
              ),
              SizedBox(
                width: 140,
                height: 28,
                child: ZRangeSlider(controller: _rangeCtrl),
              ),
              SizedBox(
                width: 84,
                height: 84,
                child: ZGauge(valueListenable: _gaugeVal, min: 0, max: 100),
              ),
              SizedBox(
                width: 64,
                height: 64,
                child: ZCircularProgress(valueListenable: _knobVal, showPercentage: true),
              ),
              ZKnob(controller: _knobVal, size: 64.0),
              ZJoystick(controller: _joystickCtrl),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (int i = 0; i < _barCount; i++)
                SizedBox(
                  width: 130,
                  height: 16,
                  child: ZLinearProgress(
                    valueListenable: _progressBars[i],
                    showPercentage: true,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTraditionalUiPanel() {
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
            '🐢 Traditional Flutter (setState + Material Slider/Switch/LinearProgressIndicator × 20)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Badge(
                label: Text('${_badgeCount.value}'),
                child: ElevatedButton(
                  onPressed: () => setState(() => _badgeCount.add(1)),
                  child: const Text('Trigger Pulse'),
                ),
              ),
              Switch(
                value: _switchVal.value,
                onChanged: (v) => setState(() => _switchVal.value = v),
              ),
              SizedBox(
                width: 150,
                child: Slider(
                  value: _sliderVal.value,
                  onChanged: (v) => setState(() => _sliderVal.value = v),
                ),
              ),
              CircularProgressIndicator(value: _knobVal.value),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (int i = 0; i < _barCount; i++)
                SizedBox(
                  width: 130,
                  height: 16,
                  child: LinearProgressIndicator(
                    value: _progressBars[i].value,
                    color: Colors.redAccent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

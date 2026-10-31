import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_ui/d_zero_ui.dart';

void main() {
  runApp(const DZeroUiBenchmarkApp());
}

enum UiBenchMode { dZero, traditional }

class DZeroUiBenchmarkApp extends StatelessWidget {
  const DZeroUiBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_ui Sample',
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
  static const int _barCount = 12;

  UiBenchMode _mode = UiBenchMode.dZero;
  int _schedulerSlot = -1;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(3.8);

  final ZeroIntNotifier _badgeCount = ZeroIntNotifier(12);
  final ValueNotifier<bool> _switchVal = ValueNotifier<bool>(true);
  final ValueNotifier<double> _sliderVal = ValueNotifier<double>(0.65);
  final ZeroDoubleNotifier _gaugeVal = ZeroDoubleNotifier(72.0);
  final ValueNotifier<double> _knobVal = ValueNotifier<double>(0.5);
  final ZeroDoubleNotifier _tabPos = ZeroDoubleNotifier(0.0);
  final ZeroDoubleNotifier _ratingVal = ZeroDoubleNotifier(4.5);
  late final ZeroRangeValuesController _rangeCtrl;
  late final ZeroJoystickController _joystickCtrl;
  late final ZeroWheelPickerController _wheelCtrl;
  late final ZeroNumberPadController _numPadCtrl;
  late final ZeroStoryProgressController _storyCtrl;
  late final ZeroTokenStreamController _tokenCtrl;
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
    _wheelCtrl = ZeroWheelPickerController(initialValue: 24);
    _numPadCtrl = ZeroNumberPadController(initialValue: 4820);
    _storyCtrl = ZeroStoryProgressController(segmentCount: 5);
    _tokenCtrl = ZeroTokenStreamController()
      ..appendToken('# D-Zero Token Stream\n> 0 String allocations\n');
    _progressBars = List<ZeroDoubleNotifier>.generate(
      _barCount,
      (i) => ZeroDoubleNotifier((i + 1) / _barCount),
      growable: false,
    );
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _tickCount++;
    _phase += 0.05;
    _gaugeVal.value = 50.0 + math.sin(_phase) * 45.0;
    _knobVal.value = (0.5 + math.cos(_phase * 0.7) * 0.45).clamp(0.0, 1.0);
    _tabPos.value = (1.0 + math.sin(_phase * 0.6)).clamp(0.0, 2.0);
    _storyCtrl.advance(0.008);
    if (_tickCount % 30 == 0) {
      _badgeCount.value = (_badgeCount.value % 99) + 1;
      _tokenCtrl.appendToken('tok ');
    }

    for (int i = 0; i < _barCount; i++) {
      _progressBars[i].value =
          (0.5 + 0.48 * math.sin(_phase + i * 0.35)).clamp(0.02, 0.98);
    }

    if (_mode == UiBenchMode.traditional) {
      setState(() {});
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == UiBenchMode.dZero ? 150.0 : 1750.0;
    final double pct =
        ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.2, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
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
    _tabPos.dispose();
    _ratingVal.dispose();
    _rangeCtrl.dispose();
    _joystickCtrl.dispose();
    _wheelCtrl.dispose();
    _numPadCtrl.dispose();
    _storyCtrl.dispose();
    _tokenCtrl.dispose();
    _cpuPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_ui'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            SegmentedButton<UiBenchMode>(
              segments: const [
                ButtonSegment(value: UiBenchMode.dZero, label: Text('D-Zero')),
                ButtonSegment(
                  value: UiBenchMode.traditional,
                  label: Text('従来'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == UiBenchMode.dZero
                ? _buildDZeroUiPanel()
                : _buildTraditionalUiPanel(),
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

  Widget _buildDZeroUiPanel() {
    return ZCard(
      color: const Color(0xFF101926),
      borderColor: const Color(0xFF00E5FF).withValues(alpha: 0.45),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'D-Zero UI Suite',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(height: 8),
          ZStoryProgressBar(controller: _storyCtrl),
          const SizedBox(height: 8),
          ZSegmentedControl(
            segments: const ['Home', 'Feed', 'Live'],
            positionListenable: _tabPos,
          ),
          const SizedBox(height: 8),
          ZPageIndicator(count: 5, pageListenable: _tabPos),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ZWheelPicker(controller: _wheelCtrl),
              ZNumberPad(controller: _numPadCtrl),
              ZStreamingMarkdown(controller: _tokenCtrl),
              ZRatingBar(ratingListenable: _ratingVal),
              ZPullToRefresh(
                pullProgressListenable: _knobVal,
                isRefreshing: true,
              ),
              ZBadge(
                countListenable: _badgeCount,
                child: ZButton(
                  label: 'Pulse',
                  onPressed: () => _badgeCount.add(1),
                ),
              ),
              ZSwitch(valueListenable: _switchVal, controller: _switchVal),
              SizedBox(
                width: 140,
                height: 28,
                child: ZSlider(
                  valueListenable: _sliderVal,
                  controller: _sliderVal,
                ),
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
            '従来 (setState + Material Widgets)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
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
                  child: const Text('Pulse'),
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

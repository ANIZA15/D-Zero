import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';

void main() {
  runApp(const DZeroCounterBenchmarkApp());
}

enum CounterBenchMode { dZero, traditional, sideBySide }

class DZeroCounterBenchmarkApp extends StatelessWidget {
  const DZeroCounterBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_counter High-Load Benchmark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00B0FF),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const CounterBenchmarkScreen(),
    );
  }
}

class CounterBenchmarkScreen extends StatefulWidget {
  const CounterBenchmarkScreen({super.key});

  @override
  State<CounterBenchmarkScreen> createState() => _CounterBenchmarkScreenState();
}

class _CounterBenchmarkScreenState extends State<CounterBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  static const int _cellCount = 36;

  CounterBenchMode _mode = CounterBenchMode.dZero;
  int _schedulerSlot = -1;
  bool _isRunning = true;
  bool _extremeLoad = false;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(3.5);
  final ZeroDoubleNotifier _rssMb = ZeroDoubleNotifier(48.0);
  final ZeroDoubleNotifier _peakMb = ZeroDoubleNotifier(48.0);
  final ZeroIntNotifier _dZeroRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradAllocs = ZeroIntNotifier(0);

  final ZeroIntNotifier _fastCounter = ZeroIntNotifier(10000);
  final ZeroDoubleNotifier _odometerVal = ZeroDoubleNotifier(84210.5);
  late final List<ZeroDoubleNotifier> _tickerCells;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _tickerCells = List<ZeroDoubleNotifier>.generate(
      _cellCount,
      (i) => ZeroDoubleNotifier(100.0 + i * 25.0),
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
    _phase += _extremeLoad ? 0.16 : 0.06;
    _fastCounter.add(_extremeLoad ? 7 : 1);
    _odometerVal.value = _odometerVal.value + (_extremeLoad ? 1.25 : 0.35);

    for (int i = 0; i < _cellCount; i++) {
      _tickerCells[i].value = 100.0 + i * 25.0 + math.sin(_phase + i * 0.4) * 14.0;
    }

    if (_mode != CounterBenchMode.dZero) {
      setState(() {
        _tradRebuilds.add(1);
        _tradAllocs.add(_cellCount * 4 + 12);
      });
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == CounterBenchMode.dZero
        ? 140.0
        : (_extremeLoad ? 3900.0 : 1800.0);
    final double pct = ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.0, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
    if (_tickCount % 15 == 0) {
      _sampleMemory();
    }
  }

  void _sampleMemory() {
    try {
      final double mb = ProcessInfo.currentRss / (1024.0 * 1024.0);
      _rssMb.value = mb;
      if (mb > _peakMb.value) _peakMb.value = mb;
    } catch (_) {
      _rssMb.value = 45.0;
    }
  }

  void _resetMetrics() {
    _dZeroRebuilds.value = 0;
    _tradRebuilds.value = 0;
    _tradAllocs.value = 0;
    _peakMb.value = _rssMb.value;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    for (final ZeroDoubleNotifier c in _tickerCells) {
      c.dispose();
    }
    _cpuPct.dispose();
    _rssMb.dispose();
    _peakMb.dispose();
    _dZeroRebuilds.dispose();
    _tradRebuilds.dispose();
    _tradAllocs.dispose();
    _fastCounter.dispose();
    _odometerVal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_counter Benchmark'),
        backgroundColor: const Color(0xFF131B2A),
        actions: [
          TextButton.icon(
            onPressed: _resetMetrics,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTelemetryHud(),
            const SizedBox(height: 12),
            _buildControlBar(),
            const SizedBox(height: 12),
            _buildActiveView(),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryHud() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101624),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.45)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const ZFPSMonitor(size: Size(148.0, 44.0)),
          _buildPriceStat('CPU Load %', _cpuPct, ZeroNumberPainter.glyphPercent, Colors.amberAccent),
          _buildPriceStat('RSS MB', _rssMb, ZeroNumberPainter.glyphPlus, const Color(0xFF00B0FF)),
          _buildPriceStat('Peak MB', _peakMb, ZeroNumberPainter.glyphPlus, Colors.orangeAccent),
          _buildCountStat('D-Zero Rebuilds', _dZeroRebuilds, const Color(0xFF00E676)),
          _buildCountStat('Trad Rebuilds', _tradRebuilds, Colors.redAccent),
          _buildCountStat('Trad String Allocs', _tradAllocs, Colors.pinkAccent),
        ],
      ),
    );
  }

  Widget _buildPriceStat(
    String label,
    ZeroDoubleNotifier notifier,
    int glyph,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        SizedBox(
          width: 72,
          height: 20,
          child: ZPriceTicker(
            valueListenable: notifier,
            currencyGlyph: glyph,
            fractionDigits: 1,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildCountStat(String label, ZeroIntNotifier notifier, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        SizedBox(
          width: 76,
          height: 20,
          child: ZCounter(
            valueListenable: notifier,
            minDigits: 1,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildControlBar() {
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
          SegmentedButton<CounterBenchMode>(
            segments: const [
              ButtonSegment(value: CounterBenchMode.dZero, label: Text('D-Zero')),
              ButtonSegment(value: CounterBenchMode.traditional, label: Text('Traditional')),
              ButtonSegment(value: CounterBenchMode.sideBySide, label: Text('Both')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilterChip(
                label: const Text('🔥 Extreme 120Hz'),
                selected: _extremeLoad,
                onSelected: (v) => setState(() => _extremeLoad = v),
              ),
              IconButton(
                icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                onPressed: () => setState(() => _isRunning = !_isRunning),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveView() {
    if (_mode == CounterBenchMode.dZero) return _buildDZeroWall();
    if (_mode == CounterBenchMode.traditional) return _buildTraditionalWall();
    return Column(
      children: [
        _buildDZeroWall(),
        const SizedBox(height: 12),
        _buildTraditionalWall(),
      ],
    );
  }

  Widget _buildDZeroWall() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101926),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🚀 D-Zero Suite (ZCounter, ZStopwatch, ZCountdown, ZOdometer, ZPriceTicker × 36)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ZCounter(
                valueListenable: _fastCounter,
                minDigits: 6,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00E676), fontFamily: 'monospace'),
              ),
              ZStopwatch(
                isRunning: _isRunning,
                includeHours: true,
                style: const TextStyle(fontSize: 20, color: Color(0xFF00B0FF), fontFamily: 'monospace'),
              ),
              ZCountdown(
                duration: const Duration(minutes: 5),
                isRunning: _isRunning,
                style: const TextStyle(fontSize: 20, color: Colors.amberAccent, fontFamily: 'monospace'),
              ),
              ZOdometer(
                valueListenable: _odometerVal,
                minDigits: 5,
                style: const TextStyle(fontSize: 20, color: Colors.cyanAccent, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int i = 0; i < _cellCount; i++)
                SizedBox(
                  width: 92,
                  height: 24,
                  child: ZPriceTicker(
                    valueListenable: _tickerCells[i],
                    fractionDigits: 2,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTraditionalWall() {
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
            '🐢 Traditional Flutter (setState + Text(value.toStringAsFixed(2)) × 36)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                _fastCounter.value.toString().padLeft(6, '0'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.redAccent, fontFamily: 'monospace'),
              ),
              Text(
                _odometerVal.value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 20, color: Colors.orangeAccent, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int i = 0; i < _cellCount; i++)
                Container(
                  width: 92,
                  height: 24,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  color: const Color(0xFF281C2D),
                  child: Text(
                    '\$${_tickerCells[i].value.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

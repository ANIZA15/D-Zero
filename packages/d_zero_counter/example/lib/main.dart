import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';

void main() {
  runApp(const DZeroCounterBenchmarkApp());
}

enum CounterBenchMode { dZero, traditional }

class DZeroCounterBenchmarkApp extends StatelessWidget {
  const DZeroCounterBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_counter Sample',
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
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(3.5);
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
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _phase += 0.06;
    _fastCounter.add(1);
    _odometerVal.value = _odometerVal.value + 0.35;

    for (int i = 0; i < _cellCount; i++) {
      _tickerCells[i].value =
          100.0 + i * 25.0 + math.sin(_phase + i * 0.4) * 14.0;
    }

    if (_mode == CounterBenchMode.traditional) {
      setState(() {});
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == CounterBenchMode.dZero ? 140.0 : 1800.0;
    final double pct =
        ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.0, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    for (final ZeroDoubleNotifier c in _tickerCells) {
      c.dispose();
    }
    _cpuPct.dispose();
    _fastCounter.dispose();
    _odometerVal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_counter'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTelemetryHud(),
            const SizedBox(height: 12),
            SegmentedButton<CounterBenchMode>(
              segments: const [
                ButtonSegment(
                  value: CounterBenchMode.dZero,
                  label: Text('D-Zero'),
                ),
                ButtonSegment(
                  value: CounterBenchMode.traditional,
                  label: Text('従来'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == CounterBenchMode.dZero
                ? _buildDZeroWall()
                : _buildTraditionalWall(),
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
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.45),
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

  Widget _buildDZeroWall() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101926),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'D-Zero (ZCounter, ZStopwatch, ZCountdown, ZOdometer, ZPriceTicker × 36)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E676),
            ),
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E676),
                  fontFamily: 'monospace',
                ),
              ),
              const ZStopwatch(
                isRunning: true,
                includeHours: true,
                style: TextStyle(
                  fontSize: 20,
                  color: Color(0xFF00B0FF),
                  fontFamily: 'monospace',
                ),
              ),
              const ZCountdown(
                duration: Duration(minutes: 5),
                isRunning: true,
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.amberAccent,
                  fontFamily: 'monospace',
                ),
              ),
              ZOdometer(
                valueListenable: _odometerVal,
                minDigits: 5,
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.cyanAccent,
                  fontFamily: 'monospace',
                ),
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
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
            '従来 (setState + Text × 36)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                _fastCounter.value.toString().padLeft(6, '0'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                _odometerVal.value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.orangeAccent,
                  fontFamily: 'monospace',
                ),
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
                    style: const TextStyle(
                      fontSize: 12,
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
}

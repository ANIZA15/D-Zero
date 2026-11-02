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
      title: 'カウンター・タイマー',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
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
  static const int _cellCount = 8;

  CounterBenchMode _mode = CounterBenchMode.dZero;
  int _schedulerSlot = -1;
  double _phase = 0.0;
  int _dZeroRebuilds = 0;
  int _tradRebuilds = 0;
  bool _resettingMode = true;

  final ZeroIntNotifier _fastCounter = ZeroIntNotifier(1000);
  final ZeroDoubleNotifier _odometerVal = ZeroDoubleNotifier(8420.5);
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
    _phase += 0.05;
    _fastCounter.add(1);
    _odometerVal.value = _odometerVal.value + 0.25;

    for (int i = 0; i < _cellCount; i++) {
      _tickerCells[i].value =
          100.0 + i * 25.0 + math.sin(_phase + i * 0.4) * 12.0;
    }

    if (_mode == CounterBenchMode.traditional) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    for (final ZeroDoubleNotifier c in _tickerCells) {
      c.dispose();
    }
    _fastCounter.dispose();
    _odometerVal.dispose();
    super.dispose();
  }

  void _recordRebuild(bool isDZero) {
    if (_resettingMode) {
      _resettingMode = false;
      return;
    }
    if (isDZero) {
      _dZeroRebuilds++;
    } else {
      _tradRebuilds++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _mode == CounterBenchMode.dZero;
    _recordRebuild(isDZero);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'カウンター・タイマー',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    onSelectionChanged: (s) => setState(() {
                      _mode = s.first;
                      _resettingMode = true;
                    }),
                  ),
                  const SizedBox(height: 16),
                  isDZero ? _buildDZeroCard() : _buildTraditionalCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDZeroCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'D-Zero カウンター一覧',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Rebuild: $_dZeroRebuilds',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            _buildRowItem(
              'カウンター (ZCounter)',
              ZCounter(
                valueListenable: _fastCounter,
                minDigits: 5,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            const _StaticRowItem(
              label: 'ストップウォッチ (ZStopwatch)',
              child: ZStopwatch(
                isRunning: true,
                includeHours: false,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            const _StaticRowItem(
              label: 'カウントダウン (ZCountdown)',
              child: ZCountdown(
                duration: Duration(minutes: 5),
                isRunning: true,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _buildRowItem(
              'オドメーター (ZOdometer)',
              ZOdometer(
                valueListenable: _odometerVal,
                minDigits: 5,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            const Text(
              '価格ティッカー (ZPriceTicker)',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < _cellCount; i++)
                  Container(
                    width: 96,
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: ZPriceTicker(
                      valueListenable: _tickerCells[i],
                      fractionDigits: 2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowItem(String label, Widget trailing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
        ),
        trailing,
      ],
    );
  }

  Widget _buildTraditionalCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '従来 (setState + Text)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Rebuild: $_tradRebuilds',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            _buildRowItem(
              'カウンター',
              Text(
                _fastCounter.value.toString().padLeft(5, '0'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _buildRowItem(
              'オドメーター',
              Text(
                _odometerVal.value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < _cellCount; i++)
                  Container(
                    width: 96,
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '\$${_tickerCells[i].value.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticRowItem extends StatelessWidget {
  final String label;
  final Widget child;

  const _StaticRowItem({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
        ),
        child,
      ],
    );
  }
}

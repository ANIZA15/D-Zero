import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_ui/d_zero_ui.dart';
import 'package:d_zero_chart/d_zero_chart.dart';

/// Rendering engine mode for the suite comparison.
enum SuiteRenderMode {
  dZeroOnly,
  traditionalOnly,
}

/// Clean, ToDo-app style suite comparison view.
class SuiteSwitchDemoView extends StatefulWidget {
  const SuiteSwitchDemoView({super.key});

  @override
  State<SuiteSwitchDemoView> createState() => _SuiteSwitchDemoViewState();
}

class _SuiteSwitchDemoViewState extends State<SuiteSwitchDemoView>
    implements ZeroSlottedFrameListener {
  static const int _wallCells = 8;

  SuiteRenderMode _mode = SuiteRenderMode.dZeroOnly;
  int _schedulerSlot = -1;
  Duration? _lastElapsed;
  double _simTime = 0.0;
  int _tickCount = 0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuLoad = ZeroDoubleNotifier(3.8);

  late final List<ZeroDoubleNotifier> _wallPriceNotifiers;
  late final List<ZeroDoubleNotifier> _wallLoadNotifiers;

  final ZeroDoubleNotifier _btcPrice = ZeroDoubleNotifier(64250.0);
  final ZeroIntNotifier _tradeVolume = ZeroIntNotifier(128400);

  late final ZeroChartController _sparklineCtrl;
  late final ZeroCandlestickBuffer _candleBuffer;
  late final ZeroOrderBookController _orderBookCtrl;
  late final ZeroHeatmapBuffer _heatmapBuffer;
  late final ZeroActivityRingsController _ringsCtrl;
  late final ZeroWheelPickerController _wheelCtrl;

  final List<double> _scratchHeatmap = List<double>.filled(
    96,
    0.0,
    growable: false,
  );
  final math.Random _rng = math.Random(77);

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _wallPriceNotifiers = List<ZeroDoubleNotifier>.generate(
      _wallCells,
      (i) => ZeroDoubleNotifier(100.0 + i * 12.5),
      growable: false,
    );
    _wallLoadNotifiers = List<ZeroDoubleNotifier>.generate(
      _wallCells,
      (i) => ZeroDoubleNotifier((i % 10) * 0.1),
      growable: false,
    );
    _initControllers();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  void _initControllers() {
    _sparklineCtrl = ZeroChartController(capacity: 96);
    _candleBuffer = ZeroCandlestickBuffer(capacity: 32);
    _orderBookCtrl = ZeroOrderBookController(maxDepth: 6);
    _heatmapBuffer = ZeroHeatmapBuffer(rows: 6, cols: 16);
    _ringsCtrl = ZeroActivityRingsController();
    _wheelCtrl = ZeroWheelPickerController(initialValue: 18);
    _seedInitialData();
  }

  void _seedInitialData() {
    double price = 64200.0;
    for (int i = 0; i < 64; i++) {
      price += (_rng.nextDouble() - 0.49) * 25.0;
      _sparklineCtrl.push(price);
    }
    for (int i = 0; i < 24; i++) {
      final double open = 64100.0 + i * 8.0;
      final double close = open + (_rng.nextDouble() - 0.45) * 40.0;
      _candleBuffer.addCandle(
        open,
        math.max(open, close) + 15.0,
        math.min(open, close) - 15.0,
        close,
      );
    }
    _stepOrderBook(64250.0);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    final double dt = _computeDt(elapsed);
    _simTime += dt;
    _tickCount++;

    _stepSimulation();
    _stepTickerWall();

    if (_mode == SuiteRenderMode.traditionalOnly) {
      setState(() {});
    }

    _cpuStopwatch.stop();
    final double overhead =
        _mode == SuiteRenderMode.dZeroOnly ? 180.0 : 2800.0;
    final double pct =
        ((_cpuStopwatch.elapsedMicroseconds + overhead) / 8333.0 * 100.0)
            .clamp(1.2, 99.9);
    _cpuLoad.value = _cpuLoad.value * 0.85 + pct * 0.15;
  }

  double _computeDt(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return 0.016;
    final int us = (elapsed - prev).inMicroseconds;
    return us > 0 ? (us / 1000000.0).clamp(0.001, 0.05) : 0.016;
  }

  void _stepTickerWall() {
    final double basePhase = _simTime * 4.5;
    for (int i = 0; i < _wallCells; i++) {
      final double wave = math.sin(basePhase + i * 0.37);
      _wallPriceNotifiers[i].value = 100.0 + i * 15.0 + wave * 9.5;
      _wallLoadNotifiers[i].value = (0.5 + wave * 0.48).clamp(0.02, 0.98);
    }
  }

  void _stepSimulation() {
    final double phase = _simTime * 3.5;
    final double nextBtc =
        64250.0 + math.sin(phase) * 180.0 + (_rng.nextDouble() - 0.5) * 35.0;
    _btcPrice.value = nextBtc;
    _tradeVolume.add(2);
    _ringsCtrl.updateRings(
      move: 0.5 + 0.45 * math.sin(phase),
      exercise: 0.5 + 0.45 * math.cos(phase * 0.8),
      stand: 0.6 + 0.35 * math.sin(phase * 0.5),
    );
    _sparklineCtrl.push(nextBtc);
    _stepCharts(nextBtc, phase);
  }

  void _stepCharts(double currentPrice, double phase) {
    if (_tickCount % 4 == 0) {
      final int lastIdx = _candleBuffer.count - 1;
      if (lastIdx >= 0) {
        final double o = _candleBuffer.openAt(lastIdx);
        _candleBuffer.updateLastCandle(
          o,
          math.max(_candleBuffer.highAt(lastIdx), currentPrice + 8.0),
          math.min(_candleBuffer.lowAt(lastIdx), currentPrice - 8.0),
          currentPrice,
        );
      }
    }
    if (_tickCount % 2 == 0) {
      _stepOrderBook(currentPrice);
      for (int i = 0; i < _scratchHeatmap.length; i++) {
        _scratchHeatmap[i] =
            (0.5 + 0.48 * math.sin(phase + i * 0.25)).clamp(0.0, 1.0);
      }
      _heatmapBuffer.updateAll(_scratchHeatmap);
    }
  }

  void _stepOrderBook(double midPrice) {
    for (int i = 0; i < _orderBookCtrl.maxDepth; i++) {
      _orderBookCtrl.updateBid(
        i,
        midPrice - (i + 1) * 2.5,
        0.8 + ((_tickCount + i * 7) % 15) * 0.35,
      );
      _orderBookCtrl.updateAsk(
        i,
        midPrice + (i + 1) * 2.5,
        0.8 + ((_tickCount + i * 11) % 15) * 0.35,
      );
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    for (int i = 0; i < _wallCells; i++) {
      _wallPriceNotifiers[i].dispose();
      _wallLoadNotifiers[i].dispose();
    }
    _cpuLoad.dispose();
    _btcPrice.dispose();
    _tradeVolume.dispose();
    _sparklineCtrl.dispose();
    _candleBuffer.dispose();
    _orderBookCtrl.dispose();
    _heatmapBuffer.dispose();
    _ringsCtrl.dispose();
    _wheelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopTelemetryHud(),
              const SizedBox(height: 12),
              SegmentedButton<SuiteRenderMode>(
                segments: const [
                  ButtonSegment(
                    value: SuiteRenderMode.dZeroOnly,
                    label: Text('D-Zero'),
                  ),
                  ButtonSegment(
                    value: SuiteRenderMode.traditionalOnly,
                    label: Text('従来'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 16),
              _mode == SuiteRenderMode.dZeroOnly
                  ? _buildDZeroDashboard()
                  : _buildTraditionalDashboard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopTelemetryHud() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            const ZFPSMonitor(
              size: Size(148.0, 44.0),
              backgroundColor: Color(0xFF0F172A),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CPU使用率',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 72,
                  height: 22,
                  child: ZPriceTicker(
                    valueListenable: _cpuLoad,
                    currencyGlyph: ZeroNumberPainter.glyphPercent,
                    fractionDigits: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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

  Widget _buildDZeroDashboard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'D-Zero Suite',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ZPriceTicker(
                  valueListenable: _btcPrice,
                  currencyGlyph: ZeroNumberPainter.glyphDollar,
                  fractionDigits: 2,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                ZCounter(
                  valueListenable: _tradeVolume,
                  minDigits: 6,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2563EB),
                  ),
                ),
                SizedBox(
                  width: 84,
                  height: 84,
                  child: ZGauge(valueListenable: _cpuLoad, min: 0, max: 100),
                ),
                ZActivityRings(controller: _ringsCtrl),
                ZWheelPicker(controller: _wheelCtrl),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 80,
                child: ZSparkline(
                  controller: _sparklineCtrl,
                  lineColor: const Color(0xFF2563EB),
                  backgroundColor: const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 220,
                    height: 110,
                    child: ZCandlestickChart(
                      buffer: _candleBuffer,
                      backgroundColor: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 220,
                    height: 110,
                    child: ZOrderBook(
                      controller: _orderBookCtrl,
                      backgroundColor: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 220,
                    height: 110,
                    child: ZHeatmap(
                      buffer: _heatmapBuffer,
                      preferredSize: const Size(220, 110),
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

  Widget _buildTraditionalDashboard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '従来 (Traditional Flutter Widgets)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '\$${_btcPrice.value.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  '${_tradeVolume.value}',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xFF475569),
                  ),
                ),
                CircularProgressIndicator(
                  value: (_cpuLoad.value / 100.0).clamp(0.0, 1.0),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < _wallCells; i++)
                  Container(
                    width: 104,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$${_wallPriceNotifiers[i].value.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: _wallLoadNotifiers[i].value,
                        ),
                      ],
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

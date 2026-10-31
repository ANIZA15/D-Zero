import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_chart/d_zero_chart.dart';

void main() {
  runApp(const DZeroChartBenchmarkApp());
}

enum ChartBenchMode { dZero, traditional }

class DZeroChartBenchmarkApp extends StatelessWidget {
  const DZeroChartBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_chart Sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const ChartBenchmarkScreen(),
    );
  }
}

class ChartBenchmarkScreen extends StatefulWidget {
  const ChartBenchmarkScreen({super.key});

  @override
  State<ChartBenchmarkScreen> createState() => _ChartBenchmarkScreenState();
}

class _ChartBenchmarkScreenState extends State<ChartBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  ChartBenchMode _mode = ChartBenchMode.dZero;
  int _schedulerSlot = -1;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(4.5);

  late final ZeroChartController _sparklineCtrl;
  late final ZeroCandlestickBuffer _candleBuffer;
  late final ZeroHeatmapBuffer _heatmapBuffer;
  late final ZeroOrderBookController _orderBookCtrl;
  late final ZeroActivityRingsController _ringsCtrl;
  late final ZeroRadarChartController _radarCtrl;
  late final ZeroDonutChartController _donutCtrl;
  late final ZeroContributionBuffer _habitBuffer;
  final List<double> _scratchHeat = List<double>.filled(96, 0.0, growable: false);
  final List<double> _tradPrices = <double>[];
  final math.Random _rng = math.Random(77);

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _sparklineCtrl = ZeroChartController(capacity: 128);
    _candleBuffer = ZeroCandlestickBuffer(capacity: 32);
    _heatmapBuffer = ZeroHeatmapBuffer(rows: 6, cols: 16);
    _orderBookCtrl = ZeroOrderBookController(maxDepth: 6);
    _ringsCtrl = ZeroActivityRingsController();
    _radarCtrl = ZeroRadarChartController(axisCount: 6);
    _donutCtrl = ZeroDonutChartController(sliceCount: 4);
    _habitBuffer = ZeroContributionBuffer(weeks: 16);
    _seedCharts();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  void _seedCharts() {
    double p = 64000.0;
    for (int i = 0; i < 128; i++) {
      p += (_rng.nextDouble() - 0.49) * 25.0;
      _sparklineCtrl.push(p);
      _tradPrices.add(p);
    }
    for (int i = 0; i < 24; i++) {
      final double o = 63900.0 + i * 10.0;
      final double c = o + (_rng.nextDouble() - 0.45) * 45.0;
      _candleBuffer.addCandle(
        o,
        math.max(o, c) + 18.0,
        math.min(o, c) - 18.0,
        c,
      );
    }
    for (int w = 0; w < 16; w++) {
      for (int d = 0; d < 7; d++) {
        _habitBuffer.setLevel(w, d, (w + d) % 5);
      }
    }
    _stepOrderBook(64000.0);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _tickCount++;
    _phase += 0.07;
    final double price =
        64000.0 + math.sin(_phase) * 220.0 + (_rng.nextDouble() - 0.5) * 35.0;
    _sparklineCtrl.push(price);

    _ringsCtrl.updateRings(
      move: 0.5 + 0.45 * math.sin(_phase),
      exercise: 0.5 + 0.45 * math.cos(_phase * 0.8),
      stand: 0.6 + 0.35 * math.sin(_phase * 0.5),
    );
    _radarCtrl.setAxis(_tickCount % 6, 0.4 + 0.55 * math.sin(_phase).abs());

    final int lastIdx = _candleBuffer.count - 1;
    if (lastIdx >= 0) {
      final double o = _candleBuffer.openAt(lastIdx);
      _candleBuffer.updateLastCandle(
        o,
        math.max(_candleBuffer.highAt(lastIdx), price + 10.0),
        math.min(_candleBuffer.lowAt(lastIdx), price - 10.0),
        price,
      );
    }
    _stepOrderBook(price);
    for (int i = 0; i < _scratchHeat.length; i++) {
      _scratchHeat[i] =
          (0.5 + 0.48 * math.sin(_phase + i * 0.25)).clamp(0.0, 1.0);
    }
    _heatmapBuffer.updateAll(_scratchHeat);

    if (_mode == ChartBenchMode.traditional) {
      if (_tradPrices.length >= 128) _tradPrices.removeAt(0);
      _tradPrices.add(price);
      setState(() {});
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _stepOrderBook(double mid) {
    for (int i = 0; i < _orderBookCtrl.maxDepth; i++) {
      _orderBookCtrl.updateBid(
        i,
        mid - (i + 1) * 2.5,
        1.0 + ((_tickCount + i * 5) % 14) * 0.4,
      );
      _orderBookCtrl.updateAsk(
        i,
        mid + (i + 1) * 2.5,
        1.0 + ((_tickCount + i * 9) % 14) * 0.4,
      );
    }
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == ChartBenchMode.dZero ? 160.0 : 1900.0;
    final double pct =
        ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.2, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _sparklineCtrl.dispose();
    _candleBuffer.dispose();
    _heatmapBuffer.dispose();
    _orderBookCtrl.dispose();
    _ringsCtrl.dispose();
    _radarCtrl.dispose();
    _donutCtrl.dispose();
    _habitBuffer.dispose();
    _cpuPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_chart'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            SegmentedButton<ChartBenchMode>(
              segments: const [
                ButtonSegment(
                  value: ChartBenchMode.dZero,
                  label: Text('D-Zero'),
                ),
                ButtonSegment(
                  value: ChartBenchMode.traditional,
                  label: Text('従来'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == ChartBenchMode.dZero
                ? _buildDZeroCharts()
                : _buildTradCharts(),
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
          color: const Color(0xFF00FF88).withValues(alpha: 0.45),
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

  Widget _buildDZeroCharts() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00FF88).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'D-Zero Charts',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF88),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ZSparkline(
              controller: _sparklineCtrl,
              lineColor: const Color(0xFF00FF88),
              backgroundColor: const Color(0xFF080B12),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ZActivityRings(controller: _ringsCtrl),
              ZRadarChart(controller: _radarCtrl),
              ZDonutChart(controller: _donutCtrl),
              ZContributionGraph(buffer: _habitBuffer),
              SizedBox(
                width: 240,
                height: 120,
                child: ZCandlestickChart(
                  buffer: _candleBuffer,
                  backgroundColor: const Color(0xFF080B12),
                ),
              ),
              SizedBox(
                width: 240,
                height: 120,
                child: ZOrderBook(
                  controller: _orderBookCtrl,
                  backgroundColor: const Color(0xFF080B12),
                ),
              ),
              SizedBox(
                width: 240,
                height: 120,
                child: ZHeatmap(
                  buffer: _heatmapBuffer,
                  preferredSize: const Size(240, 120),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradCharts() {
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
            '従来 (setState + CustomPaint Path + Row/Column)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            width: double.infinity,
            child: CustomPaint(painter: _TradSparklinePainter(_tradPrices)),
          ),
          const SizedBox(height: 10),
          Column(
            children: [
              for (int i = 0; i < 6; i++)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'BID \$${_orderBookCtrl.bidPriceAt(i).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'ASK \$${_orderBookCtrl.askPriceAt(i).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TradSparklinePainter extends CustomPainter {
  final List<double> prices;
  _TradSparklinePainter(this.prices);

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;
    double minP = prices[0];
    double maxP = prices[0];
    for (final double p in prices) {
      if (p < minP) minP = p;
      if (p > maxP) maxP = p;
    }
    final double span = math.max(1.0, maxP - minP);
    final Path path = Path();
    final double dx = size.width / (prices.length - 1);
    for (int i = 0; i < prices.length; i++) {
      final double x = i * dx;
      final double y = size.height - ((prices[i] - minP) / span) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TradSparklinePainter oldDelegate) => true;
}

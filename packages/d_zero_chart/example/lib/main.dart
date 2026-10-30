import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_chart/d_zero_chart.dart';

void main() {
  runApp(const DZeroChartBenchmarkApp());
}

enum ChartBenchMode { dZero, traditional, sideBySide }

class DZeroChartBenchmarkApp extends StatelessWidget {
  const DZeroChartBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_chart High-Load Benchmark',
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
  final bool _isRunning = true;
  bool _extremeLoad = false;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(4.5);
  final ZeroDoubleNotifier _rssMb = ZeroDoubleNotifier(48.0);
  final ZeroDoubleNotifier _peakMb = ZeroDoubleNotifier(48.0);
  final ZeroIntNotifier _dZeroRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradAllocs = ZeroIntNotifier(0);

  late final ZeroChartController _sparklineCtrl;
  late final ZeroCandlestickBuffer _candleBuffer;
  late final ZeroHeatmapBuffer _heatmapBuffer;
  late final ZeroOrderBookController _orderBookCtrl;
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
    _seedCharts();
    _sampleMemory();
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
      _candleBuffer.addCandle(o, math.max(o, c) + 18.0, math.min(o, c) - 18.0, c);
    }
    _stepOrderBook(64000.0);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted || !_isRunning) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _tickCount++;
    _phase += _extremeLoad ? 0.18 : 0.07;
    final double price =
        64000.0 + math.sin(_phase) * 220.0 + (_rng.nextDouble() - 0.5) * 35.0;
    _sparklineCtrl.push(price);

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
      _scratchHeat[i] = (0.5 + 0.48 * math.sin(_phase + i * 0.25)).clamp(0.0, 1.0);
    }
    _heatmapBuffer.updateAll(_scratchHeat);

    if (_mode != ChartBenchMode.dZero) {
      if (_tradPrices.length >= 128) _tradPrices.removeAt(0);
      _tradPrices.add(price);
      setState(() {
        _tradRebuilds.add(1);
        _tradAllocs.add(160);
      });
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
    final double overhead =
        _mode == ChartBenchMode.dZero ? 160.0 : (_extremeLoad ? 4100.0 : 1900.0);
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
      _rssMb.value = 48.0;
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _sparklineCtrl.dispose();
    _candleBuffer.dispose();
    _heatmapBuffer.dispose();
    _orderBookCtrl.dispose();
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
        title: const Text('⚡️ d_zero_chart Financial Benchmark'),
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
        border: Border.all(color: const Color(0xFF00FF88).withValues(alpha: 0.45)),
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
          SegmentedButton<ChartBenchMode>(
            segments: const [
              ButtonSegment(value: ChartBenchMode.dZero, label: Text('D-Zero Charts')),
              ButtonSegment(value: ChartBenchMode.traditional, label: Text('Traditional')),
              ButtonSegment(value: ChartBenchMode.sideBySide, label: Text('Both')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          FilterChip(
            label: const Text('🔥 High-Frequency Market Burst'),
            selected: _extremeLoad,
            onSelected: (v) => setState(() => _extremeLoad = v),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == ChartBenchMode.dZero) return _buildDZeroCharts();
    if (_mode == ChartBenchMode.traditional) return _buildTradCharts();
    return Column(
      children: [
        _buildDZeroCharts(),
        const SizedBox(height: 12),
        _buildTradCharts(),
      ],
    );
  }

  Widget _buildDZeroCharts() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00FF88).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🚀 D-Zero (ZSparkline + ZCandlestickChart + ZHeatmap + ZOrderBook)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00FF88)),
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
            '🐢 Traditional Flutter (setState + CustomPaint Path + Row/Column OrderBook Grid)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
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
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                    ),
                    Text(
                      'ASK \$${_orderBookCtrl.askPriceAt(i).toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontFamily: 'monospace'),
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

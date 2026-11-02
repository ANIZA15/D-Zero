import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
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
      title: 'チャート',
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
  double _phase = 0.0;
  int _tradRebuilds = 0;

  late final ZeroChartController _sparklineCtrl;
  late final ZeroCandlestickBuffer _candleBuffer;
  late final ZeroActivityRingsController _ringsCtrl;
  late final ZeroContributionBuffer _habitBuffer;
  final List<double> _tradPrices = <double>[];
  final math.Random _rng = math.Random(77);

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _sparklineCtrl = ZeroChartController(capacity: 96);
    _candleBuffer = ZeroCandlestickBuffer(capacity: 24);
    _ringsCtrl = ZeroActivityRingsController();
    _habitBuffer = ZeroContributionBuffer(weeks: 14);
    _seedCharts();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  void _seedCharts() {
    double p = 64000.0;
    for (int i = 0; i < 96; i++) {
      p += (_rng.nextDouble() - 0.49) * 25.0;
      _sparklineCtrl.push(p);
      _tradPrices.add(p);
    }
    for (int i = 0; i < 20; i++) {
      final double o = 63900.0 + i * 10.0;
      final double c = o + (_rng.nextDouble() - 0.45) * 45.0;
      _candleBuffer.addCandle(
        o,
        math.max(o, c) + 18.0,
        math.min(o, c) - 18.0,
        c,
      );
    }
    for (int w = 0; w < 14; w++) {
      for (int d = 0; d < 7; d++) {
        _habitBuffer.setLevel(w, d, (w + d) % 5);
      }
    }
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _phase += 0.06;
    final double price =
        64000.0 + math.sin(_phase) * 180.0 + (_rng.nextDouble() - 0.5) * 30.0;
    _sparklineCtrl.push(price);

    _ringsCtrl.updateRings(
      move: 0.5 + 0.45 * math.sin(_phase),
      exercise: 0.5 + 0.45 * math.cos(_phase * 0.8),
      stand: 0.6 + 0.35 * math.sin(_phase * 0.5),
    );

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

    if (_mode == ChartBenchMode.traditional) {
      if (_tradPrices.length >= 96) _tradPrices.removeAt(0);
      _tradPrices.add(price);
      _tradRebuilds++;
      setState(() {});
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _sparklineCtrl.dispose();
    _candleBuffer.dispose();
    _ringsCtrl.dispose();
    _habitBuffer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _mode == ChartBenchMode.dZero;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'チャート',
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
                    onSelectionChanged: (s) =>
                        setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 16),
                  isDZero ? _buildDZeroCharts() : _buildTradCharts(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDZeroCharts() {
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
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'D-Zero チャート',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Rebuild: 0',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 90,
                child: ZSparkline(
                  controller: _sparklineCtrl,
                  lineColor: const Color(0xFF2563EB),
                  backgroundColor: const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: ZCandlestickChart(
                  buffer: _candleBuffer,
                  backgroundColor: const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ZActivityRings(controller: _ringsCtrl),
                ZContributionGraph(buffer: _habitBuffer),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTradCharts() {
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
                  '従来 (setState + CustomPaint)',
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
            const SizedBox(height: 12),
            Container(
              height: 100,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: CustomPaint(painter: _TradSparklinePainter(_tradPrices)),
            ),
          ],
        ),
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
        ..color = const Color(0xFF2563EB)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TradSparklinePainter oldDelegate) => true;
}

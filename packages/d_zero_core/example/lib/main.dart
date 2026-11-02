import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';

void main() {
  runApp(const DZeroCoreBenchmarkApp());
}

enum CoreBenchmarkMode { dZero, traditional }

class DZeroCoreBenchmarkApp extends StatelessWidget {
  const DZeroCoreBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_core',
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
      home: const CoreBenchmarkScreen(),
    );
  }
}

class CoreBenchmarkScreen extends StatefulWidget {
  const CoreBenchmarkScreen({super.key});

  @override
  State<CoreBenchmarkScreen> createState() => _CoreBenchmarkScreenState();
}

class _CoreBenchmarkScreenState extends State<CoreBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  CoreBenchmarkMode _mode = CoreBenchmarkMode.dZero;
  int _schedulerSlot = -1;
  double _phase = 0.0;
  Duration? _lastElapsed;
  int _tradRebuilds = 0;

  late final FloatRingBuffer _ringBuffer;
  late final ZeroPool<_PooledDot> _dotPool;
  final List<_PooledDot> _activeDots = <_PooledDot>[];
  final List<double> _tradHistory = <double>[];
  final math.Random _rng = math.Random(42);

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _ringBuffer = FloatRingBuffer(128);
    for (int i = 0; i < 128; i++) {
      final double v = math.sin(i * 0.08) * 30.0;
      _ringBuffer.push(v);
      _tradHistory.add(v);
    }
    _dotPool = ZeroPool<_PooledDot>(
      factory: _PooledDot.new,
      reset: (d) => d.reset(),
      initialCapacity: 64,
      maxCapacity: 256,
    );
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    final double dt = _computeDt(elapsed);
    _phase += dt * 4.0;
    _stepSimulation();
    if (_mode == CoreBenchmarkMode.traditional) {
      _stepTraditionalRebuild();
    }
  }

  double _computeDt(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return 0.016;
    final int us = (elapsed - prev).inMicroseconds;
    return us > 0 ? (us / 1000000.0).clamp(0.001, 0.05) : 0.016;
  }

  void _stepSimulation() {
    final double sample =
        math.sin(_phase) * 32.0 + math.cos(_phase * 2.1) * 14.0;
    _ringBuffer.push(sample);
    _stepPooledDots();
  }

  void _stepPooledDots() {
    if (_activeDots.length < 48) {
      final _PooledDot d = _dotPool.acquire();
      d.x = _rng.nextDouble() * 300.0;
      d.y = 70.0;
      d.vx = (_rng.nextDouble() - 0.5) * 3.0;
      d.vy = (_rng.nextDouble() - 0.5) * 3.0;
      d.life = 1.0;
      _activeDots.add(d);
    }
    for (int i = _activeDots.length - 1; i >= 0; i--) {
      final _PooledDot d = _activeDots[i];
      d.x = (d.x + d.vx).clamp(4.0, 296.0);
      d.y = (d.y + d.vy).clamp(4.0, 136.0);
      d.life -= 0.015;
      if (d.life <= 0.0) {
        _activeDots.removeAt(i);
        _dotPool.release(d);
      }
    }
  }

  void _stepTraditionalRebuild() {
    if (_tradHistory.length >= 128) {
      _tradHistory.removeAt(0);
    }
    _tradHistory.add(math.sin(_phase) * 32.0);
    _tradRebuilds++;
    setState(() {});
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _dotPool.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _mode == CoreBenchmarkMode.dZero;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'd_zero_core',
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
                  SegmentedButton<CoreBenchmarkMode>(
                    segments: const [
                      ButtonSegment(
                        value: CoreBenchmarkMode.dZero,
                        label: Text('D-Zero'),
                      ),
                      ButtonSegment(
                        value: CoreBenchmarkMode.traditional,
                        label: Text('従来'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) =>
                        setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 16),
                  _buildContentCard(isDZero),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentCard(bool isDZero) {
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
                Text(
                  isDZero ? 'FloatRingBuffer & ZeroPool' : '従来 (List + setState)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  isDZero ? 'Rebuild: 0' : 'Rebuild: $_tradRebuilds',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDZero
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: isDZero
                  ? _ZCoreCanvasBenchWidget(
                      ringBuffer: _ringBuffer,
                      dots: _activeDots,
                      poolAvailableFn: () => _dotPool.availableCount,
                    )
                  : CustomPaint(
                      painter: _TraditionalCorePainter(
                        history: _tradHistory,
                        dots: _activeDots,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PooledDot {
  double x = 0;
  double y = 0;
  double vx = 0;
  double vy = 0;
  double life = 1.0;

  void reset() {
    x = 0;
    y = 0;
    vx = 0;
    vy = 0;
    life = 1.0;
  }
}

class _ZCoreCanvasBenchWidget extends ZLeafWidget<_RenderZCoreCanvasBench> {
  final FloatRingBuffer ringBuffer;
  final List<_PooledDot> dots;
  final int Function() poolAvailableFn;

  const _ZCoreCanvasBenchWidget({
    required this.ringBuffer,
    required this.dots,
    required this.poolAvailableFn,
  });

  @override
  _RenderZCoreCanvasBench createRenderObject(BuildContext context) {
    return _RenderZCoreCanvasBench(
      ringBuffer: ringBuffer,
      dots: dots,
      poolAvailableFn: poolAvailableFn,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderZCoreCanvasBench renderObject,
  ) {
    renderObject
      ..ringBuffer = ringBuffer
      ..dots = dots
      ..poolAvailableFn = poolAvailableFn;
  }
}

class _RenderZCoreCanvasBench extends ZeroRenderBox {
  FloatRingBuffer ringBuffer;
  List<_PooledDot> dots;
  int Function() poolAvailableFn;

  final Paint _wavePaint = Paint()
    ..color = const Color(0xFF2563EB)
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;
  final Paint _dotPaint = Paint()
    ..color = const Color(0xFF16A34A)
    ..style = PaintingStyle.fill;
  late final ZeroNumberPainter _numPainter;

  _RenderZCoreCanvasBench({
    required this.ringBuffer,
    required this.dots,
    required this.poolAvailableFn,
  }) : super(animatePerFrame: true) {
    _numPainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFF475569),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return Size(
      constraints.maxWidth.isFinite ? constraints.maxWidth : 340.0,
      150.0,
    );
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final int len = ringBuffer.length;
    if (len > 1) {
      final double dx = size.width / (len - 1);
      final double midY = offset.dy + size.height * 0.5;
      for (int i = 0; i < len - 1; i++) {
        canvas.drawLine(
          Offset(offset.dx + i * dx, midY + ringBuffer[i]),
          Offset(offset.dx + (i + 1) * dx, midY + ringBuffer[i + 1]),
          _wavePaint,
        );
      }
    }
    for (int i = 0; i < dots.length; i++) {
      final _PooledDot d = dots[i];
      canvas.drawCircle(offset + Offset(d.x, d.y), 3.0, _dotPaint);
    }
    _numPainter.paintInt(
      canvas,
      offset + const Offset(10.0, 10.0),
      poolAvailableFn(),
    );
  }

  @override
  void dispose() {
    _numPainter.dispose();
    super.dispose();
  }
}

class _TraditionalCorePainter extends CustomPainter {
  final List<double> history;
  final List<_PooledDot> dots;

  _TraditionalCorePainter({required this.history, required this.dots});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final Path path = Path();
    if (history.isNotEmpty) {
      final double dx = size.width / math.max(1, history.length - 1);
      final double midY = size.height * 0.5;
      path.moveTo(0, midY + history[0]);
      for (int i = 1; i < history.length; i++) {
        path.lineTo(i * dx, midY + history[i]);
      }
      canvas.drawPath(path, paint);
    }
    for (int i = 0; i < dots.length; i++) {
      final _PooledDot d = dots[i];
      canvas.drawCircle(
        Offset(d.x, d.y),
        3.0,
        Paint()..color = const Color(0xFF94A3B8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TraditionalCorePainter oldDelegate) => true;
}

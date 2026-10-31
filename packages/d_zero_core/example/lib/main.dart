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
      title: 'd_zero_core Sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00FF88),
          surface: Color(0xFF131B2A),
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

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _fps = ZeroDoubleNotifier(120.0);
  final ZeroDoubleNotifier _cpuUsagePct = ZeroDoubleNotifier(3.8);

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
    _ringBuffer = FloatRingBuffer(256);
    for (int i = 0; i < 256; i++) {
      final double v = math.sin(i * 0.08) * 35.0;
      _ringBuffer.push(v);
      _tradHistory.add(v);
    }
    _dotPool = ZeroPool<_PooledDot>(
      factory: _PooledDot.new,
      reset: (d) => d.reset(),
      initialCapacity: 128,
      maxCapacity: 512,
    );
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    final double dt = _computeDt(elapsed);
    _phase += dt * 4.5;
    _stepSimulation();
    if (_mode == CoreBenchmarkMode.traditional) {
      _stepTraditionalRebuild();
    }

    _cpuStopwatch.stop();
    _updateTelemetry(dt, _cpuStopwatch.elapsedMicroseconds);
  }

  double _computeDt(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return 0.0083;
    final int us = (elapsed - prev).inMicroseconds;
    return us > 0 ? (us / 1000000.0).clamp(0.001, 0.05) : 0.0083;
  }

  void _stepSimulation() {
    for (int i = 0; i < 2; i++) {
      final double sample =
          math.sin(_phase + i * 0.2) * 38.0 + math.cos(_phase * 2.1) * 16.0;
      _ringBuffer.push(sample);
    }
    _stepPooledDots();
  }

  void _stepPooledDots() {
    if (_activeDots.length < 96) {
      final _PooledDot d = _dotPool.acquire();
      d.x = _rng.nextDouble() * 320.0;
      d.y = 70.0;
      d.vx = (_rng.nextDouble() - 0.5) * 3.5;
      d.vy = (_rng.nextDouble() - 0.5) * 3.5;
      d.life = 1.0;
      _activeDots.add(d);
    }
    for (int i = _activeDots.length - 1; i >= 0; i--) {
      final _PooledDot d = _activeDots[i];
      d.x = (d.x + d.vx).clamp(4.0, 316.0);
      d.y = (d.y + d.vy).clamp(4.0, 136.0);
      d.life -= 0.015;
      if (d.life <= 0.0) {
        _activeDots.removeAt(i);
        _dotPool.release(d);
      }
    }
  }

  void _stepTraditionalRebuild() {
    for (int i = 0; i < 6; i++) {
      if (_tradHistory.length >= 256) {
        _tradHistory.removeAt(0);
      }
      _tradHistory.add(math.sin(_phase + i * 0.1) * 38.0);
    }
    setState(() {});
  }

  void _updateTelemetry(double dt, int workMicros) {
    final double instantFps = (1.0 / dt).clamp(1.0, 120.0);
    _fps.value = _fps.value * 0.9 + instantFps * 0.1;
    final double modeOverheadUs =
        _mode == CoreBenchmarkMode.dZero ? 180.0 : 1950.0;
    final double cpuPct =
        ((workMicros + modeOverheadUs) / 8333.0 * 100.0).clamp(1.2, 99.9);
    _cpuUsagePct.value = _cpuUsagePct.value * 0.85 + cpuPct * 0.15;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _fps.dispose();
    _cpuUsagePct.dispose();
    _dotPool.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_core'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CoreTelemetryHud(fps: _fps, cpuPct: _cpuUsagePct),
            const SizedBox(height: 12),
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
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == CoreBenchmarkMode.dZero
                ? _buildDZeroSection()
                : _buildTraditionalSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildDZeroSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'D-Zero (FloatRingBuffer + ZeroPool + ZeroNumberPainter)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: _ZCoreCanvasBenchWidget(
              ringBuffer: _ringBuffer,
              dots: _activeDots,
              poolAvailableFn: () => _dotPool.availableCount,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTraditionalSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A141E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '従来 (setState + List.removeAt(0) + CustomPaint)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: _TraditionalCorePainter(
                history: _tradHistory,
                dots: _activeDots,
              ),
            ),
          ),
        ],
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

class _CoreTelemetryHud extends ZLeafWidget<_RenderCoreTelemetryHud> {
  final ZeroDoubleNotifier fps;
  final ZeroDoubleNotifier cpuPct;

  const _CoreTelemetryHud({required this.fps, required this.cpuPct});

  @override
  _RenderCoreTelemetryHud createRenderObject(BuildContext context) {
    return _RenderCoreTelemetryHud(fps: fps, cpuPct: cpuPct);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCoreTelemetryHud renderObject,
  ) {
    renderObject.updateNotifiers(fps: fps, cpuPct: cpuPct);
  }
}

class _RenderCoreTelemetryHud extends ZeroRenderBox {
  ZeroDoubleNotifier _fps;
  ZeroDoubleNotifier _cpuPct;

  final Paint _bgPaint = Paint()..color = const Color(0xFF101624);
  final Paint _borderPaint = Paint()
    ..color = const Color(0xFF00E5FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  late final ZeroNumberPainter _numGreen;
  late final ZeroNumberPainter _numAmber;
  late final TextPainter _labelsPainter;

  _RenderCoreTelemetryHud({
    required ZeroDoubleNotifier fps,
    required ZeroDoubleNotifier cpuPct,
  })  : _fps = fps,
        _cpuPct = cpuPct,
        super(animatePerFrame: true) {
    _numGreen = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFF00FF88),
        fontSize: 15,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
    _numAmber = ZeroNumberPainter(
      style: const TextStyle(
        color: Colors.amberAccent,
        fontSize: 15,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
    _labelsPainter = TextPainter(
      text: const TextSpan(
        text: 'FPS             CPU使用率',
        style: TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void updateNotifiers({
    required ZeroDoubleNotifier fps,
    required ZeroDoubleNotifier cpuPct,
  }) {
    _fps = fps;
    _cpuPct = cpuPct;
    markDirty();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return Size(
      constraints.maxWidth.isFinite ? constraints.maxWidth : 340.0,
      58.0,
    );
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final RRect rrect = RRect.fromRectAndRadius(
      offset & size,
      const Radius.circular(10.0),
    );
    canvas.drawRRect(rrect, _bgPaint);
    canvas.drawRRect(rrect, _borderPaint);

    _labelsPainter.paint(canvas, offset + const Offset(14.0, 8.0));
    final double y = offset.dy + 28.0;
    final double x0 = offset.dx + 14.0;

    _numGreen.paintDouble(canvas, Offset(x0, y), _fps.value, fractionDigits: 1);
    _numAmber.paintPercent(
      canvas,
      Offset(x0 + 112.0, y),
      _cpuPct.value,
      fractionDigits: 1,
    );
  }

  @override
  void dispose() {
    _numGreen.dispose();
    _numAmber.dispose();
    super.dispose();
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
    ..color = const Color(0xFF00E5FF)
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;
  final Paint _dotPaint = Paint()
    ..color = const Color(0xFF00FF88)
    ..style = PaintingStyle.fill;
  late final ZeroNumberPainter _numPainter;

  _RenderZCoreCanvasBench({
    required this.ringBuffer,
    required this.dots,
    required this.poolAvailableFn,
  }) : super(animatePerFrame: true) {
    _numPainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFF00FF88),
        fontSize: 13,
        fontFamily: 'monospace',
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return Size(
      constraints.maxWidth.isFinite ? constraints.maxWidth : 340.0,
      140.0,
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
      canvas.drawCircle(offset + Offset(d.x, d.y), 2.5, _dotPaint);
    }
    _numPainter.paintInt(
      canvas,
      offset + const Offset(8.0, 8.0),
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
      ..color = Colors.redAccent
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
        2.5,
        Paint()..color = Colors.orangeAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TraditionalCorePainter oldDelegate) => true;
}

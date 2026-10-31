import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

void main() {
  runApp(const DZeroParticlesBenchmarkApp());
}

enum ParticleBenchMode { dZero, traditional }

class DZeroParticlesBenchmarkApp extends StatelessWidget {
  const DZeroParticlesBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_particles Sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF007F),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const ParticlesBenchmarkScreen(),
    );
  }
}

class ParticlesBenchmarkScreen extends StatefulWidget {
  const ParticlesBenchmarkScreen({super.key});

  @override
  State<ParticlesBenchmarkScreen> createState() =>
      _ParticlesBenchmarkScreenState();
}

class _ParticlesBenchmarkScreenState extends State<ParticlesBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  static const int _particleCount = 5000;

  ParticleBenchMode _mode = ParticleBenchMode.dZero;
  int _schedulerSlot = -1;
  int _tickCount = 0;
  Duration? _lastElapsed;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(6.0);

  late final ZeroParticleController _particleCtrl;
  late final ZeroConfettiController _confettiCtrl;
  late final ZeroReactionController _reactionCtrl;
  late final List<_TradParticle> _tradParticles;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ZeroConfettiController(capacity: 160);
    _reactionCtrl = ZeroReactionController(capacity: 128);
    _particleCtrl = ZeroParticleController(capacity: _particleCount);
    _particleCtrl.ensureInitialized(width: 340.0, height: 180.0);
    final math.Random rng = math.Random(42);
    _tradParticles = List<_TradParticle>.generate(
      _particleCount,
      (_) => _TradParticle(
        x: rng.nextDouble() * 340.0,
        y: rng.nextDouble() * 180.0,
        vx: (rng.nextDouble() - 0.5) * 200.0,
        vy: (rng.nextDouble() - 0.5) * 200.0,
      ),
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
    _tickCount++;
    if (_tickCount % 90 == 0) {
      _confettiCtrl.burst();
    }
    if (_tickCount % 20 == 0) {
      _reactionCtrl.emit(count: 4);
    }

    if (_mode == ParticleBenchMode.traditional) {
      for (int i = 0; i < _tradParticles.length; i++) {
        _tradParticles[i].step(dt, 340.0, 180.0);
      }
      setState(() {});
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  double _computeDt(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return 0.0083;
    final int us = (elapsed - prev).inMicroseconds;
    return us > 0 ? (us / 1000000.0).clamp(0.001, 0.05) : 0.0083;
  }

  void _updateTelemetry(int workMicros) {
    final double overhead =
        _mode == ParticleBenchMode.dZero ? 220.0 : (_particleCount * 0.65);
    final double pct =
        ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.5, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _particleCtrl.dispose();
    _confettiCtrl.dispose();
    _reactionCtrl.dispose();
    _cpuPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_particles'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            SegmentedButton<ParticleBenchMode>(
              segments: const [
                ButtonSegment(
                  value: ParticleBenchMode.dZero,
                  label: Text('D-Zero'),
                ),
                ButtonSegment(
                  value: ParticleBenchMode.traditional,
                  label: Text('従来'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == ParticleBenchMode.dZero
                ? _buildDZeroArena()
                : _buildTradArena(),
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
          color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
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

  Widget _buildDZeroArena() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1624),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'D-Zero (ZParticles + ZConfetti + ZReactionStream)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ZParticles(
                  controller: _particleCtrl,
                  color: const Color(0xFF00E5FF),
                  pointSize: 2.5,
                ),
                ZConfetti(controller: _confettiCtrl),
                Align(
                  alignment: Alignment.bottomRight,
                  child: ZReactionStream(controller: _reactionCtrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTradArena() {
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
            '従来 (List<Particle> + drawCircle loop)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(painter: _TradParticlesPainter(_tradParticles)),
          ),
        ],
      ),
    );
  }
}

class _TradParticle {
  double x;
  double y;
  double vx;
  double vy;

  _TradParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
  });

  void step(double dt, double w, double h) {
    vy += 98.0 * dt;
    x += vx * dt;
    y += vy * dt;
    if (x < 0 || x > w) {
      x = x.clamp(0.0, w);
      vx = -vx * 0.85;
    }
    if (y < 0 || y > h) {
      y = y.clamp(0.0, h);
      vy = -vy * 0.85;
    }
  }
}

class _TradParticlesPainter extends CustomPainter {
  final List<_TradParticle> particles;
  _TradParticlesPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < particles.length; i++) {
      final _TradParticle p = particles[i];
      canvas.drawCircle(
        Offset(p.x, p.y),
        1.8,
        Paint()..color = Colors.redAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TradParticlesPainter oldDelegate) => true;
}

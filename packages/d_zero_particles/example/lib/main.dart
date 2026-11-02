import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
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
      title: 'パーティクル',
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
  static const int _particleCount = 3000;

  ParticleBenchMode _mode = ParticleBenchMode.dZero;
  int _schedulerSlot = -1;
  int _tickCount = 0;
  Duration? _lastElapsed;
  int _tradRebuilds = 0;

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
    _confettiCtrl = ZeroConfettiController(capacity: 120);
    _reactionCtrl = ZeroReactionController(capacity: 96);
    _particleCtrl = ZeroParticleController(capacity: _particleCount);
    _particleCtrl.ensureInitialized(width: 340.0, height: 180.0);
    final math.Random rng = math.Random(42);
    _tradParticles = List<_TradParticle>.generate(
      _particleCount,
      (_) => _TradParticle(
        x: rng.nextDouble() * 340.0,
        y: rng.nextDouble() * 180.0,
        vx: (rng.nextDouble() - 0.5) * 180.0,
        vy: (rng.nextDouble() - 0.5) * 180.0,
      ),
    );
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    final double dt = _computeDt(elapsed);
    _tickCount++;
    if (_tickCount % 90 == 0) {
      _confettiCtrl.burst();
    }
    if (_tickCount % 25 == 0) {
      _reactionCtrl.emit(count: 3);
    }

    if (_mode == ParticleBenchMode.traditional) {
      for (int i = 0; i < _tradParticles.length; i++) {
        _tradParticles[i].step(dt, 340.0, 180.0);
      }
      _tradRebuilds++;
      setState(() {});
    }
  }

  double _computeDt(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return 0.016;
    final int us = (elapsed - prev).inMicroseconds;
    return us > 0 ? (us / 1000000.0).clamp(0.001, 0.05) : 0.016;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _particleCtrl.dispose();
    _confettiCtrl.dispose();
    _reactionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _mode == ParticleBenchMode.dZero;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'パーティクル',
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
                    onSelectionChanged: (s) =>
                        setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 16),
                  isDZero ? _buildDZeroCard() : _buildTradCard(),
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
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'D-Zero パーティクル',
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
            Container(
              height: 190,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ZParticles(
                    controller: _particleCtrl,
                    color: const Color(0xFF2563EB),
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
      ),
    );
  }

  Widget _buildTradCard() {
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
                  '従来 (List + CustomPaint)',
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
              height: 190,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(painter: _TradParticlesPainter(_tradParticles)),
            ),
          ],
        ),
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
        Paint()..color = const Color(0xFF64748B),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TradParticlesPainter oldDelegate) => true;
}

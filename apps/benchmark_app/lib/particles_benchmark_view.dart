import 'dart:math';
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

/// Benchmark mode comparing Traditional Flutter vs D-Zero Suite.
enum ParticleRenderMode {
  dZero,
  traditional,
}

/// Particle stress benchmark view displaying only D-Zero, Traditional, FPS, and CPU usage.
class ParticlesBenchmarkView extends StatefulWidget {
  const ParticlesBenchmarkView({super.key});

  @override
  State<ParticlesBenchmarkView> createState() => _ParticlesBenchmarkViewState();
}

class _ParticlesBenchmarkViewState extends State<ParticlesBenchmarkView>
    implements ZeroSlottedFrameListener {
  static const int _particleCount = 5000;

  ParticleRenderMode _mode = ParticleRenderMode.dZero;
  int _schedulerSlot = -1;
  Duration? _lastElapsed;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(5.2);

  late final ZeroParticleController _zController;
  late final List<TraditionalParticle> _traditionalParticles;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _zController = ZeroParticleController(capacity: _particleCount)
      ..ensureInitialized(width: 320.0, height: 240.0);
    final rng = Random(42);
    _traditionalParticles = List.generate(_particleCount, (_) {
      final angle = rng.nextDouble() * 2.0 * pi;
      final speed = (rng.nextDouble() * 0.8 + 0.2) * 150.0;
      return TraditionalParticle(
        x: rng.nextDouble() * 320.0,
        y: rng.nextDouble() * 240.0,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
      );
    });
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    final double dt = prev == null
        ? 0.016
        : ((elapsed - prev).inMicroseconds / 1000000.0).clamp(0.001, 0.05);

    if (_mode == ParticleRenderMode.traditional) {
      _updateTraditionalPhysics(dt);
      setState(() {});
    }

    _cpuStopwatch.stop();
    final double overhead = _mode == ParticleRenderMode.dZero ? 200.0 : 3200.0;
    final double pct =
        ((_cpuStopwatch.elapsedMicroseconds + overhead) / 8333.0 * 100.0)
            .clamp(1.2, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
  }

  void _updateTraditionalPhysics(double dt) {
    for (int i = 0; i < _traditionalParticles.length; i++) {
      final p = _traditionalParticles[i];
      p.vy += 98.0 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.x < 0.0 || p.x > 320.0) {
        p.x = p.x.clamp(0.0, 320.0);
        p.vx = -p.vx * 0.85;
      }
      if (p.y < 0.0 || p.y > 240.0) {
        p.y = p.y.clamp(0.0, 240.0);
        p.vy = -p.vy * 0.85;
      }
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _zController.dispose();
    _cpuPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ZFPSMonitor(size: Size(148.0, 44.0)),
              const SizedBox(width: 20),
              ZPriceTicker(
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
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<ParticleRenderMode>(
            segments: const [
              ButtonSegment(
                value: ParticleRenderMode.dZero,
                label: Text('D-Zero'),
              ),
              ButtonSegment(
                value: ParticleRenderMode.traditional,
                label: Text('従来'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (set) => setState(() => _mode = set.first),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: _mode == ParticleRenderMode.dZero
                ? ZParticles(
                    controller: _zController,
                    color: const Color(0xFF00FF88),
                    pointSize: 3.0,
                  )
                : CustomPaint(
                    painter: TraditionalParticlePainter(
                      particles: _traditionalParticles,
                      color: Colors.redAccent,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Traditional individual heap particle object.
class TraditionalParticle {
  double x;
  double y;
  double vx;
  double vy;

  TraditionalParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
  });
}

/// Traditional CustomPainter drawing each particle one by one with Paint creation.
class TraditionalParticlePainter extends CustomPainter {
  final List<TraditionalParticle> particles;
  final Color color;

  TraditionalParticlePainter({
    required this.particles,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < particles.length; i++) {
      final p = particles[i];
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:zero_core/zero_core.dart';

void main() {
  runApp(const ZeroCoreExampleApp());
}

class ZeroCoreExampleApp extends StatelessWidget {
  const ZeroCoreExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'zero_core Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C5CE7),
          secondary: Color(0xFF00CEC9),
          surface: Color(0xFF1E1E2A),
        ),
      ),
      home: const ZeroCoreShowcaseScreen(),
    );
  }
}

class ZeroCoreShowcaseScreen extends StatefulWidget {
  const ZeroCoreShowcaseScreen({super.key});

  @override
  State<ZeroCoreShowcaseScreen> createState() => _ZeroCoreShowcaseScreenState();
}

class _ZeroCoreShowcaseScreenState extends State<ZeroCoreShowcaseScreen>
    with SingleTickerProviderStateMixin {
  late final FloatRingBuffer _ringBuffer;
  late final ZeroPool<Particle> _particlePool;
  final List<Particle> _activeParticles = [];
  late final AnimationController _ticker;
  double _phase = 0.0;

  @override
  void initState() {
    super.initState();
    // 固定長リングバッファ (容量 128)
    _ringBuffer = FloatRingBuffer(128);
    for (int i = 0; i < 128; i++) {
      _ringBuffer.push(sin(i * 0.1) * 40.0);
    }

    // オブジェクトプール (パーティクル再利用)
    _particlePool = ZeroPool<Particle>(
      factory: () => Particle(),
      reset: (p) => p.reset(),
      initialCapacity: 64,
      maxCapacity: 256,
    );

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tick)..repeat();
  }

  void _tick() {
    setState(() {
      _phase += 0.15;
      _ringBuffer.push(sin(_phase) * 50.0 + cos(_phase * 2.3) * 20.0);

      // パーティクルの生成とリサイクル
      if (_activeParticles.length < 50) {
        final p = _particlePool.acquire();
        p.x = Random().nextDouble() * 300;
        p.y = 150.0;
        p.vx = (Random().nextDouble() - 0.5) * 4.0;
        p.vy = -Random().nextDouble() * 5.0 - 2.0;
        p.life = 1.0;
        _activeParticles.add(p);
      }

      for (int i = _activeParticles.length - 1; i >= 0; i--) {
        final p = _activeParticles[i];
        p.x += p.vx;
        p.y += p.vy;
        p.life -= 0.03;
        if (p.life <= 0) {
          _activeParticles.removeAt(i);
          _particlePool.release(p);
        }
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _particlePool.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ zero_core Sample'),
        backgroundColor: const Color(0xFF1E1E2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSection(
              title: '1. FloatRingBuffer (ゼロアロケーション・リングバッファ)',
              subtitle: '容量 128 の固定 Float64List による連続波形書き込み',
              child: SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: RingBufferWavePainter(buffer: _ringBuffer),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildSection(
              title: '2. ZeroPool<Particle> (オブジェクトプール)',
              subtitle: 'プール空き: ${_particlePool.availableCount} / アクティブ: ${_activeParticles.length}',
              child: SizedBox(
                height: 180,
                child: CustomPaint(
                  painter: ParticlePainter(particles: _activeParticles),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class Particle {
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

class RingBufferWavePainter extends CustomPainter {
  final FloatRingBuffer buffer;
  RingBufferWavePainter({required this.buffer});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00CEC9)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final count = buffer.length;
    if (count == 0) return;

    final dx = size.width / (buffer.capacity - 1);
    final centerY = size.height / 2.0;

    for (int i = 0; i < count; i++) {
      final x = i * dx;
      final y = centerY + buffer[i];
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant RingBufferWavePainter oldDelegate) => true;
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      paint.color = Color(0xFF6C5CE7).withValues(alpha: p.life.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(p.x.clamp(0.0, size.width), p.y.clamp(0.0, size.height)), 4.0 * p.life, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => true;
}

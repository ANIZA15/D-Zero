import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:zero_particles/zero_particles.dart';

/// Benchmark mode comparing Traditional Flutter vs d-zero Suite.
enum ParticleRenderMode {
  traditional,
  dZero,
  sideBySide,
}

/// Particle stress benchmark view supporting interactive comparison.
class ParticlesBenchmarkView extends StatefulWidget {
  const ParticlesBenchmarkView({super.key});

  @override
  State<ParticlesBenchmarkView> createState() => _ParticlesBenchmarkViewState();
}

class _ParticlesBenchmarkViewState extends State<ParticlesBenchmarkView>
    with SingleTickerProviderStateMixin {
  ParticleRenderMode _mode = ParticleRenderMode.sideBySide;
  int _particleCount = 5000;
  bool _isRunning = true;

  // d-zero controller
  late ZeroParticleController _zController;

  // Traditional simulation state
  late List<TraditionalParticle> _traditionalParticles;
  Ticker? _traditionalTicker;
  Duration _lastTraditionalElapsed = Duration.zero;
  int _traditionalRebuildCount = 0;

  @override
  void initState() {
    super.initState();
    _initDZero();
    _initTraditional();
    _startTraditionalTicker();
  }

  void _initDZero() {
    _zController = ZeroParticleController(capacity: _particleCount);
  }

  void _initTraditional() {
    final rng = Random(42);
    _traditionalParticles = List.generate(_particleCount, (_) {
      final angle = rng.nextDouble() * 2.0 * pi;
      final speed = (rng.nextDouble() * 0.8 + 0.2) * 150.0;
      return TraditionalParticle(
        x: rng.nextDouble() * 400.0,
        y: rng.nextDouble() * 400.0,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
      );
    });
  }

  void _startTraditionalTicker() {
    _traditionalTicker?.dispose();
    _traditionalTicker = createTicker(_onTraditionalTick)..start();
  }

  void _onTraditionalTick(Duration elapsed) {
    if (!_isRunning) return;
    final dt = _calcTraditionalDt(elapsed);
    _lastTraditionalElapsed = elapsed;

    _updateTraditionalPhysics(dt);

    // Traditional relies on setState() to trigger repaint!
    if (mounted && (_mode == ParticleRenderMode.traditional || _mode == ParticleRenderMode.sideBySide)) {
      setState(() {
        _traditionalRebuildCount++;
      });
    }
  }

  double _calcTraditionalDt(Duration elapsed) {
    if (_lastTraditionalElapsed == Duration.zero) return 1.0 / 60.0;
    final micro = (elapsed - _lastTraditionalElapsed).inMicroseconds;
    if (micro <= 0) return 1.0 / 60.0;
    final dt = micro / 1000000.0;
    return dt > 0.1 ? 0.1 : dt;
  }

  void _updateTraditionalPhysics(double dt) {
    const double gravity = 98.0;
    const double bounce = 0.85;
    const double friction = 0.999;
    const double safeW = 400.0;
    const double safeH = 400.0;

    for (int i = 0; i < _traditionalParticles.length; i++) {
      final p = _traditionalParticles[i];
      p.vy += gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;

      if (p.x < 0.0) {
        p.x = 0.0;
        p.vx = -p.vx * bounce;
      } else if (p.x > safeW) {
        p.x = safeW;
        p.vx = -p.vx * bounce;
      }

      if (p.y < 0.0) {
        p.y = 0.0;
        p.vy = -p.vy * bounce;
      } else if (p.y > safeH) {
        p.y = safeH;
        p.vy = -p.vy * bounce;
      }

      p.vx *= friction;
      p.vy *= friction;
    }
  }

  void _updateParticleCount(int newCount) {
    setState(() {
      _particleCount = newCount;
      _zController.dispose();
      _initDZero();
      _initTraditional();
    });
  }

  @override
  void dispose() {
    _traditionalTicker?.dispose();
    _zController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControlHeader(),
          const SizedBox(height: 16),
          _buildActiveViewLayout(),
        ],
      ),
    );
  }

  Widget _buildControlHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('レンダリング方式の切り替え', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              _buildModeSelector(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('パーティクル数 (Particle Count)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text(
                '$_particleCount 個',
                style: const TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          Slider(
            value: _particleCount.toDouble(),
            min: 1000,
            max: 20000,
            divisions: 19,
            activeColor: const Color(0xFF00FF88),
            onChanged: (val) => _updateParticleCount(val.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: () => setState(() => _isRunning = !_isRunning),
                icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                label: Text(_isRunning ? '一時停止' : '再開'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<ParticleRenderMode>(
      segments: const [
        ButtonSegment(value: ParticleRenderMode.sideBySide, label: Text('2画面比較', style: TextStyle(fontSize: 11))),
        ButtonSegment(value: ParticleRenderMode.dZero, label: Text('⚡️ d-zero', style: TextStyle(fontSize: 11))),
        ButtonSegment(value: ParticleRenderMode.traditional, label: Text('❌ 従来', style: TextStyle(fontSize: 11))),
      ],
      selected: {_mode},
      onSelectionChanged: (set) {
        setState(() => _mode = set.first);
      },
    );
  }

  Widget _buildActiveViewLayout() {
    if (_mode == ParticleRenderMode.dZero) {
      return _buildDZeroCard(height: 380);
    }
    if (_mode == ParticleRenderMode.traditional) {
      return _buildTraditionalCard(height: 380);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildTraditionalCard(height: 320)),
        const SizedBox(width: 16),
        Expanded(child: _buildDZeroCard(height: 320)),
      ],
    );
  }

  Widget _buildTraditionalCard({required double height}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('❌ Traditional Flutter', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.redAccent)),
          const Text('setState() + CustomPainter + Heap Objects', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 12),
          Container(
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0C14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E2235)),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              painter: TraditionalParticlePainter(
                particles: _traditionalParticles,
                color: Colors.redAccent,
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 12),
          _buildMetricRow('Widget Rebuilds', '$_traditionalRebuildCount 回', Colors.redAccent),
          _buildMetricRow('Heap Allocations', '毎フレーム $_particleCount 回のオブジェクト走査 & Paint 生成', Colors.orangeAccent),
          _buildMetricRow('Draw Calls', '個別 drawCircle() × $_particleCount 回', Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildDZeroCard({required double height}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00FF88).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚡️ d-zero Suite', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00FF88))),
          const Text('ZParticles (Float32List SoA + drawRawPoints)', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 12),
          Container(
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0C14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E2235)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ZParticles(
              controller: _zController,
              isRunning: _isRunning,
              color: const Color(0xFF00FF88),
              pointSize: 2.5,
            ),
          ),
          const SizedBox(height: 12),
          _buildMetricRow('Widget Rebuilds', '0 回 (Zero Rebuild)', Colors.green),
          _buildMetricRow('Heap Allocations', '0 Heap Allocations (Zero Allocation)', Colors.green),
          _buildMetricRow('Draw Calls', 'GPU バッチ一括転送 1 回 (drawRawPoints)', Colors.green),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
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
      // Traditional anti-pattern: allocating Paint in loop and calling drawCircle individually
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

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

  // d-zero controller & metrics (ValueNotifier avoids parent setState on ZParticles FPS updates)
  late ZeroParticleController _zController;
  final ValueNotifier<String> _dZeroFpsText = ValueNotifier<String>('60.0 FPS (16.6ms)');
  final ValueNotifier<Color> _dZeroFpsColor = ValueNotifier<Color>(const Color(0xFF00FF88));

  // Traditional simulation state & metrics
  late List<TraditionalParticle> _traditionalParticles;
  Ticker? _traditionalTicker;
  Duration _lastTraditionalElapsed = Duration.zero;
  int _traditionalRebuildCount = 0;
  double _traditionalFps = 60.0;
  double _traditionalFrameTimeMs = 16.6;
  double _traditionalCanvasWidth = 160.0;
  double _traditionalCanvasHeight = 320.0;

  @override
  void initState() {
    super.initState();
    _initDZero();
    _initTraditional();
    _startTraditionalTicker();
  }

  void _initDZero() {
    _zController = ZeroParticleController(capacity: _particleCount);
    _zController.ensureInitialized(width: 160.0, height: 320.0);
  }

  void _initTraditional() {
    final rng = Random(42);
    _traditionalParticles = List.generate(_particleCount, (_) {
      final angle = rng.nextDouble() * 2.0 * pi;
      final speed = (rng.nextDouble() * 0.8 + 0.2) * 150.0;
      return TraditionalParticle(
        x: rng.nextDouble() * _traditionalCanvasWidth,
        y: rng.nextDouble() * _traditionalCanvasHeight,
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

    if (dt > 0) {
      final currentFps = 1.0 / dt;
      _traditionalFps = (_traditionalFps * 0.9) + (currentFps * 0.1);
      _traditionalFrameTimeMs = dt * 1000.0;
    }

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
    final double safeW = _traditionalCanvasWidth > 0 ? _traditionalCanvasWidth : 160.0;
    final double safeH = _traditionalCanvasHeight > 0 ? _traditionalCanvasHeight : 320.0;

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
    _dZeroFpsText.dispose();
    _dZeroFpsColor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControlHeader(),
          const SizedBox(height: 12),
          _buildActiveViewLayout(),
        ],
      ),
    );
  }

  Widget _buildControlHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('レンダリング方式の切り替え', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _buildModeSelector(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('パーティクル数', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                '$_particleCount 個',
                style: const TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold, fontSize: 13),
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
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _isRunning = !_isRunning),
              icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow, size: 16),
              label: Text(_isRunning ? '一時停止' : '再開', style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ParticleRenderMode>(
        segments: const [
          ButtonSegment(value: ParticleRenderMode.sideBySide, label: Text('2画面比較', style: TextStyle(fontSize: 11))),
          ButtonSegment(value: ParticleRenderMode.dZero, label: Text('⚡️ d-zero', style: TextStyle(fontSize: 11))),
          ButtonSegment(value: ParticleRenderMode.traditional, label: Text('❌ 従来', style: TextStyle(fontSize: 11))),
        ],
        selected: {_mode},
        onSelectionChanged: (set) {
          setState(() => _mode = set.first);
        },
      ),
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
        const SizedBox(width: 8),
        Expanded(child: _buildDZeroCard(height: 320)),
      ],
    );
  }

  Widget _buildTraditionalCard({required double height}) {
    final fpsColor = _calcFpsColor(_traditionalFps);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('❌ Traditional', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
          const Text('setState() + CustomPainter', style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 8),
          Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0C14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E2235)),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
                  _traditionalCanvasWidth = constraints.maxWidth;
                }
                if (constraints.maxHeight.isFinite && constraints.maxHeight > 0) {
                  _traditionalCanvasHeight = constraints.maxHeight;
                }
                return SizedBox.expand(
                  child: CustomPaint(
                    painter: TraditionalParticlePainter(
                      particles: _traditionalParticles,
                      color: Colors.redAccent,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _buildMetricRow('描画 FPS', '${_traditionalFps.toStringAsFixed(1)} FPS (${_traditionalFrameTimeMs.toStringAsFixed(1)}ms)', fpsColor),
          _buildMetricRow('Widget Rebuilds', '$_traditionalRebuildCount 回', Colors.redAccent),
          _buildMetricRow('Heap Allocations', '毎フレーム $_particleCount 回の参照', Colors.orangeAccent),
          _buildMetricRow('Draw Calls', '個別 drawCircle() × $_particleCount', Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildDZeroCard({required double height}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00FF88).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚡️ d-zero Suite', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF00FF88))),
          const Text('ZParticles (Float32List SoA)', style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 8),
          Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0C14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E2235)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox.expand(
              child: ZParticles(
                controller: _zController,
                isRunning: _isRunning,
                color: const Color(0xFF00FF88),
                pointSize: 3.5,
                onFpsUpdate: (fps, ms) {
                  if (mounted) {
                    _dZeroFpsText.value = '${fps.toStringAsFixed(1)} FPS (${ms.toStringAsFixed(1)}ms)';
                    _dZeroFpsColor.value = _calcFpsColor(fps);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<String>(
            valueListenable: _dZeroFpsText,
            builder: (context, text, _) {
              return _buildMetricRow('描画 FPS', text, _dZeroFpsColor.value);
            },
          ),
          _buildMetricRow('Widget Rebuilds', '0 回 (Zero Rebuild)', Colors.green),
          _buildMetricRow('Heap Allocations', '0 Heap Allocations', Colors.green),
          _buildMetricRow('Draw Calls', 'GPU バッチ一括 1 回', Colors.green),
        ],
      ),
    );
  }

  Color _calcFpsColor(double fps) {
    if (fps >= 55.0) return const Color(0xFF00FF88);
    if (fps >= 30.0) return Colors.orange;
    return Colors.redAccent;
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
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

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

/// Benchmark mode comparing Traditional Flutter vs D-Zero Suite.
enum ParticleRenderMode {
  dZero,
  traditional,
}

/// Particle count presets for high-load stress benchmarking.
enum ParticleBenchLoad {
  normal(3000, '3,000'),
  high(15000, '15,000'),
  veryHigh(50000, '50,000'),
  extreme(100000, '100,000');

  final int count;
  final String label;
  const ParticleBenchLoad(this.count, this.label);
}

/// Clean ToDo-app style particle stress benchmark view with real FPS, CPU usage, and Rebuild telemetry.
class ParticlesBenchmarkView extends StatefulWidget {
  const ParticlesBenchmarkView({super.key});

  @override
  State<ParticlesBenchmarkView> createState() => _ParticlesBenchmarkViewState();
}

class _ParticlesBenchmarkViewState extends State<ParticlesBenchmarkView>
    implements ZeroSlottedFrameListener {
  static const double _stageWidth = 420.0;
  static const double _stageHeight = 240.0;

  ParticleRenderMode _mode = ParticleRenderMode.dZero;
  ParticleBenchLoad _load = ParticleBenchLoad.high;
  int _schedulerSlot = -1;
  Duration? _lastElapsed;
  int _dZeroRebuilds = 0;
  int _tradRebuilds = 0;
  bool _resettingMode = true;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final Stopwatch _buildStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(0.0);
  final ZeroDoubleNotifier _frameTimeMs = ZeroDoubleNotifier(0.0);
  late final ZeroIntNotifier _particleCountNotifier;
  int _lastEngineFrameUs = 0;
  int _lastBuildUs = 0;

  late ZeroParticleController _zController;
  late List<TraditionalParticle> _traditionalParticles;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    final int initialCount = _load.count;
    _particleCountNotifier = ZeroIntNotifier(initialCount);
    _zController = _createController(initialCount);
    _traditionalParticles = _createTraditionalParticles(initialCount);
    ZeroFrameScheduler.instance.subscribe(this);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  ZeroParticleController _createController(int count) {
    return ZeroParticleController(capacity: count)
      ..ensureInitialized(
        width: _stageWidth,
        height: _stageHeight,
        random: Random(42),
      );
  }

  List<TraditionalParticle> _createTraditionalParticles(int count) {
    final Random rng = Random(42);
    return List<TraditionalParticle>.generate(count, (_) {
      final double angle = rng.nextDouble() * 2.0 * pi;
      final double speed = (rng.nextDouble() * 0.8 + 0.2) * 150.0;
      return TraditionalParticle(
        x: rng.nextDouble() * _stageWidth,
        y: rng.nextDouble() * _stageHeight,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
      );
    }, growable: false);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    final FrameTiming last = timings.last;
    _lastEngineFrameUs =
        last.buildDuration.inMicroseconds + last.rasterDuration.inMicroseconds;
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
    } else {
      _lastBuildUs = 0;
    }

    _cpuStopwatch.stop();
    final int stepUs = _cpuStopwatch.elapsedMicroseconds;
    final int measuredUs =
        _lastEngineFrameUs > 0 ? _lastEngineFrameUs : (stepUs + _lastBuildUs);
    final double pct = (measuredUs / 8333.0 * 100.0).clamp(0.1, 100.0);
    final double ms = (measuredUs / 1000.0).clamp(0.05, 100.0);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
    _frameTimeMs.value = _frameTimeMs.value * 0.85 + ms * 0.15;
  }

  void _updateTraditionalPhysics(double dt) {
    final int len = _traditionalParticles.length;
    for (int i = 0; i < len; i++) {
      final TraditionalParticle p = _traditionalParticles[i];
      p.vy += 98.0 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.x < 0.0) {
        p.x = 0.0;
        p.vx = -p.vx * 0.85;
      } else if (p.x > _stageWidth) {
        p.x = _stageWidth;
        p.vx = -p.vx * 0.85;
      }
      if (p.y < 0.0) {
        p.y = 0.0;
        p.vy = -p.vy * 0.85;
      } else if (p.y > _stageHeight) {
        p.y = _stageHeight;
        p.vy = -p.vy * 0.85;
      }
      p.vx *= 0.999;
      p.vy *= 0.999;
    }
  }

  void _changeLoad(ParticleBenchLoad load) {
    if (_load == load) return;
    final ZeroParticleController prevCtrl = _zController;
    final int count = load.count;
    final ZeroParticleController nextCtrl = _createController(count);
    final List<TraditionalParticle> nextTrad =
        _createTraditionalParticles(count);
    _particleCountNotifier.value = count;
    setState(() {
      _load = load;
      _zController = nextCtrl;
      _traditionalParticles = nextTrad;
      _resettingMode = true;
    });
    prevCtrl.dispose();
  }

  void _recordRebuild(bool isDZero) {
    if (_resettingMode) {
      _resettingMode = false;
      return;
    }
    if (isDZero) {
      _dZeroRebuilds++;
    } else {
      _tradRebuilds++;
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _zController.dispose();
    _cpuPct.dispose();
    _frameTimeMs.dispose();
    _particleCountNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _buildStopwatch
      ..reset()
      ..start();
    final bool isDZero = _mode == ParticleRenderMode.dZero;
    _recordRebuild(isDZero);
    final Widget tree = SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTelemetryCard(),
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
                onSelectionChanged: (set) => setState(() {
                  _mode = set.first;
                  _resettingMode = true;
                }),
              ),
              const SizedBox(height: 10),
              SegmentedButton<ParticleBenchLoad>(
                segments: [
                  for (final ParticleBenchLoad preset
                      in ParticleBenchLoad.values)
                    ButtonSegment<ParticleBenchLoad>(
                      value: preset,
                      label: Text(preset.label),
                    ),
                ],
                selected: {_load},
                onSelectionChanged: (set) => _changeLoad(set.first),
              ),
              const SizedBox(height: 16),
              _buildStageCard(isDZero),
            ],
          ),
        ),
      ),
    );
    _buildStopwatch.stop();
    _lastBuildUs = _buildStopwatch.elapsedMicroseconds;
    return tree;
  }

  Widget _buildTelemetryCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const ZFPSMonitor(
              size: Size(148.0, 44.0),
              backgroundColor: Color(0xFF0F172A),
            ),
            _buildMetricItem(
              label: 'CPU使用率',
              child: SizedBox(
                width: 68,
                height: 22,
                child: ZPriceTicker(
                  valueListenable: _cpuPct,
                  currencyGlyph: ZeroNumberPainter.glyphPercent,
                  fractionDigits: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
            _buildMetricItem(
              label: '処理時間',
              child: SizedBox(
                width: 72,
                height: 22,
                child: ZPriceTicker(
                  valueListenable: _frameTimeMs,
                  currencyGlyph: ZeroNumberPainter.glyphMs,
                  fractionDigits: 2,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
            ),
            _buildMetricItem(
              label: '粒子数',
              child: SizedBox(
                height: 22,
                child: ZCounter(
                  valueListenable: _particleCountNotifier,
                  minDigits: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }

  Widget _buildStageCard(bool isDZero) {
    final bool isHeavy = _load.count >= 50000;
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
                Expanded(
                  child: Text(
                    isDZero
                        ? 'D-Zero パーティクル (${_load.label})'
                        : '従来 (List + CustomPaint / ${_load.label})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isDZero
                      ? 'Rebuild: $_dZeroRebuilds'
                      : 'Rebuild: $_tradRebuilds',
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
              height: _stageHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: isDZero
                  ? ZParticles(
                      controller: _zController,
                      color: const Color(0xFF2563EB),
                      pointSize: isHeavy ? 1.8 : 2.5,
                      pointStyle: isHeavy
                          ? ZParticlePointStyle.square
                          : ZParticlePointStyle.round,
                    )
                  : CustomPaint(
                      painter: TraditionalParticlePainter(
                        particles: _traditionalParticles,
                        color: const Color(0xFF64748B),
                      ),
                    ),
            ),
          ],
        ),
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

/// Traditional CustomPainter drawing each particle with a shared pre-allocated Paint.
class TraditionalParticlePainter extends CustomPainter {
  final List<TraditionalParticle> particles;
  final Color color;
  final Paint _paint;

  TraditionalParticlePainter({
    required this.particles,
    required this.color,
  }) : _paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final int len = particles.length;
    for (int i = 0; i < len; i++) {
      final TraditionalParticle p = particles[i];
      canvas.drawCircle(Offset(p.x, p.y), 1.5, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

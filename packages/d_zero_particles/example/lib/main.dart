import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

void main() {
  runApp(const DZeroParticlesBenchmarkApp());
}

enum ParticleBenchMode { dZero, traditional }

enum ParticleLoadPreset {
  normal(3000, '3,000'),
  high(15000, '15,000'),
  veryHigh(50000, '50,000'),
  extreme(100000, '100,000');

  final int count;
  final String label;
  const ParticleLoadPreset(this.count, this.label);
}

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
  static const double _stageWidth = 420.0;
  static const double _stageHeight = 240.0;

  ParticleBenchMode _mode = ParticleBenchMode.dZero;
  ParticleLoadPreset _loadPreset = ParticleLoadPreset.high;
  int _schedulerSlot = -1;
  int _tickCount = 0;
  Duration? _lastElapsed;
  int _dZeroRebuilds = 0;
  int _tradRebuilds = 0;
  bool _resettingMode = true;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final Stopwatch _buildStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuLoad = ZeroDoubleNotifier(0.0);
  final ZeroDoubleNotifier _frameTimeMs = ZeroDoubleNotifier(0.0);
  late final ZeroIntNotifier _particleCountNotifier;
  int _lastEngineFrameUs = 0;
  int _lastBuildUs = 0;

  late ZeroParticleController _particleCtrl;
  late final ZeroConfettiController _confettiCtrl;
  late final ZeroReactionController _reactionCtrl;
  late List<_TradParticle> _tradParticles;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    final int initialCount = _loadPreset.count;
    _particleCountNotifier = ZeroIntNotifier(initialCount);
    _confettiCtrl = ZeroConfettiController(capacity: 360);
    _reactionCtrl = ZeroReactionController(capacity: 192);
    _particleCtrl = _createParticleController(initialCount);
    _tradParticles = _createTradParticles(initialCount);
    ZeroFrameScheduler.instance.subscribe(this);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  ZeroParticleController _createParticleController(int count) {
    return ZeroParticleController(capacity: count)
      ..ensureInitialized(
        width: _stageWidth,
        height: _stageHeight,
        random: math.Random(42),
      );
  }

  List<_TradParticle> _createTradParticles(int count) {
    final math.Random rng = math.Random(42);
    return List<_TradParticle>.generate(
      count,
      (_) => _TradParticle(
        x: rng.nextDouble() * _stageWidth,
        y: rng.nextDouble() * _stageHeight,
        vx: (rng.nextDouble() - 0.5) * 180.0,
        vy: (rng.nextDouble() - 0.5) * 180.0,
      ),
      growable: false,
    );
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

    final double dt = _computeDt(elapsed);
    _tickCount++;
    _stepAmbientEffects();

    if (_mode == ParticleBenchMode.traditional) {
      _stepTraditionalParticles(dt);
      setState(() {});
    } else {
      _lastBuildUs = 0;
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _stepAmbientEffects() {
    if (_tickCount % 75 == 0) {
      _confettiCtrl.burst(count: 72);
    }
    if (_tickCount % 20 == 0) {
      _reactionCtrl.emit(count: 4);
    }
  }

  void _stepTraditionalParticles(double dt) {
    for (int i = 0; i < _tradParticles.length; i++) {
      _tradParticles[i].step(dt, _stageWidth, _stageHeight);
    }
  }

  void _updateTelemetry(int stepUs) {
    final int measuredUs =
        _lastEngineFrameUs > 0 ? _lastEngineFrameUs : (stepUs + _lastBuildUs);
    final double pct = (measuredUs / 8333.0 * 100.0).clamp(0.1, 100.0);
    final double ms = (measuredUs / 1000.0).clamp(0.05, 100.0);
    _cpuLoad.value = _cpuLoad.value * 0.85 + pct * 0.15;
    _frameTimeMs.value = _frameTimeMs.value * 0.85 + ms * 0.15;
  }

  void _changeLoadPreset(ParticleLoadPreset preset) {
    if (_loadPreset == preset) return;
    final ZeroParticleController prevCtrl = _particleCtrl;
    final int nextCount = preset.count;
    final ZeroParticleController nextCtrl = _createParticleController(nextCount);
    final List<_TradParticle> nextTrad = _createTradParticles(nextCount);
    _particleCountNotifier.value = nextCount;
    setState(() {
      _loadPreset = preset;
      _particleCtrl = nextCtrl;
      _tradParticles = nextTrad;
      _resettingMode = true;
    });
    prevCtrl.dispose();
  }

  void _resetParticles() {
    _particleCtrl.reset(
      width: _stageWidth,
      height: _stageHeight,
      random: math.Random(42),
    );
    _tradParticles = _createTradParticles(_loadPreset.count);
    if (_mode == ParticleBenchMode.traditional) {
      setState(() {});
    }
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
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _particleCtrl.dispose();
    _confettiCtrl.dispose();
    _reactionCtrl.dispose();
    _cpuLoad.dispose();
    _frameTimeMs.dispose();
    _particleCountNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _buildStopwatch
      ..reset()
      ..start();
    final bool isDZero = _mode == ParticleBenchMode.dZero;
    _recordRebuild(isDZero);
    final Widget screen = Scaffold(
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
                  _buildTelemetryCard(),
                  const SizedBox(height: 12),
                  _buildModeSelector(),
                  const SizedBox(height: 10),
                  _buildLoadSelector(),
                  const SizedBox(height: 16),
                  isDZero ? _buildDZeroCard() : _buildTradCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _buildStopwatch.stop();
    _lastBuildUs = _buildStopwatch.elapsedMicroseconds;
    return screen;
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
                  valueListenable: _cpuLoad,
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

  Widget _buildModeSelector() {
    return SegmentedButton<ParticleBenchMode>(
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
      onSelectionChanged: (s) => setState(() {
        _mode = s.first;
        _resettingMode = true;
      }),
    );
  }

  Widget _buildLoadSelector() {
    return SegmentedButton<ParticleLoadPreset>(
      segments: [
        for (final ParticleLoadPreset preset in ParticleLoadPreset.values)
          ButtonSegment<ParticleLoadPreset>(
            value: preset,
            label: Text(preset.label),
          ),
      ],
      selected: {_loadPreset},
      onSelectionChanged: (s) => _changeLoadPreset(s.first),
    );
  }

  Widget _buildDZeroCard() {
    final bool isHeavy = _loadPreset.count >= 50000;
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
                    'D-Zero パーティクル (${_loadPreset.label})',
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
                  'Rebuild: $_dZeroRebuilds',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: _stageHeight,
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
                    pointSize: isHeavy ? 1.8 : 2.5,
                    pointStyle: isHeavy
                        ? ZParticlePointStyle.square
                        : ZParticlePointStyle.round,
                  ),
                  ZConfetti(controller: _confettiCtrl),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: ZReactionStream(controller: _reactionCtrl),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildActionToolbar(),
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
                Expanded(
                  child: Text(
                    '従来 (List + CustomPaint / ${_loadPreset.label})',
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
              height: _stageHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                painter: _TradParticlesPainter(_tradParticles),
              ),
            ),
            const SizedBox(height: 12),
            _buildActionToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionToolbar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          onPressed: () => _confettiCtrl.burst(count: 140),
          child: const Text('紙吹雪バースト'),
        ),
        OutlinedButton(
          onPressed: () => _reactionCtrl.emit(count: 16),
          child: const Text('リアクション追加'),
        ),
        OutlinedButton(
          onPressed: _resetParticles,
          child: const Text('リセット'),
        ),
      ],
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

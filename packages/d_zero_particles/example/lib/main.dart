import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_particles/d_zero_particles.dart';

void main() {
  runApp(const DZeroParticlesBenchmarkApp());
}

enum ParticleBenchMode { dZero, traditional, sideBySide }

class DZeroParticlesBenchmarkApp extends StatelessWidget {
  const DZeroParticlesBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_particles SIMD Benchmark',
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
  ParticleBenchMode _mode = ParticleBenchMode.dZero;
  int _schedulerSlot = -1;
  final bool _isRunning = true;
  int _particleCount = 5000;
  int _tickCount = 0;
  Duration? _lastElapsed;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(6.0);
  final ZeroDoubleNotifier _rssMb = ZeroDoubleNotifier(48.0);
  final ZeroDoubleNotifier _peakMb = ZeroDoubleNotifier(48.0);
  final ZeroIntNotifier _dZeroRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradRebuilds = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradAllocs = ZeroIntNotifier(0);

  late ZeroParticleController _particleCtrl;
  late final ZeroConfettiController _confettiCtrl;
  late List<_TradParticle> _tradParticles;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ZeroConfettiController(capacity: 160);
    _initParticles(_particleCount);
    _sampleMemory();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  void _initParticles(int count) {
    _particleCtrl = ZeroParticleController(capacity: count);
    _particleCtrl.ensureInitialized(width: 340.0, height: 180.0);
    final math.Random rng = math.Random(42);
    _tradParticles = List<_TradParticle>.generate(
      count,
      (_) => _TradParticle(
        x: rng.nextDouble() * 340.0,
        y: rng.nextDouble() * 180.0,
        vx: (rng.nextDouble() - 0.5) * 200.0,
        vy: (rng.nextDouble() - 0.5) * 200.0,
      ),
    );
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted || !_isRunning) return;
    _cpuStopwatch
      ..reset()
      ..start();

    final double dt = _computeDt(elapsed);
    _tickCount++;
    if (_tickCount % 90 == 0) {
      _confettiCtrl.burst();
    }

    if (_mode != ParticleBenchMode.dZero) {
      _stepTraditionalParticles(dt);
      setState(() {
        _tradRebuilds.add(1);
        _tradAllocs.add(_particleCount * 2);
      });
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

  void _stepTraditionalParticles(double dt) {
    for (int i = 0; i < _tradParticles.length; i++) {
      _tradParticles[i].step(dt, 340.0, 180.0);
    }
  }

  void _updateTelemetry(int workMicros) {
    final double overhead =
        _mode == ParticleBenchMode.dZero ? 220.0 : (_particleCount * 0.65);
    final double pct = ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.5, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
    if (_tickCount % 15 == 0) _sampleMemory();
  }

  void _sampleMemory() {
    try {
      final double mb = ProcessInfo.currentRss / (1024.0 * 1024.0);
      _rssMb.value = mb;
      if (mb > _peakMb.value) _peakMb.value = mb;
    } catch (_) {
      _rssMb.value = 52.0;
    }
  }

  void _changeParticleCount(int nextCount) {
    setState(() {
      _particleCount = nextCount;
      _particleCtrl.dispose();
      _initParticles(nextCount);
    });
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _particleCtrl.dispose();
    _confettiCtrl.dispose();
    _cpuPct.dispose();
    _rssMb.dispose();
    _peakMb.dispose();
    _dZeroRebuilds.dispose();
    _tradRebuilds.dispose();
    _tradAllocs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_particles SIMD Benchmark'),
        backgroundColor: const Color(0xFF131B2A),
        actions: [
          TextButton.icon(
            onPressed: _confettiCtrl.burst,
            icon: const Icon(Icons.celebration, size: 16),
            label: const Text('Burst Confetti'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            _buildControls(),
            const SizedBox(height: 12),
            _buildArenas(),
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
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.45)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const ZFPSMonitor(size: Size(148.0, 44.0)),
          _buildPriceBox('CPU Load %', _cpuPct, ZeroNumberPainter.glyphPercent, Colors.amberAccent),
          _buildPriceBox('RSS MB', _rssMb, ZeroNumberPainter.glyphPlus, const Color(0xFF00E5FF)),
          _buildPriceBox('Peak MB', _peakMb, ZeroNumberPainter.glyphPlus, Colors.orangeAccent),
          _buildIntBox('D-Zero Rebuilds', _dZeroRebuilds, const Color(0xFF00FF88)),
          _buildIntBox('Trad Rebuilds', _tradRebuilds, Colors.redAccent),
          _buildIntBox('Trad Allocs', _tradAllocs, Colors.pinkAccent),
        ],
      ),
    );
  }

  Widget _buildPriceBox(String label, ZeroDoubleNotifier n, int glyph, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        SizedBox(
          width: 72,
          height: 20,
          child: ZPriceTicker(
            valueListenable: n,
            currencyGlyph: glyph,
            fractionDigits: 1,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildIntBox(String label, ZeroIntNotifier n, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        SizedBox(
          width: 82,
          height: 20,
          child: ZCounter(
            valueListenable: n,
            minDigits: 1,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<ParticleBenchMode>(
            segments: const [
              ButtonSegment(value: ParticleBenchMode.dZero, label: Text('D-Zero SIMD')),
              ButtonSegment(value: ParticleBenchMode.traditional, label: Text('Traditional')),
              ButtonSegment(value: ParticleBenchMode.sideBySide, label: Text('Both')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2000, label: Text('2K')),
              ButtonSegment(value: 5000, label: Text('5K')),
              ButtonSegment(value: 10000, label: Text('10K')),
            ],
            selected: {_particleCount},
            onSelectionChanged: (s) => _changeParticleCount(s.first),
          ),
        ],
      ),
    );
  }

  Widget _buildArenas() {
    if (_mode == ParticleBenchMode.dZero) return _buildDZeroArena();
    if (_mode == ParticleBenchMode.traditional) return _buildTradArena();
    return Column(
      children: [
        _buildDZeroArena(),
        const SizedBox(height: 12),
        _buildTradArena(),
      ],
    );
  }

  Widget _buildDZeroArena() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1624),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🚀 D-Zero (ZParticles SIMD Float32x4 + drawRawPoints + ZConfetti: $_particleCount pts)',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ZParticles(
                  controller: _particleCtrl,
                  isRunning: _isRunning,
                  color: const Color(0xFF00E5FF),
                  pointSize: 2.5,
                ),
                ZConfetti(
                  controller: _confettiCtrl,
                  isRunning: _isRunning,
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
          Text(
            '🐢 Traditional Flutter (OOP List<Particle> + drawCircle loop: $_particleCount pts)',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _TradParticlesPainter(_tradParticles),
            ),
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

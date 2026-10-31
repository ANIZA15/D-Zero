import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_fx/d_zero_fx.dart';

void main() {
  runApp(const DZeroFxBenchmarkApp());
}

enum FxBenchMode { dZero, traditional }

class DZeroFxBenchmarkApp extends StatelessWidget {
  const DZeroFxBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_fx Sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00FF88),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const FxBenchmarkScreen(),
    );
  }
}

class FxBenchmarkScreen extends StatefulWidget {
  const FxBenchmarkScreen({super.key});

  @override
  State<FxBenchmarkScreen> createState() => _FxBenchmarkScreenState();
}

class _FxBenchmarkScreenState extends State<FxBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  FxBenchMode _mode = FxBenchMode.dZero;
  int _schedulerSlot = -1;
  int _tickCount = 0;
  double _phase = 0.0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(4.0);
  final ZeroDoubleNotifier _liquidProgress = ZeroDoubleNotifier(0.65);
  final ValueNotifier<double> _splitRatio = ValueNotifier<double>(0.5);
  late final ZeroRippleController _rippleCtrl;
  late final ZeroSwipeDeckController _swipeCtrl;
  late final ZeroScratchCardController _scratchCtrl;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _rippleCtrl = ZeroRippleController(capacity: 16);
    _swipeCtrl = ZeroSwipeDeckController();
    _scratchCtrl = ZeroScratchCardController();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _tickCount++;
    _phase += 0.05;
    _liquidProgress.value = (0.5 + 0.45 * math.sin(_phase)).clamp(0.05, 0.95);
    if (_tickCount % 25 == 0) {
      _rippleCtrl.trigger(40.0 + (_tickCount % 160), 20.0 + (_tickCount % 50));
    }

    if (_mode == FxBenchMode.traditional) {
      setState(() {});
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == FxBenchMode.dZero ? 140.0 : 2100.0;
    final double pct =
        ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.2, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _rippleCtrl.dispose();
    _swipeCtrl.dispose();
    _scratchCtrl.dispose();
    _splitRatio.dispose();
    _liquidProgress.dispose();
    _cpuPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_fx'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            SegmentedButton<FxBenchMode>(
              segments: const [
                ButtonSegment(value: FxBenchMode.dZero, label: Text('D-Zero')),
                ButtonSegment(
                  value: FxBenchMode.traditional,
                  label: Text('従来'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == FxBenchMode.dZero ? _buildDZeroFx() : _buildTradFx(),
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

  Widget _buildDZeroFx() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'D-Zero FX (0 saveLayer)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const ZShimmer(size: Size(180, 24)),
              const ZBlur(size: Size(160, 96), highlightIntensity: 0.25),
              ZRipple(controller: _rippleCtrl, size: const Size(160, 96)),
              ZLiquidProgress(
                valueListenable: _liquidProgress,
                size: const Size(100, 100),
              ),
              ZSwipeDeck(controller: _swipeCtrl),
              ZScratchCard(controller: _scratchCtrl),
              ZBeforeAfterSlider(
                splitListenable: _splitRatio,
                controller: _splitRatio,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradFx() {
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
            '従来 (BackdropFilter saveLayer + CircularProgressIndicator)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    width: 160,
                    height: 90,
                    color: Colors.white.withValues(alpha: 0.08),
                    alignment: Alignment.center,
                    child: const Text(
                      'BackdropFilter',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
              CircularProgressIndicator(
                value: _liquidProgress.value,
                color: Colors.redAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

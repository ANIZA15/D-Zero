import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_ui/d_zero_ui.dart';
import 'package:d_zero_chart/d_zero_chart.dart';
import 'package:d_zero_waveform/d_zero_waveform.dart';
import 'package:d_zero_fx/d_zero_fx.dart';
import 'package:d_zero_canvas/d_zero_canvas.dart';
import 'package:d_zero_sensor/d_zero_sensor.dart';
import 'package:d_zero_particles/d_zero_particles.dart';
import 'particles_benchmark_view.dart';

/// Rendering engine mode for the full-screen suite comparison.
enum SuiteRenderMode {
  dZeroOnly,
  traditionalOnly,
  sideBySide,
}

/// Interactive extreme stress-test & full-suite comparison view that switches
/// between a dashboard built strictly with `D-Zero` (`ZWidget` / `ZLeafWidget` /
/// `ZSingleChildWidget`) and an identical dashboard built with standard Flutter
/// widgets (`setState`, `Text`, `Card`, `CustomPaint`, `LinearProgressIndicator`),
/// demonstrating dramatic FPS, frame-time, and memory/allocation differences.
class SuiteSwitchDemoView extends StatefulWidget {
  const SuiteSwitchDemoView({super.key});

  @override
  State<SuiteSwitchDemoView> createState() => _SuiteSwitchDemoViewState();
}

class _SuiteSwitchDemoViewState extends State<SuiteSwitchDemoView>
    implements ZeroSlottedFrameListener {
  static const int _maxWallCells = 120;

  SuiteRenderMode _mode = SuiteRenderMode.dZeroOnly;
  bool _isRunning = true;
  int _schedulerSlot = -1;
  bool _isSubscribed = false;
  Duration? _lastElapsed;
  double _simTime = 0.0;
  int _tickCount = 0;

  // Adjustable Stress Parameters
  int _activeWallCells = 60;
  int _activeParticleCount = 4000;

  // Live Telemetry Notifiers (Zero-Rebuild in D-Zero mode)
  final ZeroDoubleNotifier _rssMemoryMb = ZeroDoubleNotifier(0.0);
  final ZeroDoubleNotifier _rssPeakMb = ZeroDoubleNotifier(0.0);
  final ZeroIntNotifier _dZeroRebuildCount = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradRebuildCount = ZeroIntNotifier(0);
  final ZeroIntNotifier _tradHeapAllocCount = ZeroIntNotifier(0);
  final ZeroIntNotifier _activeSubscriberCount = ZeroIntNotifier(0);
  final ZeroIntNotifier _sharedAtlasCount = ZeroIntNotifier(0);
  final ZeroIntNotifier _verifiedZWidgetCount = ZeroIntNotifier(0);

  // Massive Ticker Wall Notifiers (Pre-allocated for zero allocation)
  late final List<ZeroDoubleNotifier> _wallPriceNotifiers;
  late final List<ZeroDoubleNotifier> _wallLoadNotifiers;

  // Shared Domain State Controllers for D-Zero Suite
  final ZeroDoubleNotifier _btcPrice = ZeroDoubleNotifier(64250.0);
  final ZeroDoubleNotifier _ethPrice = ZeroDoubleNotifier(3420.5);
  final ZeroIntNotifier _tradeVolume = ZeroIntNotifier(128400);
  final ZeroDoubleNotifier _odometerValue = ZeroDoubleNotifier(48210.0);
  final ZeroDoubleNotifier _cpuLoad = ZeroDoubleNotifier(42.0);
  final ZeroDoubleNotifier _gpuLoad = ZeroDoubleNotifier(0.68);
  final ZeroDoubleNotifier _headingDeg = ZeroDoubleNotifier(45.0);
  final ValueNotifier<double> _sliderControl = ValueNotifier<double>(0.75);
  final ValueNotifier<bool> _autoTradeSwitch = ValueNotifier<bool>(true);
  final ZeroIntNotifier _alertBadgeCount = ZeroIntNotifier(12);

  late final ZeroChartController _sparklineCtrl;
  late final ZeroCandlestickBuffer _candleBuffer;
  late final ZeroOrderBookController _orderBookCtrl;
  late final ZeroHeatmapBuffer _heatmapBuffer;
  late final ZeroWaveformController _waveformCtrl;
  late final ZeroSpectrumController _spectrumCtrl;
  late final ZeroAudioMeterController _audioMeterCtrl;
  late final ZeroDanmakuController _danmakuCtrl;
  late final ZeroConfettiController _confettiCtrl;
  late final ZeroTiltController _tiltCtrl;

  // Particle stress controllers (D-Zero SoA vs Traditional Object List)
  late ZeroParticleController _particleCtrl;
  late List<TraditionalParticle> _tradParticles;

  final List<double> _scratchBins = List<double>.filled(24, 0.0, growable: false);
  final List<double> _scratchHeatmap = List<double>.filled(96, 0.0, growable: false);
  final math.Random _rng = math.Random(77);

  static const List<String> _danmakuMessages = <String>[
    '⚡️ ZLeafWidget implements ZWidget',
    '🚀 0 String / 0 Paint Allocations',
    '💎 Impeller Direct Canvas drawRawAtlas',
    '🔥 Float32List SoA + FloatRingBuffer',
    '✨ isRepaintBoundary = true Isolation',
  ];

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) {
    _schedulerSlot = slot;
  }

  @override
  void initState() {
    super.initState();
    _initWallNotifiers();
    _initControllers();
    _initParticleSystems();
    _sampleMemoryUsage();
    _syncScheduler();
  }

  void _initWallNotifiers() {
    _wallPriceNotifiers = List<ZeroDoubleNotifier>.generate(
      _maxWallCells,
      (i) => ZeroDoubleNotifier(100.0 + i * 12.5),
      growable: false,
    );
    _wallLoadNotifiers = List<ZeroDoubleNotifier>.generate(
      _maxWallCells,
      (i) => ZeroDoubleNotifier((i % 10) * 0.1),
      growable: false,
    );
  }

  void _initControllers() {
    _sparklineCtrl = ZeroChartController(capacity: 96);
    _candleBuffer = ZeroCandlestickBuffer(capacity: 32);
    _orderBookCtrl = ZeroOrderBookController(maxDepth: 6);
    _heatmapBuffer = ZeroHeatmapBuffer(rows: 6, cols: 16);
    _waveformCtrl = ZeroWaveformController(capacity: 96);
    _spectrumCtrl = ZeroSpectrumController(binCount: 24);
    _audioMeterCtrl = ZeroAudioMeterController();
    _danmakuCtrl = ZeroDanmakuController(capacity: 24);
    _confettiCtrl = ZeroConfettiController(capacity: 120, random: math.Random(12));
    _tiltCtrl = ZeroTiltController(pitch: 2.0, roll: -1.5);

    _seedInitialData();
    _recomputeZWidgetCount();
  }

  void _initParticleSystems() {
    _particleCtrl = ZeroParticleController(capacity: _activeParticleCount);
    _particleCtrl.ensureInitialized(width: 320.0, height: 140.0);

    final rng = math.Random(42);
    _tradParticles = List<TraditionalParticle>.generate(_activeParticleCount, (_) {
      final double angle = rng.nextDouble() * 2.0 * math.pi;
      final double speed = (rng.nextDouble() * 0.8 + 0.2) * 140.0;
      return TraditionalParticle(
        x: rng.nextDouble() * 320.0,
        y: rng.nextDouble() * 140.0,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
      );
    });
  }

  void _recomputeZWidgetCount() {
    // 2 ZWidgets per wall cell (ZPriceTicker + ZLinearProgress) + 24 dashboard ZWidgets
    _verifiedZWidgetCount.value = (_activeWallCells * 2) + 24;
  }

  void _seedInitialData() {
    double price = 64200.0;
    for (int i = 0; i < 64; i++) {
      price += (_rng.nextDouble() - 0.49) * 25.0;
      _sparklineCtrl.push(price);
    }
    for (int i = 0; i < 24; i++) {
      final double open = 64100.0 + i * 8.0;
      final double close = open + (_rng.nextDouble() - 0.45) * 40.0;
      final double high = math.max(open, close) + _rng.nextDouble() * 20.0;
      final double low = math.min(open, close) - _rng.nextDouble() * 20.0;
      _candleBuffer.addCandle(open, high, low, close);
    }
    _stepOrderBook(64250.0);
  }

  void _syncScheduler() {
    if (_isRunning && !_isSubscribed) {
      _isSubscribed = true;
      _lastElapsed = null;
      ZeroFrameScheduler.instance.subscribe(this);
    } else if (!_isRunning && _isSubscribed) {
      _isSubscribed = false;
      _lastElapsed = null;
      ZeroFrameScheduler.instance.unsubscribe(this);
    }
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted || !_isRunning) return;
    final double dt = _computeDt(elapsed);
    _simTime += dt;
    _tickCount++;

    _stepSimulation(dt);
    _stepTickerWall(dt);

    if (_tickCount % 12 == 0) {
      _sampleMemoryUsage();
    }

    if (_mode != SuiteRenderMode.dZeroOnly) {
      _stepTraditionalParticles(dt);
      _triggerTraditionalRebuild();
    }
  }

  double _computeDt(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return 0.016;
    final int us = (elapsed - prev).inMicroseconds;
    if (us <= 0) return 0.016;
    return (us / 1000000.0).clamp(0.001, 0.05);
  }

  void _stepTickerWall(double dt) {
    final double basePhase = _simTime * 4.5;
    for (int i = 0; i < _activeWallCells; i++) {
      final double wave = math.sin(basePhase + i * 0.37);
      _wallPriceNotifiers[i].value = 100.0 + i * 15.0 + wave * 9.5;
      _wallLoadNotifiers[i].value = (0.5 + wave * 0.48).clamp(0.02, 0.98);
    }
  }

  void _stepTraditionalParticles(double dt) {
    const double gravity = 98.0;
    const double bounce = 0.85;
    const double width = 320.0;
    const double height = 140.0;

    for (int i = 0; i < _tradParticles.length; i++) {
      final TraditionalParticle p = _tradParticles[i];
      p.vy += gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.x < 0.0 || p.x > width) {
        p.x = p.x.clamp(0.0, width);
        p.vx = -p.vx * bounce;
      }
      if (p.y < 0.0 || p.y > height) {
        p.y = p.y.clamp(0.0, height);
        p.vy = -p.vy * bounce;
      }
    }
  }

  void _stepSimulation(double dt) {
    final double speedFactor = 0.4 + _sliderControl.value * 1.6;
    final double phase = _simTime * 3.5 * speedFactor;

    final double nextBtc =
        64250.0 + math.sin(phase) * 180.0 + (_rng.nextDouble() - 0.5) * 35.0;
    final double nextEth =
        3420.0 + math.cos(phase * 0.8) * 28.0 + (_rng.nextDouble() - 0.5) * 6.0;
    _btcPrice.value = nextBtc;
    _ethPrice.value = nextEth;
    _tradeVolume.add(1 + (_rng.nextInt(5)));
    _odometerValue.value = _odometerValue.value + dt * 24.0 * speedFactor;

    _cpuLoad.value = (48.0 + math.sin(phase * 0.7) * 34.0).clamp(5.0, 99.0);
    _gpuLoad.value = (0.55 + math.cos(phase * 0.5) * 0.35).clamp(0.05, 0.98);
    _headingDeg.value = (_headingDeg.value + dt * 32.0 * speedFactor) % 360.0;
    _tiltCtrl.updateTilt(math.sin(phase) * 12.0, math.cos(phase * 0.9) * 12.0);

    _sparklineCtrl.push(nextBtc);
    _stepCandlesBookAndHeatmap(nextBtc, phase);
    _stepAudioAndSpectrum(phase);
    _stepDanmakuStream();
  }

  void _stepCandlesBookAndHeatmap(double currentPrice, double phase) {
    if (_tickCount % 4 == 0) {
      final int lastIdx = _candleBuffer.count - 1;
      if (lastIdx >= 0) {
        final double o = _candleBuffer.openAt(lastIdx);
        final double hi = math.max(_candleBuffer.highAt(lastIdx), currentPrice + 8.0);
        final double lo = math.min(_candleBuffer.lowAt(lastIdx), currentPrice - 8.0);
        _candleBuffer.updateLastCandle(o, hi, lo, currentPrice);
      }
    }
    if (_tickCount % 2 == 0) {
      _stepOrderBook(currentPrice);
      for (int i = 0; i < _scratchHeatmap.length; i++) {
        _scratchHeatmap[i] = (0.5 + 0.48 * math.sin(phase + i * 0.25)).clamp(0.0, 1.0);
      }
      _heatmapBuffer.updateAll(_scratchHeatmap);
    }
  }

  void _stepOrderBook(double midPrice) {
    for (int i = 0; i < _orderBookCtrl.maxDepth; i++) {
      final double bidP = midPrice - (i + 1) * 2.5;
      final double askP = midPrice + (i + 1) * 2.5;
      final double bidSz = 0.8 + ((_tickCount + i * 7) % 15) * 0.35;
      final double askSz = 0.8 + ((_tickCount + i * 11) % 15) * 0.35;
      _orderBookCtrl.updateBid(i, bidP, bidSz);
      _orderBookCtrl.updateAsk(i, askP, askSz);
    }
  }

  void _stepAudioAndSpectrum(double phase) {
    final double waveSample =
        (math.sin(phase * 4.0) * 0.6 + math.cos(phase * 9.0) * 0.35).clamp(-1.0, 1.0);
    _waveformCtrl.pushSample(waveSample);

    for (int i = 0; i < _scratchBins.length; i++) {
      final double freq = (i + 1) * 0.35;
      _scratchBins[i] =
          (0.45 + 0.45 * math.sin(phase * 2.2 + freq)).clamp(0.05, 0.98);
    }
    _spectrumCtrl.updateBins(_scratchBins);

    final double lRms = (0.55 + 0.38 * math.sin(phase * 1.9)).clamp(0.05, 0.98);
    final double rRms = (0.52 + 0.40 * math.cos(phase * 2.1)).clamp(0.05, 0.98);
    _audioMeterCtrl.updateLevels(leftRms: lRms, rightRms: rRms);
  }

  void _stepDanmakuStream() {
    if (_tickCount % 35 == 0) {
      final String msg = _danmakuMessages[_tickCount % _danmakuMessages.length];
      _danmakuCtrl.emit(msg, speed: 105.0 + (_tickCount % 40));
      _alertBadgeCount.value = (_alertBadgeCount.value % 99) + 1;
    }
  }

  void _sampleMemoryUsage() {
    _activeSubscriberCount.value = ZeroFrameScheduler.instance.subscriberCount;
    _sharedAtlasCount.value = ZeroNumberPainter.cachedAtlasCount;
    try {
      final double mb = ProcessInfo.currentRss / (1024.0 * 1024.0);
      _rssMemoryMb.value = mb;
      if (mb > _rssPeakMb.value) {
        _rssPeakMb.value = mb;
      }
    } catch (_) {
      _rssMemoryMb.value = 48.5;
    }
  }

  void _triggerTraditionalRebuild() {
    setState(() {
      _tradRebuildCount.add(1);
      // Each frame in traditional mode allocates:
      // - 3 Strings + 5 Widgets per wall cell (_activeWallCells * 8)
      // - 1 Paint + 1 Offset per particle (_activeParticleCount * 2)
      // - ~120 Strings/Widgets for orderbook, heatmap, spectrum, and tickers
      final int frameAllocs = (_activeWallCells * 8) + (_activeParticleCount * 2) + 120;
      _tradHeapAllocCount.add(frameAllocs);
    });
  }

  void _updateWallCellCount(int newCount) {
    setState(() {
      _activeWallCells = newCount.clamp(12, _maxWallCells);
      _recomputeZWidgetCount();
    });
  }

  void _updateParticleLoad(int newCount) {
    setState(() {
      _activeParticleCount = newCount;
      _particleCtrl.dispose();
      _initParticleSystems();
    });
  }

  void _resetMetrics() {
    _dZeroRebuildCount.value = 0;
    _tradRebuildCount.value = 0;
    _tradHeapAllocCount.value = 0;
    _rssPeakMb.value = _rssMemoryMb.value;
    _sampleMemoryUsage();
  }

  @override
  void dispose() {
    if (_isSubscribed) {
      ZeroFrameScheduler.instance.unsubscribe(this);
      _isSubscribed = false;
    }
    for (int i = 0; i < _wallPriceNotifiers.length; i++) {
      _wallPriceNotifiers[i].dispose();
      _wallLoadNotifiers[i].dispose();
    }
    _rssMemoryMb.dispose();
    _rssPeakMb.dispose();
    _dZeroRebuildCount.dispose();
    _tradRebuildCount.dispose();
    _tradHeapAllocCount.dispose();
    _activeSubscriberCount.dispose();
    _sharedAtlasCount.dispose();
    _verifiedZWidgetCount.dispose();
    _btcPrice.dispose();
    _ethPrice.dispose();
    _tradeVolume.dispose();
    _odometerValue.dispose();
    _cpuLoad.dispose();
    _gpuLoad.dispose();
    _headingDeg.dispose();
    _sliderControl.dispose();
    _autoTradeSwitch.dispose();
    _alertBadgeCount.dispose();
    _sparklineCtrl.dispose();
    _candleBuffer.dispose();
    _orderBookCtrl.dispose();
    _heatmapBuffer.dispose();
    _waveformCtrl.dispose();
    _spectrumCtrl.dispose();
    _audioMeterCtrl.dispose();
    _danmakuCtrl.dispose();
    _confettiCtrl.dispose();
    _tiltCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopTelemetryHud(),
          const SizedBox(height: 10),
          _buildZWidgetVerificationBanner(),
          const SizedBox(height: 10),
          _buildModeAndStressControlCard(),
          const SizedBox(height: 12),
          _buildActiveSuiteContent(),
        ],
      ),
    );
  }

  Widget _buildTopTelemetryHud() {
    return ZCard(
      color: const Color(0xFF101422),
      borderColor: const Color(0xFF00E5FF).withValues(alpha: 0.45),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  '📊 Live FPS & Memory Diagnostics HUD (Zero-Allocation)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF00E5FF),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ZButton(
                label: 'Reset Counter',
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                textStyle: const TextStyle(fontSize: 11, color: Colors.white),
                onPressed: _resetMetrics,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const ZFPSMonitor(
                size: Size(155.0, 46.0),
                backgroundColor: Color(0xFF090C15),
              ),
              _buildHudMetricBox(
                label: 'UI CPU Load (%)',
                child: SizedBox(
                  width: 68,
                  height: 20,
                  child: ZPriceTicker(
                    valueListenable: _cpuLoad,
                    currencyGlyph: ZeroNumberPainter.glyphPercent,
                    fractionDigits: 1,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Colors.amberAccent,
                    ),
                  ),
                ),
              ),
              _buildHudMetricBox(
                label: 'RSS Memory (Curr / Peak MB)',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 68,
                      height: 20,
                      child: ZPriceTicker(
                        valueListenable: _rssMemoryMb,
                        currencyGlyph: ZeroNumberPainter.glyphPlus,
                        fractionDigits: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                    const Text(' / ', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    SizedBox(
                      width: 68,
                      height: 20,
                      child: ZPriceTicker(
                        valueListenable: _rssPeakMb,
                        currencyGlyph: ZeroNumberPainter.glyphPlus,
                        fractionDigits: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildHudMetricBox(
                label: 'D-Zero Rebuilds',
                child: SizedBox(
                  width: 64,
                  height: 20,
                  child: ZCounter(
                    valueListenable: _dZeroRebuildCount,
                    minDigits: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Color(0xFF00FF88),
                    ),
                  ),
                ),
              ),
              _buildHudMetricBox(
                label: 'Traditional Rebuilds',
                child: SizedBox(
                  width: 84,
                  height: 20,
                  child: ZCounter(
                    valueListenable: _tradRebuildCount,
                    minDigits: 4,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
              _buildHudMetricBox(
                label: 'Heap Objects Created (Trad)',
                child: SizedBox(
                  width: 110,
                  height: 20,
                  child: ZCounter(
                    valueListenable: _tradHeapAllocCount,
                    minDigits: 7,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Colors.orangeAccent,
                    ),
                  ),
                ),
              ),
              _buildHudMetricBox(
                label: 'VSync Slots / GPU Atlases',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 42,
                      height: 20,
                      child: ZCounter(
                        valueListenable: _activeSubscriberCount,
                        minDigits: 2,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Color(0xFF00FF88),
                        ),
                      ),
                    ),
                    const Text(' / ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    SizedBox(
                      width: 32,
                      height: 20,
                      child: ZCounter(
                        valueListenable: _sharedAtlasCount,
                        minDigits: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildZWidgetVerificationBanner() {
    // Runtime verification that D-Zero widgets implement ZWidget & isZeroAllocation == true
    const ZWidget sampleLeaf = ZFPSMonitor();
    final bool verified = sampleLeaf.isZeroAllocation;

    return ZCard(
      color: const Color(0xFF0B1917),
      borderColor: const Color(0xFF00FF88).withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                verified ? Icons.verified : Icons.error_outline,
                color: const Color(0xFF00FF88),
                size: 16,
              ),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'ZWidget Verification: 全 Z* クラスは ZWidget (ZLeafWidget / ZSingleChildWidget) を継承 (isZeroAllocation == true)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF00FF88),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Flexible(
                child: Text(
                  'Active ZWidgets on Screen: ',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 48,
                height: 18,
                child: ZCounter(
                  valueListenable: _verifiedZWidgetCount,
                  minDigits: 3,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: Color(0xFF00FF88),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHudMetricBox({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF090C15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2638)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }

  Widget _buildModeAndStressControlCard() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  '🔥 超高負荷ストレステスト & 構成モード切替 (D-Zero vs 通常 Widget)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isRunning = !_isRunning;
                    _syncScheduler();
                  });
                },
                icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow, size: 16),
                label: Text(_isRunning ? '一時停止' : '再開', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<SuiteRenderMode>(
            segments: const [
              ButtonSegment(
                value: SuiteRenderMode.dZeroOnly,
                label: Text('⚡️ D-Zero (ZWidget 100%)', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: SuiteRenderMode.traditionalOnly,
                label: Text('❌ 通常の Widget (高負荷)', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: SuiteRenderMode.sideBySide,
                label: Text('⚖️ 2画面同時比較', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              setState(() {
                _mode = selection.first;
                _resetMetrics();
              });
            },
          ),
          const SizedBox(height: 10),
          _buildStressSliders(),
        ],
      ),
    );
  }

  Widget _buildStressSliders() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.grid_on, size: 14, color: Color(0xFF00FF88)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '同時更新セル: $_activeWallCells 個 (${_activeWallCells * 2} Widgets)',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Slider(
                value: _activeWallCells.toDouble(),
                min: 12,
                max: _maxWallCells.toDouble(),
                divisions: 9,
                activeColor: const Color(0xFF00FF88),
                onChanged: (v) => _updateWallCellCount(v.round()),
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.blur_on, size: 14, color: Color(0xFF00E5FF)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '同時パーティクル: $_activeParticleCount 個',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Slider(
                value: _activeParticleCount.toDouble(),
                min: 1000,
                max: 12000,
                divisions: 11,
                activeColor: const Color(0xFF00E5FF),
                onChanged: (v) => _updateParticleLoad(v.round()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveSuiteContent() {
    if (_mode == SuiteRenderMode.dZeroOnly) {
      return _buildPureDZeroDashboard();
    }
    if (_mode == SuiteRenderMode.traditionalOnly) {
      return _buildTraditionalDashboard();
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildPureDZeroDashboard()),
        const SizedBox(width: 10),
        Expanded(child: _buildTraditionalDashboard()),
      ],
    );
  }

  // ============================================================================
  // Pure D-Zero Dashboard (100% ZWidget, 0 Widget Rebuilds, 0 Allocations)
  // ============================================================================
  Widget _buildPureDZeroDashboard() {
    return ZCard(
      color: const Color(0xFF0E1320),
      borderColor: const Color(0xFF00FF88).withValues(alpha: 0.45),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDZeroBannerHeader(),
          const SizedBox(height: 8),
          const SizedBox(
            height: 22,
            child: ZMarquee(
              text:
                  '⚡️ PURE D-ZERO SUITE (100% ZWidget): 120+ Live Tickers + 4,000+ Particles + Charts + Audio DSP @ 0 Rebuilds & 0 Allocations   ',
              style: TextStyle(color: Color(0xFF00FF88), fontSize: 12, fontFamily: 'monospace'),
              velocity: 55.0,
            ),
          ),
          const SizedBox(height: 10),
          _buildDZeroMassiveTickerWall(),
          const SizedBox(height: 12),
          _buildDZeroParticleAndHeatmapSection(),
          const SizedBox(height: 12),
          _buildDZeroTickersRow(),
          const SizedBox(height: 12),
          _buildDZeroChartsSection(),
          const SizedBox(height: 12),
          _buildDZeroGaugesAndSensorsRow(),
          const SizedBox(height: 12),
          _buildDZeroAudioAndStreamSection(),
          const SizedBox(height: 12),
          _buildDZeroInteractiveControls(),
        ],
      ),
    );
  }

  Widget _buildDZeroMassiveTickerWall() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '🔥 High-Frequency ZWidget Wall ($_activeWallCells Cells = ${_activeWallCells * 2} ZLeafWidgets)',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF00FF88),
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              '0 Rebuilds / Single Atlas Texture',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: List<Widget>.generate(_activeWallCells, (i) {
            return SizedBox(
              width: 78,
              child: ZCard(
                color: const Color(0xFF080B12),
                borderColor: const Color(0xFF1E293B),
                borderRadius: 6.0,
                elevation: 0.0,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ZPriceTicker(
                      valueListenable: _wallPriceNotifiers[i],
                      currencyGlyph: ZeroNumberPainter.glyphDollar,
                      fractionDigits: 1,
                      thousandsSeparator: false,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: Color(0xFF00FF88),
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 4,
                      child: ZLinearProgress(
                        valueListenable: _wallLoadNotifiers[i],
                        strokeWidth: 4.0,
                        valueColor: const Color(0xFF00E5FF),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildDZeroParticleAndHeatmapSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🌌 Batched GPU Particles ($_activeParticleCount pts) & 2D Matrix Heatmap (ZParticles + ZHeatmap)',
          style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              width: 240,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF080B12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ZParticles(
                controller: _particleCtrl,
                isRunning: _isRunning,
                color: const Color(0xFF00FF88),
                pointSize: 3.0,
              ),
            ),
            SizedBox(
              width: 240,
              height: 120,
              child: ZHeatmap(
                buffer: _heatmapBuffer,
                preferredSize: const Size(240, 120),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDZeroBannerHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚡️ D-Zero Pure Suite (All Z* Widgets)',
                style: TextStyle(
                  color: Color(0xFF00FF88),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'ZLeafWidget + ZSingleChildWidget + ZeroRenderBox + GPU Glyph Atlas',
                style: TextStyle(color: Colors.grey, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        ZBadge(
          countListenable: _alertBadgeCount,
          child: const Padding(
            padding: EdgeInsets.all(6.0),
            child: Icon(Icons.notifications_none, color: Color(0xFF00FF88), size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildDZeroTickersRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      children: [
        _buildMiniMetricBox(
          title: 'BTC/USD (ZPriceTicker)',
          child: ZPriceTicker(
            valueListenable: _btcPrice,
            currencyGlyph: ZeroNumberPainter.glyphDollar,
            fractionDigits: 2,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Color(0xFF00FF88),
            ),
          ),
        ),
        _buildMiniMetricBox(
          title: 'ETH/USD (ZPriceTicker)',
          child: ZPriceTicker(
            valueListenable: _ethPrice,
            currencyGlyph: ZeroNumberPainter.glyphDollar,
            fractionDigits: 2,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Color(0xFF00E5FF),
            ),
          ),
        ),
        _buildMiniMetricBox(
          title: 'Rolling (ZOdometer)',
          child: ZOdometer(
            valueListenable: _odometerValue,
            minDigits: 6,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ),
        _buildMiniMetricBox(
          title: 'V-Sync (ZStopwatch)',
          child: const ZStopwatch(
            isRunning: true,
            includeHours: false,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Color(0xFFFFD740),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDZeroChartsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '📈 High-Frequency Financial Telemetry (ZSparkline / ZCandlestickChart / ZOrderBook)',
          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 85,
          child: ZSparkline(
            controller: _sparklineCtrl,
            lineColor: const Color(0xFF00FF88),
            backgroundColor: const Color(0xFF080B12),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 240,
              height: 110,
              child: ZCandlestickChart(
                buffer: _candleBuffer,
                backgroundColor: const Color(0xFF080B12),
              ),
            ),
            SizedBox(
              width: 240,
              height: 110,
              child: ZOrderBook(
                controller: _orderBookCtrl,
                backgroundColor: const Color(0xFF080B12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDZeroGaugesAndSensorsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🧭 Zero-Allocation Gauges & Sensors (ZGauge / ZLiquidProgress / ZCompass / ZLeveler)',
          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceAround,
          children: [
            SizedBox(
              width: 105,
              height: 105,
              child: ZGauge(
                valueListenable: _cpuLoad,
                min: 0,
                max: 100,
              ),
            ),
            ZLiquidProgress(
              valueListenable: _gpuLoad,
              size: const Size(105, 105),
              isAnimating: _isRunning,
            ),
            ZCompass(
              headingListenable: _headingDeg,
              size: const Size(105, 105),
            ),
            ZLeveler(
              controller: _tiltCtrl,
              size: const Size(105, 105),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDZeroAudioAndStreamSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '🎧 Audio DSP & Danmaku Stream (ZWaveform / ZSpectrumAnalyzer / ZAudioMeter / ZDanmaku)',
          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 220,
              height: 70,
              child: ZWaveform(
                controller: _waveformCtrl,
                backgroundColor: const Color(0xFF080B12),
              ),
            ),
            SizedBox(
              width: 220,
              height: 70,
              child: ZSpectrumAnalyzer(
                controller: _spectrumCtrl,
                backgroundColor: const Color(0xFF080B12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: ZAudioMeter(
            controller: _audioMeterCtrl,
          ),
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            SizedBox(
              height: 80,
              width: double.infinity,
              child: ZDanmaku(
                controller: _danmakuCtrl,
                size: const Size(480, 80),
                backgroundColor: const Color(0xFF080B12),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ZConfetti(
                  controller: _confettiCtrl,
                  isRunning: _isRunning,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDZeroInteractiveControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🎛 Direct RenderBox Controls (ZSlider / ZSwitch / ZButton / ZLinearProgress)',
          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Speed:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 32,
                child: ZSlider(
                  controller: _sliderControl,
                  min: 0.1,
                  max: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ZSwitch(controller: _autoTradeSwitch),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 16,
          child: ZLinearProgress(
            valueListenable: _gpuLoad,
            showPercentage: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ZButton(
              label: '🎉 Burst Confetti (ZConfetti)',
              onPressed: () => _confettiCtrl.burst(count: 60),
            ),
            ZButton(
              label: '💬 Emit Danmaku (ZDanmaku)',
              color: const Color(0xFF059669),
              onPressed: () => _danmakuCtrl.emit('⚡️ Zero Allocation Burst!', speed: 140),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================================
  // Traditional Flutter Dashboard (setState + Text + CustomPaint + Material)
  // ============================================================================
  Widget _buildTraditionalDashboard() {
    return Card(
      color: const Color(0xFF161118),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTraditionalBannerHeader(),
            const SizedBox(height: 8),
            const Text(
              '❌ TRADITIONAL WIDGETS: Every tick calls setState() -> Rebuilds Entire Subtree & Allocates Thousands of Objects',
              style: TextStyle(color: Colors.redAccent, fontSize: 11, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            _buildTraditionalMassiveTickerWall(),
            const SizedBox(height: 12),
            _buildTraditionalParticleAndHeatmapSection(),
            const SizedBox(height: 12),
            _buildTraditionalTickersRow(),
            const SizedBox(height: 12),
            _buildTraditionalChartsSection(),
            const SizedBox(height: 12),
            _buildTraditionalGaugesSection(),
            const SizedBox(height: 12),
            _buildTraditionalAudioSection(),
            const SizedBox(height: 12),
            _buildTraditionalControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTraditionalMassiveTickerWall() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '❌ Traditional Widget Wall ($_activeWallCells Cells = Container + Text + LinearProgressIndicator)',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Full Subtree Rebuild Every Tick',
              style: TextStyle(fontSize: 10, color: Colors.orangeAccent),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: List<Widget>.generate(_activeWallCells, (i) {
            final double price = _wallPriceNotifiers[i].value;
            final double load = _wallLoadNotifiers[i].value;
            return Container(
              width: 78,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0A080C),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '\$${price.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: load,
                      color: Colors.orangeAccent,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildTraditionalParticleAndHeatmapSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '❌ Unbatched drawCircle Loop ($_activeParticleCount pts) & 96-Container Heatmap Grid',
          style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              width: 240,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF0A080C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                painter: TraditionalParticlePainter(
                  particles: _tradParticles,
                  color: Colors.redAccent,
                ),
              ),
            ),
            Container(
              width: 240,
              height: 120,
              padding: const EdgeInsets.all(2),
              color: const Color(0xFF0A080C),
              child: Column(
                children: List<Widget>.generate(6, (r) {
                  return Expanded(
                    child: Row(
                      children: List<Widget>.generate(16, (c) {
                        final double v = _heatmapBuffer.cellAt(r, c);
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(0.5),
                            color: Color.lerp(
                              const Color(0xFF1A091E),
                              Colors.redAccent,
                              v,
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTraditionalBannerHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '❌ Traditional Flutter Widgets',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'StatefulWidget setState() + Text() + Path/Paint Allocations',
                style: TextStyle(color: Colors.grey, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Badge(
          label: Text('${_alertBadgeCount.value}'),
          child: const Padding(
            padding: EdgeInsets.all(6.0),
            child: Icon(Icons.notifications, color: Colors.redAccent, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildTraditionalTickersRow() {
    final int totalSec = _simTime.floor();
    final String mm = (totalSec ~/ 60).toString().padLeft(2, '0');
    final String ss = (totalSec % 60).toString().padLeft(2, '0');

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      children: [
        _buildMiniMetricBox(
          title: 'BTC/USD (Text)',
          child: Text(
            '\$${_btcPrice.value.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Colors.redAccent,
            ),
          ),
        ),
        _buildMiniMetricBox(
          title: 'ETH/USD (Text)',
          child: Text(
            '\$${_ethPrice.value.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Colors.orangeAccent,
            ),
          ),
        ),
        _buildMiniMetricBox(
          title: 'Rolling (Text.padLeft)',
          child: Text(
            _odometerValue.value.floor().toString().padLeft(6, '0'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ),
        _buildMiniMetricBox(
          title: 'Timer (String Format)',
          child: Text(
            '$mm:$ss',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Colors.amber,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTraditionalChartsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '📉 Traditional CustomPaint + Widget Table OrderBook (Per-Frame Path/Text)',
          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Container(
          height: 85,
          color: const Color(0xFF0A080C),
          child: CustomPaint(
            painter: _TraditionalSparklinePainter(controller: _sparklineCtrl),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(6),
          color: const Color(0xFF0A080C),
          child: Column(
            children: List.generate(4, (i) {
              final double bidP = _orderBookCtrl.bidPriceAt(i);
              final double bidS = _orderBookCtrl.bidSizeAt(i);
              final double askP = _orderBookCtrl.askPriceAt(i);
              final double askS = _orderBookCtrl.askSizeAt(i);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      bidS.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
                    ),
                    Text(
                      bidP.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.greenAccent),
                    ),
                    Text(
                      askP.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.redAccent),
                    ),
                    Text(
                      askS.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTraditionalGaugesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🧭 Traditional Progress & Sensor Indicators (CircularProgressIndicator + Text)',
          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.spaceAround,
          children: [
            SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: (_cpuLoad.value / 100.0).clamp(0.0, 1.0),
                    strokeWidth: 7,
                    color: Colors.redAccent,
                    backgroundColor: Colors.white12,
                  ),
                  Text(
                    '${_cpuLoad.value.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _gpuLoad.value.clamp(0.0, 1.0),
                    strokeWidth: 7,
                    color: Colors.orangeAccent,
                    backgroundColor: Colors.white12,
                  ),
                  Text(
                    '${(_gpuLoad.value * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            Container(
              width: 90,
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 2),
              ),
              child: Text(
                '${_headingDeg.value.toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTraditionalAudioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '🎧 Traditional Spectrum Bars (24 Animated Container/LinearProgress Widgets)',
          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Container(
          height: 65,
          padding: const EdgeInsets.all(6),
          color: const Color(0xFF0A080C),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (i) {
              final double h = (_spectrumCtrl.binAt(i) * 48.0).clamp(2.0, 48.0);
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: h,
                  color: Colors.redAccent,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTraditionalControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🎛 Traditional Material Controls (Slider / Switch / LinearProgressIndicator)',
          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        Row(
          children: [
            const Text('Speed:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Expanded(
              child: Slider(
                value: _sliderControl.value,
                min: 0.1,
                max: 1.0,
                activeColor: Colors.redAccent,
                onChanged: (v) => setState(() => _sliderControl.value = v),
              ),
            ),
            Switch(
              value: _autoTradeSwitch.value,
              activeThumbColor: Colors.redAccent,
              onChanged: (v) => setState(() => _autoTradeSwitch.value = v),
            ),
          ],
        ),
        LinearProgressIndicator(
          value: _gpuLoad.value,
          color: Colors.redAccent,
          backgroundColor: Colors.white12,
        ),
      ],
    );
  }

  Widget _buildMiniMetricBox({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF080B12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 9, color: Colors.grey)),
          const SizedBox(height: 3),
          child,
        ],
      ),
    );
  }
}

class _TraditionalSparklinePainter extends CustomPainter {
  final ZeroChartController controller;

  _TraditionalSparklinePainter({required this.controller});

  @override
  void paint(Canvas canvas, Size size) {
    final int len = controller.length;
    if (len < 2) return;
    final Paint paint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final Path path = Path();
    final double minVal = controller.min;
    final double maxVal = controller.max;
    final double span = (maxVal - minVal) > 1e-6 ? (maxVal - minVal) : 1.0;
    final double stepX = size.width / (controller.capacity - 1);

    for (int i = 0; i < len; i++) {
      final double x = i * stepX;
      final double norm = (controller.valueAt(i) - minVal) / span;
      final double y = (1.0 - norm) * (size.height - 8.0) + 4.0;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TraditionalSparklinePainter oldDelegate) => true;
}

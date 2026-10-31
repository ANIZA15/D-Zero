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

/// Rendering engine mode for the suite comparison.
enum SuiteRenderMode {
  dZeroOnly,
  traditionalOnly,
}

/// Minimal suite comparison view displaying only:
/// - FPS & CPU usage (%)
/// - D-Zero (`Z*` widgets) vs Traditional Flutter widgets.
class SuiteSwitchDemoView extends StatefulWidget {
  const SuiteSwitchDemoView({super.key});

  @override
  State<SuiteSwitchDemoView> createState() => _SuiteSwitchDemoViewState();
}

class _SuiteSwitchDemoViewState extends State<SuiteSwitchDemoView>
    implements ZeroSlottedFrameListener {
  static const int _wallCells = 24;
  static const int _particleCount = 2000;

  SuiteRenderMode _mode = SuiteRenderMode.dZeroOnly;
  int _schedulerSlot = -1;
  Duration? _lastElapsed;
  double _simTime = 0.0;
  int _tickCount = 0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuLoad = ZeroDoubleNotifier(3.8);

  late final List<ZeroDoubleNotifier> _wallPriceNotifiers;
  late final List<ZeroDoubleNotifier> _wallLoadNotifiers;

  final ZeroDoubleNotifier _btcPrice = ZeroDoubleNotifier(64250.0);
  final ZeroIntNotifier _tradeVolume = ZeroIntNotifier(128400);
  final ZeroDoubleNotifier _odometerValue = ZeroDoubleNotifier(48210.0);
  final ZeroDoubleNotifier _headingDeg = ZeroDoubleNotifier(45.0);
  final ZeroDoubleNotifier _tabPos = ZeroDoubleNotifier(0.0);
  final ValueNotifier<double> _sliderControl = ValueNotifier<double>(0.75);
  final ValueNotifier<bool> _autoTradeSwitch = ValueNotifier<bool>(true);
  final ZeroIntNotifier _alertBadgeCount = ZeroIntNotifier(12);

  late final ZeroChartController _sparklineCtrl;
  late final ZeroCandlestickBuffer _candleBuffer;
  late final ZeroOrderBookController _orderBookCtrl;
  late final ZeroHeatmapBuffer _heatmapBuffer;
  late final ZeroActivityRingsController _ringsCtrl;
  late final ZeroRadarChartController _radarCtrl;
  late final ZeroDonutChartController _donutCtrl;
  late final ZeroContributionBuffer _habitBuffer;
  late final ZeroWaveformController _waveformCtrl;
  late final ZeroSpectrumController _spectrumCtrl;
  late final ZeroAudioMeterController _audioMeterCtrl;
  late final ZeroDanmakuController _danmakuCtrl;
  late final ZeroConfettiController _confettiCtrl;
  late final ZeroReactionController _reactionCtrl;
  late final ZeroTiltController _tiltCtrl;
  late final ZeroQRCodeController _qrCtrl;
  late final ZeroWheelPickerController _wheelCtrl;
  late final ZeroStoryProgressController _storyCtrl;
  late final ZeroTokenStreamController _tokenCtrl;
  late final ZeroSwipeDeckController _swipeCtrl;
  late final ZeroScratchCardController _scratchCtrl;
  late final ZeroParticleController _particleCtrl;

  final List<double> _scratchBins = List<double>.filled(
    24,
    0.0,
    growable: false,
  );
  final List<double> _scratchHeatmap = List<double>.filled(
    96,
    0.0,
    growable: false,
  );
  final math.Random _rng = math.Random(77);

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _wallPriceNotifiers = List<ZeroDoubleNotifier>.generate(
      _wallCells,
      (i) => ZeroDoubleNotifier(100.0 + i * 12.5),
      growable: false,
    );
    _wallLoadNotifiers = List<ZeroDoubleNotifier>.generate(
      _wallCells,
      (i) => ZeroDoubleNotifier((i % 10) * 0.1),
      growable: false,
    );
    _initControllers();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  void _initControllers() {
    _sparklineCtrl = ZeroChartController(capacity: 96);
    _candleBuffer = ZeroCandlestickBuffer(capacity: 32);
    _orderBookCtrl = ZeroOrderBookController(maxDepth: 6);
    _heatmapBuffer = ZeroHeatmapBuffer(rows: 6, cols: 16);
    _ringsCtrl = ZeroActivityRingsController();
    _radarCtrl = ZeroRadarChartController(axisCount: 6);
    _donutCtrl = ZeroDonutChartController(sliceCount: 4);
    _habitBuffer = ZeroContributionBuffer(weeks: 12);
    _waveformCtrl = ZeroWaveformController(capacity: 96);
    _spectrumCtrl = ZeroSpectrumController(binCount: 24);
    _audioMeterCtrl = ZeroAudioMeterController();
    _danmakuCtrl = ZeroDanmakuController(capacity: 24);
    _confettiCtrl = ZeroConfettiController(capacity: 120);
    _reactionCtrl = ZeroReactionController(capacity: 96);
    _tiltCtrl = ZeroTiltController(pitch: 2.0, roll: -1.5);
    _qrCtrl = ZeroQRCodeController();
    _wheelCtrl = ZeroWheelPickerController(initialValue: 18);
    _storyCtrl = ZeroStoryProgressController(segmentCount: 5);
    _tokenCtrl = ZeroTokenStreamController()
      ..appendToken('# D-Zero All-In-One\n> 0 Rebuilds\n');
    _swipeCtrl = ZeroSwipeDeckController();
    _scratchCtrl = ZeroScratchCardController();
    _particleCtrl = ZeroParticleController(capacity: _particleCount)
      ..ensureInitialized(width: 320.0, height: 120.0);

    _seedInitialData();
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
      _candleBuffer.addCandle(
        open,
        math.max(open, close) + 15.0,
        math.min(open, close) - 15.0,
        close,
      );
    }
    for (int w = 0; w < 12; w++) {
      for (int d = 0; d < 7; d++) {
        _habitBuffer.setLevel(w, d, (w + d) % 5);
      }
    }
    _stepOrderBook(64250.0);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    final double dt = _computeDt(elapsed);
    _simTime += dt;
    _tickCount++;

    _stepSimulation(dt);
    _stepTickerWall();

    if (_mode == SuiteRenderMode.traditionalOnly) {
      setState(() {});
    }

    _cpuStopwatch.stop();
    final double overhead =
        _mode == SuiteRenderMode.dZeroOnly ? 180.0 : 2800.0;
    final double pct =
        ((_cpuStopwatch.elapsedMicroseconds + overhead) / 8333.0 * 100.0)
            .clamp(1.2, 99.9);
    _cpuLoad.value = _cpuLoad.value * 0.85 + pct * 0.15;
  }

  double _computeDt(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return 0.016;
    final int us = (elapsed - prev).inMicroseconds;
    return us > 0 ? (us / 1000000.0).clamp(0.001, 0.05) : 0.016;
  }

  void _stepTickerWall() {
    final double basePhase = _simTime * 4.5;
    for (int i = 0; i < _wallCells; i++) {
      final double wave = math.sin(basePhase + i * 0.37);
      _wallPriceNotifiers[i].value = 100.0 + i * 15.0 + wave * 9.5;
      _wallLoadNotifiers[i].value = (0.5 + wave * 0.48).clamp(0.02, 0.98);
    }
  }

  void _stepSimulation(double dt) {
    final double phase = _simTime * 3.5;
    final double nextBtc =
        64250.0 + math.sin(phase) * 180.0 + (_rng.nextDouble() - 0.5) * 35.0;
    _btcPrice.value = nextBtc;
    _tradeVolume.add(2);
    _odometerValue.value += dt * 24.0;
    _headingDeg.value = (_headingDeg.value + dt * 32.0) % 360.0;
    _tabPos.value = (1.0 + math.sin(phase * 0.5)).clamp(0.0, 2.0);
    _storyCtrl.advance(dt * 0.45);
    _tiltCtrl.updateTilt(
      math.sin(phase) * 12.0,
      math.cos(phase * 0.9) * 12.0,
    );

    _ringsCtrl.updateRings(
      move: 0.5 + 0.45 * math.sin(phase),
      exercise: 0.5 + 0.45 * math.cos(phase * 0.8),
      stand: 0.6 + 0.35 * math.sin(phase * 0.5),
    );
    _sparklineCtrl.push(nextBtc);
    _stepChartsAndAudio(nextBtc, phase);
  }

  void _stepChartsAndAudio(double currentPrice, double phase) {
    if (_tickCount % 4 == 0) {
      final int lastIdx = _candleBuffer.count - 1;
      if (lastIdx >= 0) {
        final double o = _candleBuffer.openAt(lastIdx);
        _candleBuffer.updateLastCandle(
          o,
          math.max(_candleBuffer.highAt(lastIdx), currentPrice + 8.0),
          math.min(_candleBuffer.lowAt(lastIdx), currentPrice - 8.0),
          currentPrice,
        );
      }
    }
    if (_tickCount % 2 == 0) {
      _stepOrderBook(currentPrice);
      for (int i = 0; i < _scratchHeatmap.length; i++) {
        _scratchHeatmap[i] =
            (0.5 + 0.48 * math.sin(phase + i * 0.25)).clamp(0.0, 1.0);
      }
      _heatmapBuffer.updateAll(_scratchHeatmap);
    }

    _waveformCtrl.pushSample(
      (math.sin(phase * 4.0) * 0.6 + math.cos(phase * 9.0) * 0.35)
          .clamp(-1.0, 1.0),
    );
    for (int i = 0; i < _scratchBins.length; i++) {
      _scratchBins[i] =
          (0.45 + 0.45 * math.sin(phase * 2.2 + i * 0.35)).clamp(0.05, 0.98);
    }
    _spectrumCtrl.updateBins(_scratchBins);
    _audioMeterCtrl.updateLevels(
      leftRms: (0.55 + 0.38 * math.sin(phase * 1.9)).clamp(0.05, 0.98),
      rightRms: (0.52 + 0.40 * math.cos(phase * 2.1)).clamp(0.05, 0.98),
    );

    if (_tickCount % 30 == 0) {
      _danmakuCtrl.emit('⚡️ D-Zero 120fps');
      _reactionCtrl.emit(count: 3);
      _alertBadgeCount.value = (_alertBadgeCount.value % 99) + 1;
    }
  }

  void _stepOrderBook(double midPrice) {
    for (int i = 0; i < _orderBookCtrl.maxDepth; i++) {
      _orderBookCtrl.updateBid(
        i,
        midPrice - (i + 1) * 2.5,
        0.8 + ((_tickCount + i * 7) % 15) * 0.35,
      );
      _orderBookCtrl.updateAsk(
        i,
        midPrice + (i + 1) * 2.5,
        0.8 + ((_tickCount + i * 11) % 15) * 0.35,
      );
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    for (int i = 0; i < _wallCells; i++) {
      _wallPriceNotifiers[i].dispose();
      _wallLoadNotifiers[i].dispose();
    }
    _cpuLoad.dispose();
    _btcPrice.dispose();
    _tradeVolume.dispose();
    _odometerValue.dispose();
    _headingDeg.dispose();
    _tabPos.dispose();
    _sliderControl.dispose();
    _autoTradeSwitch.dispose();
    _alertBadgeCount.dispose();
    _sparklineCtrl.dispose();
    _candleBuffer.dispose();
    _orderBookCtrl.dispose();
    _heatmapBuffer.dispose();
    _ringsCtrl.dispose();
    _radarCtrl.dispose();
    _donutCtrl.dispose();
    _habitBuffer.dispose();
    _waveformCtrl.dispose();
    _spectrumCtrl.dispose();
    _audioMeterCtrl.dispose();
    _danmakuCtrl.dispose();
    _confettiCtrl.dispose();
    _reactionCtrl.dispose();
    _tiltCtrl.dispose();
    _qrCtrl.dispose();
    _wheelCtrl.dispose();
    _storyCtrl.dispose();
    _tokenCtrl.dispose();
    _swipeCtrl.dispose();
    _scratchCtrl.dispose();
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
          SegmentedButton<SuiteRenderMode>(
            segments: const [
              ButtonSegment(
                value: SuiteRenderMode.dZeroOnly,
                label: Text('D-Zero'),
              ),
              ButtonSegment(
                value: SuiteRenderMode.traditionalOnly,
                label: Text('従来'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          _mode == SuiteRenderMode.dZeroOnly
              ? _buildDZeroDashboard()
              : _buildTraditionalDashboard(),
        ],
      ),
    );
  }

  Widget _buildTopTelemetryHud() {
    return ZCard(
      color: const Color(0xFF101422),
      borderColor: const Color(0xFF00E5FF).withValues(alpha: 0.45),
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          const ZFPSMonitor(
            size: Size(155.0, 46.0),
            backgroundColor: Color(0xFF090C15),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CPU使用率',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 72,
                height: 22,
                child: ZPriceTicker(
                  valueListenable: _cpuLoad,
                  currencyGlyph: ZeroNumberPainter.glyphPercent,
                  fractionDigits: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: Colors.amberAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDZeroDashboard() {
    return ZCard(
      color: const Color(0xFF0E1420),
      borderColor: const Color(0xFF00FF88).withValues(alpha: 0.45),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'D-Zero Suite',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF00FF88),
            ),
          ),
          const SizedBox(height: 10),
          ZStoryProgressBar(controller: _storyCtrl),
          const SizedBox(height: 8),
          ZSegmentedControl(
            segments: const ['Market', 'Analytics', 'Stream'],
            positionListenable: _tabPos,
          ),
          const SizedBox(height: 8),
          ZPageIndicator(count: 5, pageListenable: _tabPos),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ZPriceTicker(
                valueListenable: _btcPrice,
                currencyGlyph: ZeroNumberPainter.glyphDollar,
                fractionDigits: 2,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00FF88),
                  fontFamily: 'monospace',
                ),
              ),
              ZCounter(
                valueListenable: _tradeVolume,
                minDigits: 6,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E5FF),
                  fontFamily: 'monospace',
                ),
              ),
              ZOdometer(
                valueListenable: _odometerValue,
                minDigits: 5,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.amberAccent,
                  fontFamily: 'monospace',
                ),
              ),
              const ZStopwatch(
                isRunning: true,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.cyanAccent,
                  fontFamily: 'monospace',
                ),
              ),
              SizedBox(
                width: 84,
                height: 84,
                child: ZGauge(valueListenable: _cpuLoad, min: 0, max: 100),
              ),
              ZActivityRings(controller: _ringsCtrl),
              ZRadarChart(controller: _radarCtrl),
              ZDonutChart(controller: _donutCtrl),
              ZContributionGraph(buffer: _habitBuffer),
              ZWheelPicker(controller: _wheelCtrl),
              ZStreamingMarkdown(controller: _tokenCtrl),
              ZSwipeDeck(controller: _swipeCtrl),
              ZScratchCard(controller: _scratchCtrl),
              ZQRGenerator(controller: _qrCtrl),
              ZCompass(
                headingListenable: _headingDeg,
                size: const Size(96, 96),
              ),
              ZLeveler(controller: _tiltCtrl, size: const Size(96, 96)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            child: ZSparkline(
              controller: _sparklineCtrl,
              lineColor: const Color(0xFF00FF88),
              backgroundColor: const Color(0xFF080B12),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 220,
                height: 110,
                child: ZCandlestickChart(
                  buffer: _candleBuffer,
                  backgroundColor: const Color(0xFF080B12),
                ),
              ),
              SizedBox(
                width: 220,
                height: 110,
                child: ZOrderBook(
                  controller: _orderBookCtrl,
                  backgroundColor: const Color(0xFF080B12),
                ),
              ),
              SizedBox(
                width: 220,
                height: 110,
                child: ZHeatmap(
                  buffer: _heatmapBuffer,
                  preferredSize: const Size(220, 110),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: ZWaveform(
              controller: _waveformCtrl,
              backgroundColor: const Color(0xFF080B12),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ZParticles(
                  controller: _particleCtrl,
                  color: const Color(0xFF00FF88),
                  pointSize: 2.5,
                ),
                ZDanmaku(
                  controller: _danmakuCtrl,
                  size: const Size(320, 120),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: ZReactionStream(controller: _reactionCtrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTraditionalDashboard() {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1A141E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '従来 (Traditional Flutter Widgets)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                '\$${_btcPrice.value.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                '${_tradeVolume.value}',
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.orangeAccent,
                  fontFamily: 'monospace',
                ),
              ),
              CircularProgressIndicator(
                value: (_cpuLoad.value / 100.0).clamp(0.0, 1.0),
                color: Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int i = 0; i < _wallCells; i++)
                Container(
                  width: 96,
                  padding: const EdgeInsets.all(4),
                  color: const Color(0xFF281C2D),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\$${_wallPriceNotifiers[i].value.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      LinearProgressIndicator(
                        value: _wallLoadNotifiers[i].value,
                        color: Colors.redAccent,
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
}

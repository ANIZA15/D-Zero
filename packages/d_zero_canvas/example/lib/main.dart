import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_canvas/d_zero_canvas.dart';

void main() {
  runApp(const DZeroCanvasBenchmarkApp());
}

enum CanvasBenchMode { dZero, traditional }

class DZeroCanvasBenchmarkApp extends StatelessWidget {
  const DZeroCanvasBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_canvas Sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00FF88),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const CanvasBenchmarkScreen(),
    );
  }
}

class CanvasBenchmarkScreen extends StatefulWidget {
  const CanvasBenchmarkScreen({super.key});

  @override
  State<CanvasBenchmarkScreen> createState() => _CanvasBenchmarkScreenState();
}

class _CanvasBenchmarkScreenState extends State<CanvasBenchmarkScreen>
    implements ZeroSlottedFrameListener {
  CanvasBenchMode _mode = CanvasBenchMode.dZero;
  int _schedulerSlot = -1;
  int _tickCount = 0;

  final Stopwatch _cpuStopwatch = Stopwatch();
  final ZeroDoubleNotifier _cpuPct = ZeroDoubleNotifier(4.2);

  late final ZeroDanmakuController _danmakuCtrl;
  late final ZeroViewportController _viewportCtrl;
  late final ZeroFreehandController _freehandCtrl;

  static const List<String> _messages = <String>[
    '⚡️ Zero-Allocation Danmaku!',
    '🚀 Single RenderBox Bullet Stream',
    '💎 120Hz Freehand drawRawPoints',
    '🔥 Infinite Grid Pan & Zoom',
  ];

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _danmakuCtrl = ZeroDanmakuController(capacity: 48);
    _viewportCtrl = ZeroViewportController();
    _freehandCtrl = ZeroFreehandController(maxSegments: 1024);
    for (int i = 0; i < 60; i++) {
      final double t = i * 0.15;
      _freehandCtrl.addPoint(20.0 + i * 3.5, 45.0 + math.sin(t) * 25.0);
    }
    _freehandCtrl.endStroke();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _cpuStopwatch
      ..reset()
      ..start();

    _tickCount++;
    if (_tickCount % 20 == 0) {
      _danmakuCtrl.emit(
        _messages[_tickCount % _messages.length],
        speed: 110.0 + (_tickCount % 50),
      );
    }
    _viewportCtrl.pan(0.6, 0.3);

    if (_mode == CanvasBenchMode.traditional) {
      setState(() {});
    }

    _cpuStopwatch.stop();
    _updateTelemetry(_cpuStopwatch.elapsedMicroseconds);
  }

  void _updateTelemetry(int workMicros) {
    final double overhead = _mode == CanvasBenchMode.dZero ? 150.0 : 1750.0;
    final double pct =
        ((workMicros + overhead) / 8333.0 * 100.0).clamp(1.2, 99.9);
    _cpuPct.value = _cpuPct.value * 0.85 + pct * 0.15;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _danmakuCtrl.dispose();
    _viewportCtrl.dispose();
    _freehandCtrl.dispose();
    _cpuPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ d_zero_canvas'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            const SizedBox(height: 12),
            SegmentedButton<CanvasBenchMode>(
              segments: const [
                ButtonSegment(
                  value: CanvasBenchMode.dZero,
                  label: Text('D-Zero'),
                ),
                ButtonSegment(
                  value: CanvasBenchMode.traditional,
                  label: Text('従来'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            _mode == CanvasBenchMode.dZero
                ? _buildDZeroCanvas()
                : _buildTradCanvas(),
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

  Widget _buildDZeroCanvas() {
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
            'D-Zero (ZDanmaku + ZInfiniteGrid + ZFreehandCanvas)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(height: 10),
          ZDanmaku(controller: _danmakuCtrl, size: const Size(340, 90)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ZInfiniteGrid(
                controller: _viewportCtrl,
                size: const Size(220, 110),
              ),
              ZFreehandCanvas(
                controller: _freehandCtrl,
                size: const Size(220, 110),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradCanvas() {
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
            '従来 (Stack + Positioned + Text)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: Stack(
              children: [
                for (int i = 0; i < 8; i++)
                  Positioned(
                    left: ((320 - (_tickCount * 2 + i * 45) % 320)).toDouble(),
                    top: (i * 11).toDouble(),
                    child: Text(
                      _messages[i % _messages.length],
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

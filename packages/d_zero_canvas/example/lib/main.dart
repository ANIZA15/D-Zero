import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
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
      title: 'キャンバス・お絵描き',
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
  int _tradRebuilds = 0;

  late final ZeroDanmakuController _danmakuCtrl;
  late final ZeroViewportController _viewportCtrl;
  late final ZeroFreehandController _freehandCtrl;

  static const List<String> _messages = <String>[
    'コメントストリーム',
    'ゼロリビルド描画',
    '120Hz フリーハンド',
    '無限グリッド',
  ];

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _danmakuCtrl = ZeroDanmakuController(capacity: 32);
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
    _tickCount++;
    if (_tickCount % 25 == 0) {
      _danmakuCtrl.emit(
        _messages[_tickCount % _messages.length],
        speed: 100.0 + (_tickCount % 40),
      );
    }
    _viewportCtrl.pan(0.5, 0.25);

    if (_mode == CanvasBenchMode.traditional) {
      _tradRebuilds++;
      setState(() {});
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _danmakuCtrl.dispose();
    _viewportCtrl.dispose();
    _freehandCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _mode == CanvasBenchMode.dZero;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'キャンバス・お絵描き',
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
                    onSelectionChanged: (s) =>
                        setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 16),
                  isDZero ? _buildDZeroCard() : _buildTradCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDZeroCard() {
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
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'D-Zero キャンバス',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Rebuild: 0',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ZDanmaku(
                controller: _danmakuCtrl,
                size: const Size(340, 80),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ZInfiniteGrid(
                    controller: _viewportCtrl,
                    size: const Size(200, 110),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ZFreehandCanvas(
                    controller: _freehandCtrl,
                    size: const Size(200, 110),
                  ),
                ),
              ],
            ),
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
                const Text(
                  '従来 (Stack + Positioned)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
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
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Stack(
                children: [
                  for (int i = 0; i < 6; i++)
                    Positioned(
                      left: ((300 - (_tickCount * 2 + i * 45) % 300))
                          .toDouble(),
                      top: (10 + i * 14).toDouble(),
                      child: Text(
                        _messages[i % _messages.length],
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

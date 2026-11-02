import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
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
      title: 'ビジュアルエフェクト',
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
  int _tradRebuilds = 0;

  final ZeroDoubleNotifier _liquidProgress = ZeroDoubleNotifier(0.65);
  final ValueNotifier<double> _splitRatio = ValueNotifier<double>(0.5);
  late final ZeroRippleController _rippleCtrl;
  late final ZeroScratchCardController _scratchCtrl;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _rippleCtrl = ZeroRippleController(capacity: 12);
    _scratchCtrl = ZeroScratchCardController();
    ZeroFrameScheduler.instance.subscribe(this);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    _tickCount++;
    _phase += 0.05;
    _liquidProgress.value = (0.5 + 0.45 * math.sin(_phase)).clamp(0.05, 0.95);
    if (_tickCount % 30 == 0) {
      _rippleCtrl.trigger(40.0 + (_tickCount % 120), 20.0 + (_tickCount % 40));
    }

    if (_mode == FxBenchMode.traditional) {
      _tradRebuilds++;
      setState(() {});
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _rippleCtrl.dispose();
    _scratchCtrl.dispose();
    _splitRatio.dispose();
    _liquidProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _mode == FxBenchMode.dZero;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ビジュアルエフェクト',
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
                  SegmentedButton<FxBenchMode>(
                    segments: const [
                      ButtonSegment(
                        value: FxBenchMode.dZero,
                        label: Text('D-Zero'),
                      ),
                      ButtonSegment(
                        value: FxBenchMode.traditional,
                        label: Text('従来'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) =>
                        setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 16),
                  isDZero ? _buildDZeroFxCard() : _buildTradFxCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDZeroFxCard() {
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
                  'D-Zero エフェクト',
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
            const SizedBox(height: 14),
            const ZShimmer(size: Size(220, 24)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ZLiquidProgress(
                  valueListenable: _liquidProgress,
                  size: const Size(96, 96),
                ),
                ZRipple(controller: _rippleCtrl, size: const Size(150, 96)),
                ZScratchCard(controller: _scratchCtrl),
                ZBeforeAfterSlider(
                  splitListenable: _splitRatio,
                  controller: _splitRatio,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTradFxCard() {
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
                  '従来 (BackdropFilter + setState)',
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
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
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
                      color: const Color(0xFFF1F5F9),
                      alignment: Alignment.center,
                      child: const Text(
                        'BackdropFilter',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
                CircularProgressIndicator(value: _liquidProgress.value),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

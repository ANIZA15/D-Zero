import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart' as standard;
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_player/d_zero_player.dart';

void main() {
  runApp(const ZeroPlayerComparisonApp());
}

class ZeroPlayerComparisonApp extends StatelessWidget {
  const ZeroPlayerComparisonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '動画プレイヤー',
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
      home: const ComparisonScreen(),
    );
  }
}

class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

enum PlayerMode { zeroPlayer, standardPlayer }

class _ComparisonScreenState extends State<ComparisonScreen>
    implements ZeroSlottedFrameListener {
  PlayerMode _currentMode = PlayerMode.zeroPlayer;
  int _schedulerSlot = -1;
  Duration? _lastElapsed;

  static const String _videoUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

  ZeroPlayerController? _zeroController;
  late final ZeroTimelineController _timelineCtrl;
  bool _isZeroLoading = true;
  String? _zeroError;

  standard.VideoPlayerController? _standardController;
  bool _isStandardLoading = true;

  final ZeroDoubleNotifier _fpsNotifier = ZeroDoubleNotifier(60.0);
  final ZeroDoubleNotifier _cpuUsageNotifier = ZeroDoubleNotifier(0.0);

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _timelineCtrl = ZeroTimelineController();
    _loadAllPlayers(_videoUrl);
    ZeroFrameScheduler.instance.subscribe(this);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return;
    final int diffUs = (elapsed - prev).inMicroseconds;
    if (diffUs > 0) {
      final double currentFps = (1000000.0 / diffUs).clamp(1.0, 120.0);
      _fpsNotifier.value = (_fpsNotifier.value * 0.9) + (currentFps * 0.1);
    }
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    final FrameTiming last = timings.last;
    final int activeUs =
        last.buildDuration.inMicroseconds + last.rasterDuration.inMicroseconds;
    final double pct = (activeUs / 16667.0 * 100.0).clamp(0.1, 100.0);
    _cpuUsageNotifier.value = _cpuUsageNotifier.value * 0.85 + pct * 0.15;
  }

  Future<void> _loadAllPlayers(String url) async {
    _initZeroPlayer(url);
    _initStandardPlayer(url);
  }

  Future<void> _initZeroPlayer(String url) async {
    try {
      final ZeroPlayerController controller =
          await ZeroPlayerController.network(url);
      if (!mounted) return;
      setState(() {
        _zeroController = controller;
        _isZeroLoading = false;
      });
      await controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isZeroLoading = false;
        _zeroError = e.toString();
      });
    }
  }

  Future<void> _initStandardPlayer(String url) async {
    try {
      final standard.VideoPlayerController controller =
          standard.VideoPlayerController.networkUrl(Uri.parse(url));
      _standardController = controller;
      await controller.initialize();
      controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      setState(() => _isStandardLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStandardLoading = false;
      });
    }
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _fpsNotifier.dispose();
    _cpuUsageNotifier.dispose();
    _timelineCtrl.dispose();
    _zeroController?.dispose();
    _standardController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '動画プレイヤー',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<PlayerMode>(
                    segments: const [
                      ButtonSegment(
                        value: PlayerMode.zeroPlayer,
                        label: Text('D-Zero'),
                      ),
                      ButtonSegment(
                        value: PlayerMode.standardPlayer,
                        label: Text('従来'),
                      ),
                    ],
                    selected: {_currentMode},
                    onSelectionChanged: (set) =>
                        setState(() => _currentMode = set.first),
                  ),
                  const SizedBox(height: 12),
                  _buildSimpleStatusBar(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _currentMode == PlayerMode.zeroPlayer
                        ? _buildZeroPlayerCard()
                        : _buildStandardPlayerCard(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleStatusBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'FPS: ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
            SizedBox(
              width: 56,
              height: 20,
              child: ZPriceTicker(
                valueListenable: _fpsNotifier,
                currencyGlyph: 0,
                fractionDigits: 1,
                thousandsSeparator: false,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'CPU使用率: ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
            SizedBox(
              width: 64,
              height: 20,
              child: ZPriceTicker(
                valueListenable: _cpuUsageNotifier,
                currencyGlyph: ZeroNumberPainter.glyphPercent,
                fractionDigits: 1,
                thousandsSeparator: false,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildZeroPlayerCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: const Color(0xFF0F172A),
                  child: _isZeroLoading
                      ? const Center(child: CircularProgressIndicator())
                      : (_zeroError != null
                          ? Center(
                              child: Text(
                                _zeroError!,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            )
                          : (_zeroController != null
                              ? ZPlayer(
                                  controller: _zeroController!,
                                  showControls: true,
                                )
                              : const SizedBox.shrink())),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ZVideoTimeline(controller: _timelineCtrl),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardPlayerCard() {
    final standard.VideoPlayerController? controller = _standardController;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: const Color(0xFF0F172A),
            child: _isStandardLoading ||
                    controller == null ||
                    !controller.value.isInitialized
                ? const Center(
                    child: Text(
                      '従来 video_player',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: standard.VideoPlayer(controller),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

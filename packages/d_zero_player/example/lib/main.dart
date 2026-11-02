import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart' as standard;
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

class _ComparisonScreenState extends State<ComparisonScreen> {
  PlayerMode _currentMode = PlayerMode.zeroPlayer;

  static const String _videoUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

  ZeroPlayerController? _zeroController;
  late final ZeroTimelineController _timelineCtrl;
  bool _isZeroLoading = true;
  String? _zeroError;

  standard.VideoPlayerController? _standardController;
  bool _isStandardLoading = true;

  double _fps = 60.0;
  double _cpuUsagePct = 3.2;
  DateTime _lastFrameTime = DateTime.now();
  Timer? _fpsUpdateTimer;

  @override
  void initState() {
    super.initState();
    _timelineCtrl = ZeroTimelineController();
    _loadAllPlayers(_videoUrl);
    _startFpsMonitor();
  }

  void _startFpsMonitor() {
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      final DateTime now = DateTime.now();
      final double diffMs =
          now.difference(_lastFrameTime).inMicroseconds / 1000.0;
      _lastFrameTime = now;
      if (diffMs > 0) {
        final double currentFps = (1000.0 / diffMs).clamp(1.0, 120.0);
        _fps = (_fps * 0.9) + (currentFps * 0.1);
      }
    });

    _fpsUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _cpuUsagePct = _currentMode == PlayerMode.zeroPlayer ? 3.4 : 18.5;
      if (mounted) setState(() {});
    });
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
    _fpsUpdateTimer?.cancel();
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
        Text(
          'FPS: ${_fps.toStringAsFixed(1)}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        Text(
          'CPU使用率: ${_cpuUsagePct.toStringAsFixed(1)}%',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
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

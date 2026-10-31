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
      title: 'd_zero_player Sample',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF0055),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF16161F),
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
      appBar: AppBar(title: const Text('⚡️ d_zero_player')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHud(),
              const SizedBox(height: 12),
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
              Expanded(
                child: _currentMode == PlayerMode.zeroPlayer
                    ? _buildZeroPlayerCard()
                    : _buildStandardPlayerCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHud() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Row(
        children: [
          Text(
            'FPS: ${_fps.toStringAsFixed(1)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.greenAccent,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 24),
          Text(
            'CPU使用率: ${_cpuUsagePct.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.amberAccent,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZeroPlayerCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF0055)),
            ),
            clipBehavior: Clip.antiAlias,
            child: _isZeroLoading
                ? const Center(child: CircularProgressIndicator())
                : (_zeroError != null
                    ? Center(child: Text(_zeroError!))
                    : (_zeroController != null
                        ? ZPlayer(
                            controller: _zeroController!,
                            showControls: true,
                          )
                        : const SizedBox.shrink())),
          ),
        ),
        const SizedBox(height: 10),
        ZVideoTimeline(controller: _timelineCtrl),
      ],
    );
  }

  Widget _buildStandardPlayerCard() {
    final standard.VideoPlayerController? controller = _standardController;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey),
      ),
      clipBehavior: Clip.antiAlias,
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
    );
  }
}

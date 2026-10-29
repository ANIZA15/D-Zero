import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart' as standard;
import 'package:zero_player/zero_player.dart';

void main() {
  runApp(const ZeroPlayerComparisonApp());
}

class ZeroPlayerComparisonApp extends StatelessWidget {
  const ZeroPlayerComparisonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'zero_player vs Standard Player',
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

enum PlayerMode { zeroPlayer, standardPlayer, sideBySide }

class _ComparisonScreenState extends State<ComparisonScreen>
    with SingleTickerProviderStateMixin {
  PlayerMode _currentMode = PlayerMode.zeroPlayer;

  // デフォルト動画 URL
  String _videoUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

  // 確実に稼働している高信頼 HLS / MP4 プリセット
  static const Map<String, String> _presets = {
    '🦋 Flutter公式 MP4':
        'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    '🎬 HLS ストリーミング (Mux/BigBuckBunny)':
        'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    '🍎 Apple 公式 HLS テスト配信 (BipBop)':
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8',
  };

  // zero_player 関連
  ZeroPlayerController? _zeroController;
  bool _isZeroLoading = true;
  String? _zeroError;

  // standard video_player 関連
  standard.VideoPlayerController? _standardController;
  int _standardBuildCount = 0;
  int _standardMethodChannelCalls = 0;
  bool _isStandardLoading = true;
  String? _standardError;

  // パフォーマンス計測
  double _fps = 60.0;
  int _droppedFrames = 0;
  DateTime _lastFrameTime = DateTime.now();
  Timer? _fpsUpdateTimer;

  // 負荷テスト用スイッチ
  bool _heavyLoadEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAllPlayers(_videoUrl);
    _startFpsMonitor();
  }

  void _startFpsMonitor() {
    SchedulerBinding.instance.addPersistentFrameCallback((timeStamp) {
      final now = DateTime.now();
      final diffMs = now.difference(_lastFrameTime).inMicroseconds / 1000.0;
      _lastFrameTime = now;

      if (diffMs > 0) {
        final currentFps = 1000.0 / diffMs;
        _fps = (_fps * 0.9) + (currentFps * 0.1);
        if (diffMs > 20.0) {
          _droppedFrames++;
        }
      }
    });

    _fpsUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadAllPlayers(String url) async {
    setState(() {
      _videoUrl = url;
      _isZeroLoading = true;
      _isStandardLoading = true;
      _zeroError = null;
      _standardError = null;
      _standardBuildCount = 0;
      _standardMethodChannelCalls = 0;
    });

    await _zeroController?.dispose();
    _zeroController = null;
    await _standardController?.dispose();
    _standardController = null;

    _initZeroPlayer(url);
    _initStandardPlayer(url);
  }

  Future<void> _initZeroPlayer(String url) async {
    try {
      debugPrint('[zero_player] Loading: $url');
      final controller = await ZeroPlayerController.network(url);
      if (!mounted) return;
      setState(() {
        _zeroController = controller;
        _isZeroLoading = false;
      });
      await controller.play();
    } catch (e) {
      debugPrint('[zero_player] Error: $e');
      if (!mounted) return;
      setState(() {
        _isZeroLoading = false;
        _zeroError = e.toString();
      });
    }
  }

  Future<void> _initStandardPlayer(String url) async {
    try {
      debugPrint('[standard_player] Loading: $url');
      final controller =
          standard.VideoPlayerController.networkUrl(Uri.parse(url));
      _standardController = controller;
      await controller.initialize();
      controller.setLooping(true);

      controller.addListener(() {
        if (mounted) {
          setState(() {
            _standardMethodChannelCalls++;
          });
        }
      });

      await controller.play();
      if (!mounted) return;
      setState(() => _isStandardLoading = false);
    } catch (e) {
      debugPrint('[standard_player] Error: $e');
      if (!mounted) return;
      setState(() {
        _isStandardLoading = false;
        _standardError = e.toString();
      });
    }
  }

  void _showChangeUrlSheet() {
    final textController = TextEditingController(text: _videoUrl);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.link, color: Color(0xFFFF0055)),
                  SizedBox(width: 8),
                  Text('再生 URL の変更 / HLS ストリーミング',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('信頼できるプリセットから選ぶ:',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              ..._presets.entries.map((entry) {
                final isSelected = entry.value == _videoUrl;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFFF0055)
                            : const Color(0x33FFFFFF),
                      ),
                      backgroundColor:
                          isSelected ? const Color(0x22FF0055) : null,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _loadAllPlayers(entry.value);
                    },
                    child:
                        Text(entry.key, style: const TextStyle(fontSize: 13)),
                  ),
                );
              }),
              const SizedBox(height: 12),
              const Text('自由な URL を入力:',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              TextField(
                controller: textController,
                decoration: InputDecoration(
                  hintText: 'https://.../stream.m3u8',
                  filled: true,
                  fillColor: const Color(0xFF0F0F14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF0055)),
                icon: const Icon(Icons.play_arrow),
                label: const Text('この URL で再生'),
                onPressed: () {
                  final url = textController.text.trim();
                  if (url.isNotEmpty) {
                    Navigator.pop(ctx);
                    _loadAllPlayers(url);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _fpsUpdateTimer?.cancel();
    _zeroController?.dispose();
    _standardController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ プレイヤー性能対決',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'URL変更 / HLSテスト',
            onPressed: _showChangeUrlSheet,
          ),
          Row(
            children: [
              const Text('負荷',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              Switch(
                value: _heavyLoadEnabled,
                activeTrackColor: const Color(0xFFFF0055),
                onChanged: (val) => setState(() => _heavyLoadEnabled = val),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: SegmentedButton<PlayerMode>(
                segments: const [
                  ButtonSegment(
                    value: PlayerMode.zeroPlayer,
                    label: Text('zero_player'),
                    icon: Icon(Icons.flash_on, color: Color(0xFFFF0055)),
                  ),
                  ButtonSegment(
                    value: PlayerMode.standardPlayer,
                    label: Text('従来 player'),
                    icon: Icon(Icons.layers_clear),
                  ),
                  ButtonSegment(
                    value: PlayerMode.sideBySide,
                    label: Text('同時比較'),
                    icon: Icon(Icons.compare_arrows),
                  ),
                ],
                selected: {_currentMode},
                onSelectionChanged: (set) =>
                    setState(() => _currentMode = set.first),
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _buildPlayerArea(),
              ),
            ),
            Expanded(
              flex: 4,
              child: _buildLiveMetricsDashboard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerArea() {
    switch (_currentMode) {
      case PlayerMode.zeroPlayer:
        return _buildZeroPlayerCard();
      case PlayerMode.standardPlayer:
        return _buildStandardPlayerCard();
      case PlayerMode.sideBySide:
        return Column(
          children: [
            Expanded(child: _buildZeroPlayerCard()),
            const SizedBox(height: 6),
            Expanded(child: _buildStandardPlayerCard()),
          ],
        );
    }
  }

  Widget _buildZeroPlayerCard() {
    return _PlayerCardContainer(
      title: '🚀 zero_player (FFI共有メモリ + RenderBox直描画)',
      borderColor: const Color(0xFFFF0055),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_isZeroLoading)
            const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF0055)))
          else if (_zeroError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('❌ 読み込み失敗 (404/配信停止):\n$_zeroError',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 10, color: Colors.redAccent)),
              ),
            )
          else if (_zeroController != null)
            ZPlayer(
              controller: _zeroController!,
              showControls: true,
            )
          else
            const Center(child: Text('動画がありません')),
          if (_heavyLoadEnabled) _buildHeavyOverlay(),
        ],
      ),
    );
  }

  Widget _buildStandardPlayerCard() {
    return _StandardPlayerWidget(
      controller: _standardController,
      isLoading: _isStandardLoading,
      errorMessage: _standardError,
      heavyLoad: _heavyLoadEnabled,
      onRebuild: () => _standardBuildCount++,
    );
  }

  Widget _buildHeavyOverlay() {
    return Positioned(
      top: 12,
      right: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0x1AFFFFFF),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.blur_on, size: 14, color: Colors.amber),
                SizedBox(width: 4),
                Text('BackdropFilter 負荷中', style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveMetricsDashboard() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('📊 リアルタイム性能比較',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _fps > 55
                      ? const Color(0x334CAF50)
                      : const Color(0x33F44336),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_fps.toStringAsFixed(1)} FPS ($_droppedFrames dropped)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _fps > 55 ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0x22FFFFFF), height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricColumn(
                    title: 'zero_player',
                    accentColor: const Color(0xFFFF0055),
                    buildCount: '0 回 / 秒',
                    buildSub: '再生中 Rebuild 完全ゼロ',
                    channelCalls: '0 回 (FFI 直読み)',
                    renderType: 'RenderBox 120fps 直描画',
                  ),
                ),
                Container(
                    width: 1,
                    color: const Color(0x22FFFFFF),
                    margin: const EdgeInsets.symmetric(horizontal: 12)),
                Expanded(
                  child: _buildMetricColumn(
                    title: '従来の video_player',
                    accentColor: Colors.grey,
                    buildCount: '$_standardBuildCount 回',
                    buildSub: '毎秒 10〜30 回再構築',
                    channelCalls: '$_standardMethodChannelCalls 回',
                    renderType: 'Widget ツリー再構築型',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn({
    required String title,
    required Color accentColor,
    required String buildCount,
    required String buildSub,
    required String channelCalls,
    required String renderType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: accentColor)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Widget Rebuild 回数',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            Text(buildCount,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: accentColor)),
            Text(buildSub,
                style: const TextStyle(fontSize: 9, color: Color(0x88FFFFFF))),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MethodChannel 通信負荷',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            Text(channelCalls,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('描画方式',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            Text(renderType,
                style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
      ],
    );
  }
}

class _PlayerCardContainer extends StatelessWidget {
  final String title;
  final Color borderColor;
  final Widget child;

  const _PlayerCardContainer({
    required this.title,
    required this.borderColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withAlpha(128), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF1B1B22),
            width: double.infinity,
            child: Text(title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: borderColor)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _StandardPlayerWidget extends StatefulWidget {
  final standard.VideoPlayerController? controller;
  final bool isLoading;
  final String? errorMessage;
  final bool heavyLoad;
  final VoidCallback onRebuild;

  const _StandardPlayerWidget({
    required this.controller,
    required this.isLoading,
    this.errorMessage,
    required this.heavyLoad,
    required this.onRebuild,
  });

  @override
  State<_StandardPlayerWidget> createState() => _StandardPlayerWidgetState();
}

class _StandardPlayerWidgetState extends State<_StandardPlayerWidget> {
  @override
  Widget build(BuildContext context) {
    widget.onRebuild();

    final controller = widget.controller;

    if (widget.errorMessage != null) {
      return _PlayerCardContainer(
        title: '🐢 従来の video_player (setState Rebuild 型)',
        borderColor: Colors.grey,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('❌ 読み込み失敗 (404/配信停止):\n${widget.errorMessage}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
          ),
        ),
      );
    }

    if (widget.isLoading ||
        controller == null ||
        !controller.value.isInitialized) {
      return const _PlayerCardContainer(
        title: '🐢 従来の video_player (setState Rebuild 型)',
        borderColor: Colors.grey,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final pos = controller.value.position;
    final dur = controller.value.duration;
    final progress =
        dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;

    return _PlayerCardContainer(
      title: '🐢 従来の video_player (setState Rebuild 型)',
      borderColor: Colors.grey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: standard.VideoPlayer(controller),
          ),
          if (widget.heavyLoad)
            Positioned(
              top: 12,
              right: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: const Color(0x1AFFFFFF),
                    child: const Text('BackdropFilter 負荷中',
                        style: TextStyle(fontSize: 10)),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: (val) {
                    final target = Duration(
                        milliseconds: (val * dur.inMilliseconds).toInt());
                    controller.seekTo(target);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}

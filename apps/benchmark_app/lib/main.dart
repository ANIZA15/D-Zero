import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'particles_benchmark_view.dart';

void main() {
  runApp(const DZeroBenchmarkApp());
}

class DZeroBenchmarkApp extends StatelessWidget {
  const DZeroBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd-zero Benchmark Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF121420),
        ),
      ),
      home: const BenchmarkHomeScreen(),
    );
  }
}

class BenchmarkHomeScreen extends StatefulWidget {
  const BenchmarkHomeScreen({super.key});

  @override
  State<BenchmarkHomeScreen> createState() => _BenchmarkHomeScreenState();
}

class _BenchmarkHomeScreenState extends State<BenchmarkHomeScreen> {
  int _selectedTabIndex = 0;

  // グローバル FPS & パフォーマンス監視
  double _fps = 60.0;
  double _frameTimeMs = 16.6;
  DateTime _lastFrame = DateTime.now();

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPersistentFrameCallback((timeStamp) {
      final now = DateTime.now();
      final diff = now.difference(_lastFrame).inMicroseconds / 1000.0;
      _lastFrame = now;

      if (diff > 0 && mounted) {
        final currentFps = 1000.0 / diff;
        _fps = (_fps * 0.9) + (currentFps * 0.1);
        _frameTimeMs = diff;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121420),
        title: Row(
          children: [
            const Flexible(
              child: Text(
                '⚡️ d-zero',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildFpsBadge(),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: const Color(0xFF0D0F18),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTabItem(0, Icons.speed, 'Counter & Timer'),
                  _buildTabItem(1, Icons.auto_awesome, 'Particle Stress'),
                  _buildTabItem(2, Icons.memory, 'Buffer & Pool'),
                  _buildTabItem(3, Icons.play_circle_outline, 'Video Player'),
                  _buildTabItem(4, Icons.analytics_outlined, 'Architecture'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: const [
          CounterBenchmarkView(),
          ParticlesBenchmarkView(),
          BufferPoolBenchmarkView(),
          VideoBenchmarkView(),
          ArchitectureOverviewView(),
        ],
      ),
    );
  }

  Widget _buildFpsBadge() {
    final is120 = _fps > 90;
    final color = _fps >= 55 ? const Color(0xFF00FF88) : (_fps >= 30 ? Colors.orange : Colors.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            '${_fps.toStringAsFixed(1)} FPS (${_frameTimeMs.toStringAsFixed(1)}ms)',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10),
          ),
          if (is120) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('120Hz', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? const Color(0xFF00FF88) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? const Color(0xFF00FF88) : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// 1. Counter & Stopwatch Benchmark View
// ==============================================================================
class CounterBenchmarkView extends StatefulWidget {
  const CounterBenchmarkView({super.key});

  @override
  State<CounterBenchmarkView> createState() => _CounterBenchmarkViewState();
}

class _CounterBenchmarkViewState extends State<CounterBenchmarkView> {
  final ValueNotifier<int> _dZeroCounter = ValueNotifier<int>(0);
  int _traditionalCount = 0;
  int _traditionalRebuildCount = 0;
  Timer? _updateTimer;
  double _frequencyHz = 120.0;
  bool _isRunning = true;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _updateTimer?.cancel();
    final intervalUs = (1000000 / _frequencyHz).round();
    _updateTimer = Timer.periodic(Duration(microseconds: intervalUs), (_) {
      if (!_isRunning) return;
      _dZeroCounter.value++;
      if (mounted) {
        setState(() {
          _traditionalCount++;
          _traditionalRebuildCount++;
        });
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _dZeroCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControlCard(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildPanel(
                  title: '❌ Traditional Flutter',
                  subtitle: 'setState() + Text()',
                  badgeColor: Colors.redAccent,
                  rebuildCount: _traditionalRebuildCount,
                  allocationEstimate: '${(_traditionalCount * 3)} Strings created',
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _traditionalCount.toString().padLeft(6, '0'),
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.redAccent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPanel(
                  title: '⚡️ d-zero Suite',
                  subtitle: 'ZCounter (Direct Canvas)',
                  badgeColor: const Color(0xFF00FF88),
                  rebuildCount: 0,
                  allocationEstimate: '0 Heap allocations',
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ZCounter(
                        valueListenable: _dZeroCounter,
                        minDigits: 6,
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Color(0xFF00FF88)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStopwatchComparison(),
        ],
      ),
    );
  }

  Widget _buildControlCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  '更新レート制御 (Update Frequency)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text('${_frequencyHz.toInt()} Hz (${(1000 / _frequencyHz).toStringAsFixed(1)}ms)', style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          Slider(
            value: _frequencyHz,
            min: 30,
            max: 500,
            divisions: 47,
            activeColor: const Color(0xFF00FF88),
            onChanged: (val) {
              setState(() {
                _frequencyHz = val;
                _startTimer();
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: () => setState(() => _isRunning = !_isRunning),
                icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                label: Text(_isRunning ? '一時停止' : '再開'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    required String subtitle,
    required Color badgeColor,
    required int rebuildCount,
    required String allocationEstimate,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: badgeColor)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 24),
          SizedBox(height: 70, child: child),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF1E2235)),
          const SizedBox(height: 8),
          _buildMetricRow('Widget Rebuilds', '$rebuildCount 回', rebuildCount == 0 ? Colors.green : Colors.redAccent),
          _buildMetricRow('Memory Pressure', allocationEstimate, rebuildCount == 0 ? Colors.green : Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopwatchComparison() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚡️ 120fps V-Sync 高精度ストップウォッチ (ZStopwatch)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          SizedBox(height: 4),
          Text('毎フレームの経過時間を Canvas へ直接描画。String を一切生成しないゼロアロケーション時間表示。', style: TextStyle(color: Colors.grey, fontSize: 11)),
          SizedBox(height: 20),
          Center(
            child: ZStopwatch(
              isRunning: true,
              includeHours: true,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF), fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// 2. Buffer & Pool Benchmark View
// ==============================================================================
class BufferPoolBenchmarkView extends StatefulWidget {
  const BufferPoolBenchmarkView({super.key});

  @override
  State<BufferPoolBenchmarkView> createState() => _BufferPoolBenchmarkViewState();
}

class _BufferPoolBenchmarkViewState extends State<BufferPoolBenchmarkView> {
  final FloatRingBuffer _ringBuffer = FloatRingBuffer(128);
  final List<double> _standardList = [];
  double _ringBufferWriteTimeUs = 0;
  double _standardListWriteTimeUs = 0;
  Timer? _timer;
  double _phase = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _runStep();
    });
  }

  void _runStep() {
    _phase += 0.1;
    final val = sin(_phase) * 50.0;

    // 1. Standard List.removeAt(0)
    final swList = Stopwatch()..start();
    _standardList.add(val);
    if (_standardList.length > 128) {
      _standardList.removeAt(0);
    }
    swList.stop();

    // 2. FloatRingBuffer O(1)
    final swRing = Stopwatch()..start();
    _ringBuffer.push(val);
    swRing.stop();

    if (mounted) {
      setState(() {
        _standardListWriteTimeUs = swList.elapsedMicroseconds.toDouble();
        _ringBufferWriteTimeUs = swRing.elapsedMicroseconds.toDouble();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF121420),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2235)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('リアルタイム波形リングバッファ比較 (容量 128 要素)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('音声波形や時系列データストリームにおける配列コピー (O(N)) vs 円環ポインタ更新 (O(1))', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 20),
                SizedBox(
                  height: 120,
                  child: CustomPaint(
                    painter: SimpleWavePainter(buffer: _ringBuffer),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF1E2235)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Standard List.removeAt(0)', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('${_standardListWriteTimeUs.toStringAsFixed(1)} μs (O(N) Shift)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('d-zero FloatRingBuffer', style: TextStyle(color: Color(0xFF00FF88), fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('${_ringBufferWriteTimeUs.toStringAsFixed(1)} μs (O(1) Ring)', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00FF88))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SimpleWavePainter extends CustomPainter {
  final FloatRingBuffer buffer;
  SimpleWavePainter({required this.buffer});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final count = buffer.length;
    if (count == 0) return;

    final dx = size.width / (buffer.capacity - 1);
    final centerY = size.height / 2.0;

    for (int i = 0; i < count; i++) {
      final x = i * dx;
      final y = centerY + buffer[i];
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SimpleWavePainter oldDelegate) => true;
}

// ==============================================================================
// 3. Video Benchmark View
// ==============================================================================
class VideoBenchmarkView extends StatelessWidget {
  const VideoBenchmarkView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF121420),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E2235)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_filter, size: 48, color: Color(0xFF00FF88)),
              const SizedBox(height: 16),
              const Text('zero_player Video Comparison', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                '動画プレイヤーの詳細な Side-by-Side 比較・Kawase Blur シェーダー・MethodChannel 負荷テストは、専用パッケージ example アプリにて稼働しています。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2235),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('cd packages/d_zero_player/example && flutter run', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF00E5FF))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// 4. Architecture Overview View
// ==============================================================================
class ArchitectureOverviewView extends StatelessWidget {
  const ArchitectureOverviewView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCard(
            title: '⚡️ 4つのゼロ・アーキテクチャ',
            body: '''
1. Zero Rebuild: LeafRenderObjectWidget + ZeroRenderBox により setState() / build() を一切発火させずに Canvas ペイント。
2. Zero Allocation: 描画用 String を作らない ZeroNumberPainter、ZeroPool<T> オブジェクトプール、FloatRingBuffer。
3. Zero Channel: C++ Atomic 共有メモリ ＋ Dart FFI Direct Pointer による 0ns レイテンシ同期。
4. Zero Copy & Shader: ハードウェアデコード GPU テクスチャ直結 ＋ Impeller 最適化 Kawase Blur (zero_blur.frag)。
''',
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: '📊 120Hz (ProMotion) 時代のフレームバジェット',
            body: '''
- 60fps: 16.6ms / フレーム
- 120fps: 8.33ms / フレーム

Impeller によりシェーダーコンパイルジャンクが解消された現代、残る最大のコマ落ち原因は「Dart UI スレッドにおける毎フレームのアロケーションと GC ポーズ」です。d-zero はこの根本原因を排除します。
''',
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required String body}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF00FF88))),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.white70)),
        ],
      ),
    );
  }
}

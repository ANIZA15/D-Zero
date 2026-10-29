import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zero_counter/zero_counter.dart';

void main() {
  runApp(const ZeroCounterExampleApp());
}

class ZeroCounterExampleApp extends StatelessWidget {
  const ZeroCounterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'zero_counter Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00B0FF),
          surface: Color(0xFF131B2A),
        ),
      ),
      home: const ZeroCounterShowcaseScreen(),
    );
  }
}

class ZeroCounterShowcaseScreen extends StatefulWidget {
  const ZeroCounterShowcaseScreen({super.key});

  @override
  State<ZeroCounterShowcaseScreen> createState() => _ZeroCounterShowcaseScreenState();
}

class _ZeroCounterShowcaseScreenState extends State<ZeroCounterShowcaseScreen> {
  final ValueNotifier<int> _fastCounter = ValueNotifier<int>(0);
  Timer? _timer;
  bool _isRunning = true;

  @override
  void initState() {
    super.initState();
    // 毎秒 100 回 (10ms 間隔) でインクリメント
    _startCounter();
  }

  void _startCounter() {
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      _fastCounter.value++;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fastCounter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡️ zero_counter Sample'),
        backgroundColor: const Color(0xFF131B2A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCard(
              title: '1. ZeroCounter (超高速 100Hz カウンター)',
              subtitle: '毎秒 100 回の更新でも Widget リビルド 0、String 生成 0',
              child: Center(
                child: ZeroCounter(
                  valueListenable: _fastCounter,
                  minDigits: 6,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00E676),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildCard(
              title: '2. ZeroStopwatch (120fps 高精度ストップウォッチ)',
              subtitle: 'V-Sync に同期し、Canvas へ直接タイムコードをペイント',
              child: Column(
                children: [
                  Center(
                    child: ZeroStopwatch(
                      isRunning: _isRunning,
                      includeHours: true,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00B0FF),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isRunning = !_isRunning;
                      });
                    },
                    icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                    label: Text(_isRunning ? '一時停止' : '再開'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B0FF),
                      foregroundColor: Colors.black,
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

  Widget _buildCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFF202D45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

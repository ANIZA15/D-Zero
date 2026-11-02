import 'package:flutter/material.dart';
import 'package:d_zero_terminal/d_zero_terminal.dart';

void main() {
  runApp(const DZeroTerminalExampleApp());
}

/// Simple, clean terminal demo app for `d_zero_terminal`.
class DZeroTerminalExampleApp extends StatefulWidget {
  const DZeroTerminalExampleApp({super.key});

  @override
  State<DZeroTerminalExampleApp> createState() =>
      _DZeroTerminalExampleAppState();
}

class _DZeroTerminalExampleAppState extends State<DZeroTerminalExampleApp> {
  late final ZeroPtyController _controller;
  int _burstTick = 1;

  @override
  void initState() {
    super.initState();
    _controller = ZeroPtyController(
      cols: 80,
      rows: 24,
      scrollbackCapacity: 1024,
    );
    _seedWelcomeBanner();
  }

  void _seedWelcomeBanner() {
    _controller.feedAnsiText(
      'D-Zero Terminal Ready\r\n'
      'Type commands or press buttons above.\r\n',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ターミナル',
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
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'ターミナル',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFFE2E8F0)),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildToolbar(),
                const SizedBox(height: 12),
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ZPtyTerminal(
                                controller: _controller,
                                autoResize: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ZTerminalMinimap(
                            controller: _controller,
                            width: 40,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ZTerminalHud(controller: _controller),
        FilledButton(
          onPressed: () => _controller.spawnShell(),
          child: const Text('シェル起動'),
        ),
        OutlinedButton(
          onPressed: () =>
              _controller.runStressBurst(lineCount: 64, seed: _burstTick++),
          child: const Text('サンプル出力'),
        ),
        TextButton(
          onPressed: () => _controller.clearScreen(),
          child: const Text('クリア'),
        ),
      ],
    );
  }
}

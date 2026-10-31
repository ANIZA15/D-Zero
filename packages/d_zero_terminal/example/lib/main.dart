import 'dart:async';
import 'package:flutter/material.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_terminal/d_zero_terminal.dart';

void main() {
  runApp(const DZeroTerminalExampleApp());
}

/// Interactive benchmark and terminal demo app for `d_zero_terminal`.
class DZeroTerminalExampleApp extends StatefulWidget {
  /// Creates a const [DZeroTerminalExampleApp].
  const DZeroTerminalExampleApp({super.key});

  @override
  State<DZeroTerminalExampleApp> createState() =>
      _DZeroTerminalExampleAppState();
}

class _DZeroTerminalExampleAppState extends State<DZeroTerminalExampleApp> {
  late final ZeroPtyController _controller;
  Timer? _streamTimer;
  bool _streamingBurst = false;
  int _burstTick = 1;

  @override
  void initState() {
    super.initState();
    _controller = ZeroPtyController(
      cols: 96,
      rows: 28,
      scrollbackCapacity: 2048,
    );
    _seedWelcomeBanner();
  }

  void _seedWelcomeBanner() {
    _controller.feedAnsiText(
      '\x1b[1;36m============================================================\x1b[0m\r\n'
      '\x1b[1;32m ⚡ D-ZERO TERMINAL (C++17 FFI + Impeller drawRawAtlas)\x1b[0m\r\n'
      '\x1b[38;2;140;180;255m Zero Rebuild | Zero Allocation | Zero Channel (0ns FFI)\x1b[0m\r\n'
      '\x1b[1;36m============================================================\x1b[0m\r\n',
    );
    _controller.runStressBurst(lineCount: 24, seed: 42);
  }

  void _toggleLiveStream() {
    setState(() {
      _streamingBurst = !_streamingBurst;
    });
    _streamTimer?.cancel();
    if (_streamingBurst) {
      _streamTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        _controller.runStressBurst(lineCount: 16, seed: _burstTick++);
      });
    }
  }

  void _cycleCursorStyle() {
    final nextIdx = (_controller.cursorStyle.index + 1) %
        ZeroTerminalCursorStyle.values.length;
    _controller.setCursorStyle(
      style: ZeroTerminalCursorStyle.values[nextIdx],
      visible: true,
    );
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF06090F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D1117),
          title: const Text(
            'D-Zero FFI PTY Terminal Benchmark',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ZFPSMonitor(),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ZPtyTerminal(
                        controller: _controller,
                        autoResize: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ZTerminalMinimap(
                      controller: _controller,
                      width: 46,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ZTerminalHud(controller: _controller),
        FilledButton.icon(
          onPressed: () => _controller.spawnShell(),
          icon: const Icon(Icons.terminal, size: 16),
          label: const Text('Spawn /bin/zsh PTY'),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              _controller.runStressBurst(lineCount: 512, seed: _burstTick++),
          icon: const Icon(Icons.bolt, size: 16),
          label: const Text('512-Line TrueColor Burst'),
        ),
        OutlinedButton.icon(
          onPressed: _toggleLiveStream,
          icon: Icon(_streamingBurst ? Icons.pause : Icons.play_arrow, size: 16),
          label: Text(_streamingBurst ? 'Stop 60Hz Stream' : '60Hz Stress Stream'),
        ),
        OutlinedButton(
          onPressed: _cycleCursorStyle,
          child: const Text('Cursor Style'),
        ),
        OutlinedButton(
          onPressed: () => _controller.clearScreen(),
          child: const Text('Clear'),
        ),
      ],
    );
  }
}

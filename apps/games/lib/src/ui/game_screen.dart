import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:d_zero_particles/d_zero_particles.dart';
import 'package:d_zero_fx/d_zero_fx.dart';
import 'package:d_zero_canvas/d_zero_canvas.dart';
import '../controller/zero_game_controller.dart';
import '../model/game_config.dart';
import '../rendering/z_game_stage.dart';
import '../rendering/flutter_game_stage.dart';
import 'engine_compare_hud.dart';
import 'battle_overlay_hud.dart';

/// Main interactive screen for ZERO OVERDRIVE.
class ZeroOverdriveScreen extends StatefulWidget {
  final ZeroGameController? controller;

  const ZeroOverdriveScreen({
    super.key,
    this.controller,
  });

  @override
  State<ZeroOverdriveScreen> createState() => _ZeroOverdriveScreenState();
}

class _ZeroOverdriveScreenState extends State<ZeroOverdriveScreen> {
  late final ZeroGameController _controller;
  late final bool _ownsController;
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ZeroGameController();
    _controller.addListener(_onControllerModeChanged);
  }

  void _onControllerModeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerModeChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final LogicalKeyboardKey key = event.logicalKey;
    if (event is KeyDownEvent) {
      _pressedKeys.add(key);
      _triggerInstantShortcuts(key);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
    }
    _syncDirectionalInput();
    return KeyEventResult.handled;
  }

  void _triggerInstantShortcuts(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) {
      _controller.triggerOverdriveNova();
    } else if (key == LogicalKeyboardKey.keyE) {
      _controller.toggleEngineMode();
    } else if (key == LogicalKeyboardKey.keyC) {
      _controller.spawnChaosBurst();
    }
  }

  void _syncDirectionalInput() {
    double dx = 0.0;
    double dy = 0.0;
    if (_isLeftPressed()) dx -= 1.0;
    if (_isRightPressed()) dx += 1.0;
    if (_isUpPressed()) dy -= 1.0;
    if (_isDownPressed()) dy += 1.0;
    _controller.setKeyboardVector(dx, dy);
  }

  bool _isLeftPressed() {
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA)) return true;
    return _pressedKeys.contains(LogicalKeyboardKey.arrowLeft);
  }

  bool _isRightPressed() {
    if (_pressedKeys.contains(LogicalKeyboardKey.keyD)) return true;
    return _pressedKeys.contains(LogicalKeyboardKey.arrowRight);
  }

  bool _isUpPressed() {
    if (_pressedKeys.contains(LogicalKeyboardKey.keyW)) return true;
    return _pressedKeys.contains(LogicalKeyboardKey.arrowUp);
  }

  bool _isDownPressed() {
    if (_pressedKeys.contains(LogicalKeyboardKey.keyS)) return true;
    return _pressedKeys.contains(LogicalKeyboardKey.arrowDown);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _controller.engineMode == GameEngineMode.dZero;

    return Scaffold(
      backgroundColor: ZeroGamePalette.bgVoid,
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EngineCompareHud(controller: _controller),
                const SizedBox(height: 10.0),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDZero
                              ? ZeroGamePalette.neonGreen.withValues(alpha: 0.45)
                              : ZeroGamePalette.dangerRed.withValues(alpha: 0.45),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(14.0),
                      ),
                      child: isDZero
                          ? _buildDZeroArenaStack()
                          : _buildFlutterArenaStack(),
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

  Widget _buildDZeroArenaStack() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ZInfiniteGrid(
          controller: _controller.gridViewportCtrl,
          size: const Size(1920.0, 1080.0),
          baseSpacing: 36.0,
          backgroundColor: ZeroGamePalette.bgVoid,
          minorGridColor: const Color(0xFF111A2E),
          majorGridColor: const Color(0xFF1E3A5F),
        ),
        IgnorePointer(
          child: ZRipple(
            controller: _controller.rippleCtrl,
            size: const Size(1920.0, 1080.0),
            baseColor: const Color(0x00000000),
            rippleColor: ZeroGamePalette.neonCyan,
            maxRadius: 220.0,
          ),
        ),
        IgnorePointer(
          child: ZParticles(
            controller: _controller.particleCtrl,
            isRunning: !_controller.isPaused,
            color: const Color(0x9900FF88),
            pointSize: 2.6,
            pointStyle: ZParticlePointStyle.square,
          ),
        ),
        ZGameStage(controller: _controller),
        IgnorePointer(
          child: ZConfetti(
            controller: _controller.confettiCtrl,
            isRunning: !_controller.isPaused,
            ribbonThickness: 3.5,
          ),
        ),
        Positioned(
          top: 66.0,
          left: 0.0,
          right: 0.0,
          height: 110.0,
          child: IgnorePointer(
            child: ZDanmaku(
              controller: _controller.danmakuCtrl,
              size: const Size(1920.0, 110.0),
              backgroundColor: const Color(0x00000000),
            ),
          ),
        ),
        BattleOverlayHud(controller: _controller),
      ],
    );
  }

  Widget _buildFlutterArenaStack() {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterGameStage(controller: _controller),
        BattleOverlayHud(controller: _controller),
      ],
    );
  }
}

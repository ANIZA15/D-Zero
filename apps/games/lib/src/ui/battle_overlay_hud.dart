import 'package:flutter/material.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_ui/d_zero_ui.dart';
import 'package:d_zero_fx/d_zero_fx.dart';
import 'package:d_zero_waveform/d_zero_waveform.dart';
import '../controller/zero_game_controller.dart';
import '../model/game_config.dart';

/// In-arena battle HUD & control overlay that switches between D-Zero `ZWidget`
/// components and standard Flutter widgets according to [ZeroGameController.engineMode].
class BattleOverlayHud extends StatelessWidget {
  final ZeroGameController controller;

  const BattleOverlayHud({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDZero = controller.engineMode == GameEngineMode.dZero;
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          isDZero ? _buildDZeroTopBar() : _buildFlutterTopBar(),
          _buildBottomControlsRow(),
        ],
      ),
    );
  }

  Widget _buildDZeroTopBar() {
    return Stack(
      children: [
        const Positioned.fill(
          child: ZBlur(
            size: Size(700.0, 58.0),
            tintColor: Color(0x990B1020),
            borderColor: Color(0x5500FF88),
            borderRadius: 10.0,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Wrap(
            spacing: 14.0,
            runSpacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              _buildDZeroScoreAndWave(),
              _buildDZeroShieldAndHeat(),
              _buildDZeroTimerAndSpectrum(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDZeroScoreAndWave() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SCORE (ZCounter)',
              style: TextStyle(color: Colors.white60, fontSize: 10.0),
            ),
            SizedBox(
              width: 96.0,
              height: 22.0,
              child: ZCounter(
                valueListenable: controller.scoreNotifier,
                minDigits: 7,
                style: const TextStyle(
                  color: ZeroGamePalette.neonGreen,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12.0),
        ZBadge(
          countListenable: controller.waveNotifier,
          hideWhenZero: false,
          badgeColor: ZeroGamePalette.neonPurple,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
            decoration: BoxDecoration(
              color: const Color(0xFF151C30),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: const Text(
              'WAVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14.0),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'KILLS',
              style: TextStyle(color: Colors.white60, fontSize: 10.0),
            ),
            SizedBox(
              width: 54.0,
              height: 20.0,
              child: ZCounter(
                valueListenable: controller.killCountNotifier,
                minDigits: 4,
                style: const TextStyle(
                  color: ZeroGamePalette.neonAmber,
                  fontSize: 15.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDZeroShieldAndHeat() {
    return SizedBox(
      width: 190.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SHIELD INTEGRITY (ZLinearProgress)',
            style: TextStyle(color: Colors.white70, fontSize: 9.5),
          ),
          const SizedBox(height: 3.0),
          SizedBox(
            height: 12.0,
            child: ZLinearProgress(
              valueListenable: controller.hpRatioNotifier,
              valueColor: ZeroGamePalette.neonCyan,
              trackColor: const Color(0xFF1E293B),
              strokeWidth: 7.0,
              showPercentage: true,
            ),
          ),
          const SizedBox(height: 4.0),
          SizedBox(
            height: 8.0,
            child: ZLinearProgress(
              valueListenable: controller.weaponHeatNotifier,
              valueColor: ZeroGamePalette.neonMagenta,
              trackColor: const Color(0xFF1E293B),
              strokeWidth: 5.0,
              showPercentage: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDZeroTimerAndSpectrum() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 96.0,
          height: 24.0,
          child: ZStopwatch(
            isRunning: true,
            includeHours: false,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8.0),
        SizedBox(
          width: 100.0,
          height: 32.0,
          child: ZSpectrumAnalyzer(
            controller: controller.spectrumCtrl,
            preferredSize: const Size(100.0, 32.0),
            barColor: ZeroGamePalette.neonCyan,
            peakColor: ZeroGamePalette.neonAmber,
          ),
        ),
      ],
    );
  }

  Widget _buildFlutterTopBar() {
    return ListenableBuilder(
      listenable: controller.flutterRebuildsNotifier,
      builder: (context, _) {
        final String scoreText =
            controller.scoreNotifier.value.toString().padLeft(7, '0');
        final String killsText =
            controller.killCountNotifier.value.toString().padLeft(4, '0');
        final int wave = controller.waveNotifier.value;
        final double hp = controller.hpRatioNotifier.value.clamp(0.0, 1.0);

        return Card(
          color: const Color(0xCC18101C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
            side: const BorderSide(color: ZeroGamePalette.dangerRed),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Wrap(
              spacing: 16.0,
              runSpacing: 8.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  'SCORE (Text): $scoreText   |   WAVE $wave   |   KILLS: $killsText',
                  style: const TextStyle(
                    color: ZeroGamePalette.dangerRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.0,
                    fontFamily: 'monospace',
                  ),
                ),
                SizedBox(
                  width: 180.0,
                  child: LinearProgressIndicator(
                    value: hp,
                    backgroundColor: const Color(0xFF334155),
                    color: ZeroGamePalette.dangerRed,
                    minHeight: 8.0,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomControlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildLeftStickAndSparkControl(),
        _buildRightOverdriveCore(),
      ],
    );
  }

  Widget _buildLeftStickAndSparkControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ZJoystick(
          controller: controller.joystickCtrl,
          size: const Size(104.0, 104.0),
          baseColor: const Color(0xAA0F172A),
          stickColor: ZeroGamePalette.neonCyan,
        ),
        const SizedBox(width: 10.0),
        ZCard(
          color: const Color(0xBB0D1324),
          borderColor: const Color(0xFF334155),
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'FX Spark Multiplier (ZSlider)',
                style: TextStyle(color: Colors.white70, fontSize: 10.0),
              ),
              SizedBox(
                width: 165.0,
                height: 28.0,
                child: ZSlider(
                  controller: controller.sparkIntensitySlider,
                  min: 0.5,
                  max: 4.0,
                  activeColor: ZeroGamePalette.neonGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightOverdriveCore() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZShimmer(
              size: Size(128.0, 16.0),
              borderRadius: 6.0,
              baseColor: Color(0xFF1E1B4B),
              highlightColor: ZeroGamePalette.neonCyan,
            ),
            const SizedBox(height: 6.0),
            ZButton(
              label: '💥 OVERDRIVE NOVA',
              color: const Color(0xFFD97706),
              borderColor: ZeroGamePalette.neonAmber,
              borderWidth: 1.8,
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 12.0,
                fontWeight: FontWeight.w900,
              ),
              onPressed: controller.triggerOverdriveNova,
            ),
          ],
        ),
        const SizedBox(width: 10.0),
        GestureDetector(
          onTap: controller.triggerOverdriveNova,
          child: ZLiquidProgress(
            valueListenable: controller.overdriveRatioNotifier,
            size: const Size(86.0, 86.0),
            waveColor: ZeroGamePalette.neonPurple,
            borderColor: ZeroGamePalette.neonAmber,
            backgroundColor: const Color(0xCC090D18),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_ui/d_zero_ui.dart';
import 'package:d_zero_chart/d_zero_chart.dart';
import '../controller/zero_game_controller.dart';
import '../model/game_config.dart';

/// Top control bar & live telemetry HUD comparing D-Zero vs Standard Flutter.
class EngineCompareHud extends StatelessWidget {
  final ZeroGameController controller;

  const EngineCompareHud({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDZero = controller.engineMode == GameEngineMode.dZero;
    final Color accent =
        isDZero ? ZeroGamePalette.neonGreen : ZeroGamePalette.dangerRed;

    return ZCard(
      color: ZeroGamePalette.panelDark,
      borderColor: accent.withValues(alpha: 0.55),
      borderRadius: 12.0,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTopSwitchRow(isDZero),
          const SizedBox(height: 8.0),
          _buildPresetAndActionRow(),
          const SizedBox(height: 8.0),
          _buildTelemetryRow(),
        ],
      ),
    );
  }

  Widget _buildTopSwitchRow(bool isDZero) {
    return Wrap(
      spacing: 10.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDZero ? Icons.bolt : Icons.warning_amber_rounded,
              color: isDZero ? ZeroGamePalette.neonGreen : ZeroGamePalette.dangerRed,
              size: 20.0,
            ),
            const SizedBox(width: 6.0),
            const Flexible(
              child: Text(
                'ZERO OVERDRIVE — Engine Switcher',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14.0,
                  letterSpacing: 0.6,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        _buildEngineToggleButtons(isDZero),
      ],
    );
  }

  Widget _buildEngineToggleButtons(bool isDZero) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 6.0,
      children: [
        ZButton(
          label: '⚡️ D-Zero System (Zero-Alloc / SIMD)',
          color: isDZero ? const Color(0xFF059669) : const Color(0xFF1E293B),
          borderColor:
              isDZero ? ZeroGamePalette.neonGreen : const Color(0xFF334155),
          borderWidth: isDZero ? 1.8 : 1.0,
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7.0),
          textStyle: TextStyle(
            color: isDZero ? Colors.white : Colors.white70,
            fontSize: 12.0,
            fontWeight: FontWeight.bold,
          ),
          onPressed: () => controller.setEngineMode(GameEngineMode.dZero),
        ),
        ZButton(
          label: '❌ Flutter Standard (setState + OOP)',
          color: !isDZero ? const Color(0xFFB91C1C) : const Color(0xFF1E293B),
          borderColor:
              !isDZero ? ZeroGamePalette.dangerRed : const Color(0xFF334155),
          borderWidth: !isDZero ? 1.8 : 1.0,
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7.0),
          textStyle: TextStyle(
            color: !isDZero ? Colors.white : Colors.white70,
            fontSize: 12.0,
            fontWeight: FontWeight.bold,
          ),
          onPressed: () => controller.setEngineMode(GameEngineMode.flutter),
        ),
      ],
    );
  }

  Widget _buildPresetAndActionRow() {
    final ParticleStressPreset currentPreset = controller.preset;
    return Wrap(
      spacing: 8.0,
      runSpacing: 6.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Particle Load:',
              style: TextStyle(color: Colors.white70, fontSize: 11.0),
            ),
            for (final preset in ParticleStressPreset.values)
              _buildPresetChip(preset, preset == currentPreset),
          ],
        ),
        Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          children: [
            ZButton(
              label: '💥 Chaos Burst (+500)',
              color: const Color(0xFF7C3AED),
              borderColor: ZeroGamePalette.neonPurple,
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11.0,
                fontWeight: FontWeight.bold,
              ),
              onPressed: controller.spawnChaosBurst,
            ),
            ZButton(
              label: controller.autoPilot ? '🤖 Auto-Pilot: ON' : '🎮 Manual Control',
              color: controller.autoPilot
                  ? const Color(0xFF0284C7)
                  : const Color(0xFF334155),
              borderColor: ZeroGamePalette.neonCyan,
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11.0,
                fontWeight: FontWeight.bold,
              ),
              onPressed: () => controller.setAutoPilot(!controller.autoPilot),
            ),
            ZButton(
              label: 'Reset Metrics',
              color: const Color(0xFF1E293B),
              borderColor: const Color(0xFF475569),
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
              textStyle: const TextStyle(color: Colors.white70, fontSize: 11.0),
              onPressed: controller.resetTelemetryCounters,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetChip(ParticleStressPreset preset, bool selected) {
    return ZButton(
      label: preset.label,
      color: selected ? const Color(0xFF0369A1) : const Color(0xFF161E31),
      borderColor: selected ? ZeroGamePalette.neonCyan : const Color(0xFF334155),
      padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 5.0),
      textStyle: TextStyle(
        color: selected ? Colors.white : Colors.white60,
        fontSize: 11.0,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onPressed: () => controller.applyPreset(preset),
    );
  }

  Widget _buildTelemetryRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const ZFPSMonitor(
            size: Size(140.0, 40.0),
            backgroundColor: Color(0xFF070A14),
          ),
          const SizedBox(width: 8.0),
          _buildMetricBox(
            label: 'Active Particles',
            child: SizedBox(
              width: 72.0,
              height: 18.0,
              child: ZCounter(
                valueListenable: controller.activeEntitiesNotifier,
                minDigits: 5,
                style: const TextStyle(
                  color: ZeroGamePalette.neonCyan,
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          _buildMetricBox(
            label: '⚡️ D-Zero Rebuilds',
            child: SizedBox(
              width: 56.0,
              height: 18.0,
              child: ZCounter(
                valueListenable: controller.dZeroRebuildsNotifier,
                minDigits: 1,
                style: const TextStyle(
                  color: ZeroGamePalette.neonGreen,
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          _buildMetricBox(
            label: '❌ Flutter Rebuilds',
            child: SizedBox(
              width: 68.0,
              height: 18.0,
              child: ZCounter(
                valueListenable: controller.flutterRebuildsNotifier,
                minDigits: 4,
                style: const TextStyle(
                  color: ZeroGamePalette.dangerRed,
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          _buildMetricBox(
            label: '❌ Flutter Heap Allocs',
            child: SizedBox(
              width: 96.0,
              height: 18.0,
              child: ZCounter(
                valueListenable: controller.flutterHeapAllocsNotifier,
                minDigits: 7,
                style: const TextStyle(
                  color: ZeroGamePalette.neonAmber,
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          _buildMetricBox(
            label: 'RSS Memory (MB)',
            child: SizedBox(
              width: 64.0,
              height: 18.0,
              child: ZPriceTicker(
                valueListenable: controller.rssMemoryMbNotifier,
                currencyGlyph: ZeroNumberPainter.glyphPlus,
                fractionDigits: 1,
                style: const TextStyle(
                  color: ZeroGamePalette.neonCyan,
                  fontSize: 13.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          _buildMetricBox(
            label: 'Frame Time (ms)',
            child: SizedBox(
              width: 110.0,
              height: 24.0,
              child: ZSparkline(
                controller: controller.frameChartCtrl,
                preferredSize: const Size(110.0, 24.0),
                showLabels: false,
                showGrid: false,
                lineColor: ZeroGamePalette.neonGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBox({
    required String label,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: const Color(0xFF070A14),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 10.0),
          ),
          const SizedBox(height: 2.0),
          child,
        ],
      ),
    );
  }
}

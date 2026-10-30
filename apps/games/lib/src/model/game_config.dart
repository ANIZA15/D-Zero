import 'package:flutter/material.dart';

/// Rendering & UI system mode selectable in real time inside the game.
enum GameEngineMode {
  /// Ultra-fast D-Zero engine: `ZLeafWidget` + `ZeroRenderBox` + SoA SIMD + `drawRawPoints`.
  /// Zero Widget rebuilds and zero per-frame heap allocations.
  dZero,

  /// Traditional Flutter engine: `setState` every frame + `CustomPainter` with per-entity
  /// `Paint`/`Offset` allocations and standard `Text`/`LinearProgressIndicator` rebuilds.
  flutter,
}

/// Particle and bullet-hell load presets for stress testing both engines.
enum ParticleStressPreset {
  /// Balanced arcade load (3,000 SIMD background particles + standard bullet/spark density).
  normal(
    label: 'Normal (3K)',
    ambientParticles: 3000,
    sparkMultiplier: 1.0,
    spawnIntervalSec: 0.55,
  ),

  /// Heavy bullet-hell load (10,000 SIMD particles + 2x sparks & dense enemy waves).
  heavy(
    label: 'Heavy (10K)',
    ambientParticles: 10000,
    sparkMultiplier: 2.0,
    spawnIntervalSec: 0.32,
  ),

  /// Extreme stress load (22,000 SIMD particles + 3.5x sparks & relentless enemy swarms).
  extreme(
    label: 'Extreme (22K)',
    ambientParticles: 22000,
    sparkMultiplier: 3.5,
    spawnIntervalSec: 0.18,
  );

  final String label;
  final int ambientParticles;
  final double sparkMultiplier;
  final double spawnIntervalSec;

  const ParticleStressPreset({
    required this.label,
    required this.ambientParticles,
    required this.sparkMultiplier,
    required this.spawnIntervalSec,
  });
}

/// Shared neon color palette and constants for ZERO OVERDRIVE.
abstract final class ZeroGamePalette {
  static const Color bgVoid = Color(0xFF060812);
  static const Color panelDark = Color(0xFF0E1324);
  static const Color neonGreen = Color(0xFF00FF88);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonMagenta = Color(0xFFFF2A85);
  static const Color neonAmber = Color(0xFFFFD740);
  static const Color neonPurple = Color(0xFFD500F9);
  static const Color dangerRed = Color(0xFFFF5252);

  /// 4 neon spark bucket colors used for batched `Canvas.drawRawPoints` rendering.
  static const List<Color> sparkBucketColors = <Color>[
    neonCyan,
    neonMagenta,
    neonGreen,
    neonAmber,
  ];
}

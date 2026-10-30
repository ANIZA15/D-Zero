import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_particles/d_zero_particles.dart';
import 'package:d_zero_fx/d_zero_fx.dart';
import 'package:d_zero_canvas/d_zero_canvas.dart';
import 'package:d_zero_ui/d_zero_ui.dart';
import 'package:d_zero_chart/d_zero_chart.dart';
import 'package:d_zero_waveform/d_zero_waveform.dart';
import '../model/game_config.dart';
import '../model/soa_entities.dart';

/// Central zero-allocation game & telemetry controller for ZERO OVERDRIVE.
///
/// Coordinates Structure-of-Arrays (SoA) combat simulation alongside D-Zero
/// particle, confetti, ripple, danmaku, grid, spectrum, and sparkline controllers.
/// Strictly resilient against double-[dispose] and post-dispose access.
class ZeroGameController extends ChangeNotifier {
  static const List<String> _killAnnouncements = <String>[
    '⚡️ ZERO-ALLOCATION KILL STREAK!',
    '🔥 OVERDRIVE CORE CHARGING!',
    '💎 IMPELLER DIRECT DRAW_RAW_POINTS',
    '🚀 SIMD 4-LANE PARTICLE PHYSICS',
    '💥 HYPER COMBO MULTIPLIER UP!',
    '⚠️ DREADNOUGHT SQUADRON DETECTED!',
  ];

  final SoaProjectilePool projectiles;
  final SoaEnemyPool enemies;
  final SoaSparkPool sparks;

  late ZeroParticleController _particleCtrl;
  final ZeroConfettiController confettiCtrl;
  final ZeroRippleController rippleCtrl;
  final ZeroDanmakuController danmakuCtrl;
  final ZeroViewportController gridViewportCtrl;
  final ZeroJoystickController joystickCtrl;
  final ZeroChartController frameChartCtrl;
  final ZeroSpectrumController spectrumCtrl;

  // Zero-Rebuild Reactive Telemetry & HUD Notifiers
  final ZeroIntNotifier scoreNotifier = ZeroIntNotifier(0);
  final ZeroIntNotifier killCountNotifier = ZeroIntNotifier(0);
  final ZeroIntNotifier comboNotifier = ZeroIntNotifier(1);
  final ZeroIntNotifier waveNotifier = ZeroIntNotifier(1);
  final ZeroIntNotifier activeEntitiesNotifier = ZeroIntNotifier(0);
  final ZeroIntNotifier dZeroRebuildsNotifier = ZeroIntNotifier(0);
  final ZeroIntNotifier flutterRebuildsNotifier = ZeroIntNotifier(0);
  final ZeroIntNotifier flutterHeapAllocsNotifier = ZeroIntNotifier(0);

  final ZeroDoubleNotifier hpRatioNotifier = ZeroDoubleNotifier(1.0);
  final ZeroDoubleNotifier overdriveRatioNotifier = ZeroDoubleNotifier(0.45);
  final ZeroDoubleNotifier weaponHeatNotifier = ZeroDoubleNotifier(0.2);
  final ZeroDoubleNotifier rssMemoryMbNotifier = ZeroDoubleNotifier(48.0);
  final ZeroDoubleNotifier frameTimeMsNotifier = ZeroDoubleNotifier(8.3);
  final ValueNotifier<double> sparkIntensitySlider = ValueNotifier<double>(1.0);

  final List<double> _spectrumScratch = List<double>.filled(24, 0.0, growable: false);
  final math.Random _rng;

  GameEngineMode _engineMode = GameEngineMode.dZero;
  ParticleStressPreset _preset = ParticleStressPreset.normal;
  bool _autoPilot = true;
  bool _isPaused = false;
  bool _isDisposed = false;

  // Arena & Player State
  double _arenaWidth = 720.0;
  double _arenaHeight = 460.0;
  double _playerX = 360.0;
  double _playerY = 230.0;
  double _playerVx = 0.0;
  double _playerVy = 0.0;
  double _aimAngle = 0.0;
  double _keyDx = 0.0;
  double _keyDy = 0.0;
  bool _pointerAimActive = false;
  double _pointerX = 360.0;
  double _pointerY = 100.0;

  double _simTime = 0.0;
  double _fireCooldown = 0.0;
  double _spawnCooldown = 0.25;
  double _novaRingProgress = 0.0;
  double _shieldFlash = 0.0;
  double _audioPulse = 0.0;
  int _tickCount = 0;

  ZeroGameController({math.Random? random})
      : _rng = random ?? math.Random(77),
        projectiles = SoaProjectilePool(capacity: 640),
        enemies = SoaEnemyPool(capacity: 96),
        sparks = SoaSparkPool(capacity: 2400, random: random),
        confettiCtrl = ZeroConfettiController(capacity: 360, random: random),
        rippleCtrl = ZeroRippleController(capacity: 24),
        danmakuCtrl = ZeroDanmakuController(
          capacity: 32,
          textStyle: const TextStyle(
            color: Color(0xFF00FF88),
            fontSize: 13.0,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
        gridViewportCtrl = ZeroViewportController(),
        joystickCtrl = ZeroJoystickController(),
        frameChartCtrl = ZeroChartController(capacity: 96),
        spectrumCtrl = ZeroSpectrumController(binCount: 24) {
    _particleCtrl = ZeroParticleController(
      capacity: _preset.ambientParticles,
      config: const ZeroParticleConfig(
        gravity: 35.0,
        bounce: 0.92,
        friction: 0.999,
        maxSpeed: 210.0,
      ),
    );
    _particleCtrl.ensureInitialized(width: _arenaWidth, height: _arenaHeight);
    _seedInitialWave();
    _syncEntityCount();
  }

  // Safe Getters (Post-dispose safe)
  bool get isDisposed => _isDisposed;
  GameEngineMode get engineMode => _isDisposed ? GameEngineMode.dZero : _engineMode;
  ParticleStressPreset get preset => _isDisposed ? ParticleStressPreset.normal : _preset;
  bool get autoPilot => _isDisposed ? false : _autoPilot;
  bool get isPaused => _isDisposed ? true : _isPaused;
  ZeroParticleController get particleCtrl => _particleCtrl;

  double get arenaWidth => _isDisposed ? 0.0 : _arenaWidth;
  double get arenaHeight => _isDisposed ? 0.0 : _arenaHeight;
  double get playerX => _isDisposed ? 0.0 : _playerX;
  double get playerY => _isDisposed ? 0.0 : _playerY;
  double get aimAngle => _isDisposed ? 0.0 : _aimAngle;
  double get novaRingProgress => _isDisposed ? 0.0 : _novaRingProgress;
  double get shieldFlash => _isDisposed ? 0.0 : _shieldFlash;
  double get simTime => _isDisposed ? 0.0 : _simTime;

  void _seedInitialWave() {
    for (int i = 0; i < 10; i++) {
      _spawnSingleEnemy(forceBoss: i == 9);
    }
    for (int i = 0; i < 32; i++) {
      frameChartCtrl.push(8.3);
    }
  }

  /// Updates arena bounds when layout changes.
  void updateArenaSize(double width, double height) {
    if (_isDisposed || width <= 0.0 || height <= 0.0) return;
    _arenaWidth = width;
    _arenaHeight = height;
    _playerX = _playerX.clamp(24.0, width - 24.0);
    _playerY = _playerY.clamp(24.0, height - 24.0);
    danmakuCtrl.configureViewport(width, height);
  }

  /// Switches between [GameEngineMode.dZero] and [GameEngineMode.flutter] in real time
  /// while preserving all active entities, score, and particles.
  void setEngineMode(GameEngineMode mode) {
    if (_isDisposed || _engineMode == mode) return;
    _engineMode = mode;
    danmakuCtrl.emit(
      mode == GameEngineMode.dZero
          ? '⚡️ SWITCHED TO D-ZERO ENGINE (0 REBUILDS)'
          : '❌ SWITCHED TO FLUTTER ENGINE (setState + OOP)',
      speed: 145.0,
    );
    notifyListeners();
  }

  /// Toggles between D-Zero and standard Flutter rendering engines.
  void toggleEngineMode() {
    if (_isDisposed) return;
    final GameEngineMode next = _engineMode == GameEngineMode.dZero
        ? GameEngineMode.flutter
        : GameEngineMode.dZero;
    setEngineMode(next);
  }

  /// Changes the particle/bullet load preset.
  void applyPreset(ParticleStressPreset newPreset) {
    if (_isDisposed || _preset == newPreset) return;
    _preset = newPreset;
    final ZeroParticleController oldCtrl = _particleCtrl;
    _particleCtrl = ZeroParticleController(
      capacity: newPreset.ambientParticles,
      config: const ZeroParticleConfig(
        gravity: 35.0,
        bounce: 0.92,
        friction: 0.999,
        maxSpeed: 210.0,
      ),
    );
    _particleCtrl.ensureInitialized(width: _arenaWidth, height: _arenaHeight);
    oldCtrl.dispose();
    sparkIntensitySlider.value = newPreset.sparkMultiplier.clamp(0.5, 4.0);
    _syncEntityCount();
    notifyListeners();
  }

  /// Toggles AI auto-pilot mode.
  void setAutoPilot(bool enabled) {
    if (_isDisposed || _autoPilot == enabled) return;
    _autoPilot = enabled;
    notifyListeners();
  }

  /// Toggles pause state.
  void togglePause() {
    if (_isDisposed) return;
    _isPaused = !_isPaused;
    notifyListeners();
  }

  /// Sets directional keyboard input vector (`-1.0..1.0`).
  void setKeyboardVector(double dx, double dy) {
    if (_isDisposed) return;
    _keyDx = dx.clamp(-1.0, 1.0);
    _keyDy = dy.clamp(-1.0, 1.0);
  }

  /// Updates manual pointer aim target and triggers a ripple on tap/drag.
  void setPointerAim(double x, double y, {bool active = true}) {
    if (_isDisposed) return;
    _pointerAimActive = active;
    _pointerX = x;
    _pointerY = y;
  }

  /// Resets comparative telemetry counters.
  void resetTelemetryCounters() {
    if (_isDisposed) return;
    dZeroRebuildsNotifier.value = 0;
    flutterRebuildsNotifier.value = 0;
    flutterHeapAllocsNotifier.value = 0;
  }

  /// Unleashes the Overdrive Nova super-attack: 72 radial bolts, multi-ripples,
  /// confetti explosion, spark storm, and screen-wide enemy damage.
  void triggerOverdriveNova() {
    if (_isDisposed) return;
    _novaRingProgress = 0.01;
    _audioPulse = 1.0;
    overdriveRatioNotifier.value = 0.05;

    const int boltCount = 72;
    for (int i = 0; i < boltCount; i++) {
      final double theta = (i / boltCount) * math.pi * 2.0;
      projectiles.spawn(
        px: _playerX,
        py: _playerY,
        pvx: math.cos(theta) * 560.0,
        pvy: math.sin(theta) * 560.0,
        teamId: 2,
        lifespan: 1.5,
      );
    }

    sparks.emitBurst(
      ox: _playerX,
      oy: _playerY,
      count: _scaledSparkCount(220),
      maxSpeed: 520.0,
    );
    confettiCtrl.burst(origin: Offset(_playerX, _playerY), count: 90);
    rippleCtrl.trigger(_playerX, _playerY);
    danmakuCtrl.emit('💥 OVERDRIVE NOVA UNLEASHED! 72x PLASMA BURST!', speed: 165.0);
    _damageAllEnemiesInNova();
    _syncEntityCount();
  }

  void _damageAllEnemiesInNova() {
    for (int i = 0; i < enemies.capacity; i++) {
      if (enemies.active[i] != 0) {
        final double ex = enemies.x[i];
        final double ey = enemies.y[i];
        if (enemies.applyDamage(i, 45.0)) {
          _onEnemyDestroyed(ex, ey, enemies.kind[i]);
        }
      }
    }
  }

  /// Instant stress button: spawns an enemy squadron + massive particle/confetti/ripple burst.
  void spawnChaosBurst() {
    if (_isDisposed) return;
    for (int i = 0; i < 12; i++) {
      _spawnSingleEnemy(forceBoss: i == 0);
    }
    final double cx = _arenaWidth * 0.5;
    final double cy = _arenaHeight * 0.5;
    sparks.emitBurst(ox: cx, oy: cy, count: _scaledSparkCount(360), maxSpeed: 480.0);
    confettiCtrl.burst(origin: Offset(cx, cy), count: 120);
    rippleCtrl.trigger(cx, cy);
    rippleCtrl.trigger(cx * 0.5, cy * 0.6);
    rippleCtrl.trigger(cx * 1.5, cy * 1.4);
    danmakuCtrl.emit('🔥 CHAOS STRESS BURST (+500 SPARKS & SWARM)!', speed: 155.0);
    _audioPulse = 1.0;
    _syncEntityCount();
  }

  int _scaledSparkCount(int baseCount) {
    final double mult = sparkIntensitySlider.value.clamp(0.5, 4.0);
    return (baseCount * mult).round();
  }

  /// Advances one frame of the game world and telemetry in-place.
  void step(double dt) {
    if (_isDisposed || _isPaused) return;
    final double safeDt = dt.clamp(0.001, 0.05);
    _simTime += safeDt;
    _tickCount++;

    _stepPlayerMovementAndAim(safeDt);
    _stepPlayerWeapons(safeDt);
    _stepEnemySpawningAndAi(safeDt);
    projectiles.step(safeDt, _arenaWidth, _arenaHeight);
    _resolveCollisions();
    sparks.step(safeDt);
    _stepEffectsAndTelemetry(safeDt);
  }

  void _stepPlayerMovementAndAim(double dt) {
    double moveX = joystickCtrl.dx + _keyDx;
    double moveY = joystickCtrl.dy + _keyDy;
    final bool hasManualMove = (moveX * moveX + moveY * moveY) > 0.01;

    if (!hasManualMove && _autoPilot) {
      final double orbitA = _simTime * 1.65;
      final double targetX = _arenaWidth * 0.5 + math.cos(orbitA) * (_arenaWidth * 0.28);
      final double targetY = _arenaHeight * 0.5 + math.sin(orbitA * 1.3) * (_arenaHeight * 0.26);
      moveX = ((targetX - _playerX) * 0.04).clamp(-1.0, 1.0);
      moveY = ((targetY - _playerY) * 0.04).clamp(-1.0, 1.0);
    }

    const double maxSpeed = 290.0;
    _playerVx = moveX.clamp(-1.0, 1.0) * maxSpeed;
    _playerVy = moveY.clamp(-1.0, 1.0) * maxSpeed;
    _playerX = (_playerX + _playerVx * dt).clamp(24.0, _arenaWidth - 24.0);
    _playerY = (_playerY + _playerVy * dt).clamp(24.0, _arenaHeight - 24.0);

    _updateAimAngle();
    gridViewportCtrl.pan(-_playerVx * dt * 0.35, -_playerVy * dt * 0.35);
  }

  void _updateAimAngle() {
    if (_pointerAimActive) {
      _aimAngle = math.atan2(_pointerY - _playerY, _pointerX - _playerX);
      return;
    }
    final int nearestIdx = _findNearestEnemyIndex();
    if (nearestIdx >= 0) {
      _aimAngle = math.atan2(
        enemies.y[nearestIdx] - _playerY,
        enemies.x[nearestIdx] - _playerX,
      );
      return;
    }
    _aimAngle = (_simTime * 2.4) % (math.pi * 2.0);
  }

  int _findNearestEnemyIndex() {
    int bestIdx = -1;
    double bestDistSq = 1e12;
    for (int i = 0; i < enemies.capacity; i++) {
      if (enemies.active[i] != 0) {
        final double dx = enemies.x[i] - _playerX;
        final double dy = enemies.y[i] - _playerY;
        final double dSq = dx * dx + dy * dy;
        if (dSq < bestDistSq) {
          bestDistSq = dSq;
          bestIdx = i;
        }
      }
    }
    return bestIdx;
  }

  void _stepPlayerWeapons(double dt) {
    _fireCooldown -= dt;
    if (_fireCooldown > 0.0) return;
    _fireCooldown = 0.065;

    // Triple spread plasma stream
    const double boltSpeed = 640.0;
    for (int s = -1; s <= 1; s++) {
      final double spreadAngle = _aimAngle + s * 0.11;
      projectiles.spawn(
        px: _playerX + math.cos(spreadAngle) * 16.0,
        py: _playerY + math.sin(spreadAngle) * 16.0,
        pvx: math.cos(spreadAngle) * boltSpeed,
        pvy: math.sin(spreadAngle) * boltSpeed,
        teamId: 0,
        lifespan: 1.25,
      );
    }

    // Thruster exhaust spark
    final double backAngle = _aimAngle + math.pi + (_rng.nextDouble() - 0.5) * 0.5;
    sparks.emitBurst(
      ox: _playerX + math.cos(backAngle) * 12.0,
      oy: _playerY + math.sin(backAngle) * 12.0,
      count: 2,
      preferredBucket: 0,
      maxSpeed: 130.0,
    );

    weaponHeatNotifier.value = (0.45 + 0.35 * math.sin(_simTime * 6.0)).clamp(0.1, 0.95);
    if (_autoPilot && overdriveRatioNotifier.value >= 1.0) {
      triggerOverdriveNova();
    }
  }

  void _stepEnemySpawningAndAi(double dt) {
    _spawnCooldown -= dt;
    if (_spawnCooldown <= 0.0) {
      _spawnCooldown = _preset.spawnIntervalSec;
      if (enemies.activeCount < enemies.capacity - 4) {
        _spawnSingleEnemy(forceBoss: (_tickCount % 180 == 0));
      }
    }

    for (int i = 0; i < enemies.capacity; i++) {
      if (enemies.active[i] != 0) {
        _stepSingleEnemyAi(i, dt);
      }
    }
  }

  static const List<double> _enemyHpByKind = <double>[12.0, 26.0, 95.0];
  static const List<double> _enemyRadiusByKind = <double>[11.0, 15.0, 24.0];

  void _spawnSingleEnemy({bool forceBoss = false}) {
    final Offset spawnPos = _randomEdgeSpawnPoint();
    final int kind = _selectEnemyKind(forceBoss);
    enemies.spawn(
      ex: spawnPos.dx,
      ey: spawnPos.dy,
      enemyKind: kind,
      hitPoints: _enemyHpByKind[kind],
      bodyRadius: _enemyRadiusByKind[kind],
    );
  }

  Offset _randomEdgeSpawnPoint() {
    final int edge = _rng.nextInt(4);
    final double rx = _rng.nextDouble() * _arenaWidth;
    final double ry = _rng.nextDouble() * _arenaHeight;
    if (edge == 0) return Offset(rx, 16.0);
    if (edge == 1) return Offset(rx, _arenaHeight - 16.0);
    if (edge == 2) return Offset(16.0, ry);
    return Offset(_arenaWidth - 16.0, ry);
  }

  int _selectEnemyKind(bool forceBoss) {
    if (forceBoss) return 2;
    return _rng.nextInt(10) < 3 ? 1 : 0;
  }

  void _stepSingleEnemyAi(int i, double dt) {
    final double dx = _playerX - enemies.x[i];
    final double dy = _playerY - enemies.y[i];
    final double dist = math.sqrt(dx * dx + dy * dy);
    final double invDist = dist > 1.0 ? (1.0 / dist) : 0.0;
    final int k = enemies.kind[i];
    final double speed = k == 2 ? 52.0 : (k == 1 ? 85.0 : 125.0);

    enemies.vx[i] = dx * invDist * speed;
    enemies.vy[i] = dy * invDist * speed;
    enemies.x[i] = (enemies.x[i] + enemies.vx[i] * dt).clamp(16.0, _arenaWidth - 16.0);
    enemies.y[i] = (enemies.y[i] + enemies.vy[i] * dt).clamp(16.0, _arenaHeight - 16.0);
    enemies.spin[i] = (enemies.spin[i] + dt * (k == 2 ? 1.5 : 3.8)) % (math.pi * 2.0);

    enemies.fireTimer[i] -= dt;
    if (enemies.fireTimer[i] <= 0.0) {
      _fireEnemyProjectiles(i, k, dx, dy);
    }
  }

  void _fireEnemyProjectiles(int i, int k, double dx, double dy) {
    final double ex = enemies.x[i];
    final double ey = enemies.y[i];
    if (k == 2) {
      enemies.fireTimer[i] = 1.1;
      final double baseAngle = enemies.spin[i];
      for (int b = 0; b < 8; b++) {
        final double theta = baseAngle + (b / 8) * math.pi * 2.0;
        projectiles.spawn(
          px: ex,
          py: ey,
          pvx: math.cos(theta) * 195.0,
          pvy: math.sin(theta) * 195.0,
          teamId: 1,
          lifespan: 2.8,
        );
      }
      return;
    }
    enemies.fireTimer[i] = k == 1 ? 1.35 : 2.1;
    final double aim = math.atan2(dy, dx);
    projectiles.spawn(
      px: ex,
      py: ey,
      pvx: math.cos(aim) * 220.0,
      pvy: math.sin(aim) * 220.0,
      teamId: 1,
      lifespan: 2.4,
    );
  }

  void _resolveCollisions() {
    for (int p = 0; p < projectiles.capacity; p++) {
      if (projectiles.active[p] != 0) {
        _checkProjectileCollision(p);
      }
    }
  }

  void _checkProjectileCollision(int p) {
    final int teamId = projectiles.team[p];
    final double px = projectiles.x[p];
    final double py = projectiles.y[p];

    if (teamId == 1) {
      _checkEnemyOrbAgainstPlayer(p, px, py);
      return;
    }
    _checkPlayerBoltAgainstEnemies(p, px, py, teamId == 2 ? 22.0 : 10.0);
  }

  void _checkEnemyOrbAgainstPlayer(int p, double px, double py) {
    final double dx = px - _playerX;
    final double dy = py - _playerY;
    if (dx * dx + dy * dy > 225.0) return;

    projectiles.killAt(p);
    _shieldFlash = 1.0;
    sparks.emitBurst(
      ox: px,
      oy: py,
      count: _scaledSparkCount(16),
      preferredBucket: 1,
      maxSpeed: 240.0,
    );
    rippleCtrl.trigger(_playerX, _playerY);

    final double nextHp = hpRatioNotifier.value - 0.04;
    if (nextHp <= 0.15) {
      hpRatioNotifier.value = 1.0;
      comboNotifier.value = 1;
      danmakuCtrl.emit('🛡️ AUTO-SHIELD REBOOTED!', speed: 140.0);
    } else {
      hpRatioNotifier.value = nextHp;
    }
  }

  void _checkPlayerBoltAgainstEnemies(int p, double px, double py, double dmg) {
    for (int e = 0; e < enemies.capacity; e++) {
      if (enemies.active[e] != 0) {
        final double dx = px - enemies.x[e];
        final double dy = py - enemies.y[e];
        final double hitR = enemies.radius[e] + 6.0;
        if (dx * dx + dy * dy <= hitR * hitR) {
          projectiles.killAt(p);
          _onEnemyHit(e, px, py, dmg);
          return;
        }
      }
    }
  }

  void _onEnemyHit(int e, double hitX, double hitY, double dmg) {
    final double ex = enemies.x[e];
    final double ey = enemies.y[e];
    final int enemyKind = enemies.kind[e];
    sparks.emitBurst(
      ox: hitX,
      oy: hitY,
      count: _scaledSparkCount(8),
      preferredBucket: 0,
      maxSpeed: 210.0,
    );
    if (enemies.applyDamage(e, dmg)) {
      _onEnemyDestroyed(ex, ey, enemyKind);
    }
  }

  void _onEnemyDestroyed(double ex, double ey, int enemyKind) {
    final int kills = killCountNotifier.value + 1;
    killCountNotifier.value = kills;
    final int combo = (comboNotifier.value + 1).clamp(1, 999);
    comboNotifier.value = combo;
    final int points = (enemyKind == 2 ? 500 : (enemyKind == 1 ? 150 : 60)) * combo;
    scoreNotifier.add(points);
    waveNotifier.value = 1 + (kills ~/ 20);

    final double nextOd = (overdriveRatioNotifier.value + 0.055).clamp(0.0, 1.0);
    overdriveRatioNotifier.value = nextOd;
    _audioPulse = 0.85;

    final int sparkBurst = enemyKind == 2 ? 95 : 28;
    sparks.emitBurst(
      ox: ex,
      oy: ey,
      count: _scaledSparkCount(sparkBurst),
      preferredBucket: enemyKind == 2 ? 3 : 2,
      maxSpeed: enemyKind == 2 ? 420.0 : 290.0,
    );
    confettiCtrl.burst(
      origin: Offset(ex, ey),
      count: enemyKind == 2 ? 64 : 18,
    );
    if (enemyKind == 2 || kills % 6 == 0) {
      rippleCtrl.trigger(ex, ey);
    }
    if (kills % 10 == 0) {
      final String msg = _killAnnouncements[(kills ~/ 10) % _killAnnouncements.length];
      danmakuCtrl.emit('$msg (x$combo)', speed: 135.0);
    }
  }

  void _stepEffectsAndTelemetry(double dt) {
    if (_novaRingProgress > 0.0) {
      _novaRingProgress += dt * 1.4;
      if (_novaRingProgress >= 1.0) {
        _novaRingProgress = 0.0;
      }
    }
    if (_shieldFlash > 0.0) {
      _shieldFlash = (_shieldFlash - dt * 3.0).clamp(0.0, 1.0);
    }
    _audioPulse = (_audioPulse - dt * 2.5).clamp(0.0, 1.0);

    _updateSpectrumBins();
    _syncEntityCount();

    if (_engineMode == GameEngineMode.flutter) {
      flutterRebuildsNotifier.add(1);
      final int frameAllocs =
          _particleCtrl.capacity + activeEntitiesNotifier.value * 3 + 48;
      flutterHeapAllocsNotifier.add(frameAllocs);
    }

    if (_tickCount % 4 == 0) {
      frameChartCtrl.push(frameTimeMsNotifier.value);
    }
    if (_tickCount % 20 == 0) {
      _sampleRssMemory();
    }
  }

  void _updateSpectrumBins() {
    final double basePhase = _simTime * 7.5;
    for (int i = 0; i < _spectrumScratch.length; i++) {
      final double wave = 0.35 + 0.30 * math.sin(basePhase + i * 0.45);
      final double boost = _audioPulse * (1.0 - (i / _spectrumScratch.length) * 0.5);
      _spectrumScratch[i] = (wave + boost).clamp(0.05, 0.98);
    }
    spectrumCtrl.updateBins(_spectrumScratch);
  }

  void _syncEntityCount() {
    final int total = _particleCtrl.capacity +
        projectiles.activeCount +
        enemies.activeCount +
        sparks.activeCount +
        confettiCtrl.activeCount;
    activeEntitiesNotifier.value = total;
  }

  void _sampleRssMemory() {
    try {
      rssMemoryMbNotifier.value = ProcessInfo.currentRss / (1024.0 * 1024.0);
    } catch (_) {
      rssMemoryMbNotifier.value = 48.0;
    }
  }

  /// Records current frame time in ms from the active stage renderer.
  void recordFrameTimeMs(double ms) {
    if (_isDisposed || ms <= 0.0) return;
    frameTimeMsNotifier.value =
        (frameTimeMsNotifier.value * 0.85) + (ms.clamp(1.0, 100.0) * 0.15);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    projectiles.dispose();
    enemies.dispose();
    sparks.dispose();
    _particleCtrl.dispose();
    confettiCtrl.dispose();
    rippleCtrl.dispose();
    danmakuCtrl.dispose();
    gridViewportCtrl.dispose();
    joystickCtrl.dispose();
    frameChartCtrl.dispose();
    spectrumCtrl.dispose();
    scoreNotifier.dispose();
    killCountNotifier.dispose();
    comboNotifier.dispose();
    waveNotifier.dispose();
    activeEntitiesNotifier.dispose();
    dZeroRebuildsNotifier.dispose();
    flutterRebuildsNotifier.dispose();
    flutterHeapAllocsNotifier.dispose();
    hpRatioNotifier.dispose();
    overdriveRatioNotifier.dispose();
    weaponHeatNotifier.dispose();
    rssMemoryMbNotifier.dispose();
    frameTimeMsNotifier.dispose();
    sparkIntensitySlider.dispose();
    super.dispose();
  }
}

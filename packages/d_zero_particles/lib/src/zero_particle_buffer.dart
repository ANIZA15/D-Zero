import 'dart:math';
import 'dart:typed_data';

/// A flat, typed-data buffer for high-performance zero-allocation particle simulation.
///
/// Particle positions are stored in a contiguous [Float32List] in `[x0, y0, x1, y1, ...]` layout.
/// This flat layout allows:
/// 1. Zero-copy, direct passing to `Canvas.drawRawPoints`.
/// 2. 4-wide SIMD physics updates via a pre-allocated [Float32x4List] view processing
///    2 particles (`[x0, y0, x1, y1]`) per instruction with branchless boundary reflection.
class ZeroParticleBuffer {
  /// Maximum number of particles this buffer can hold.
  final int capacity;

  /// Flattened position buffer: `[x0, y0, x1, y1, ...]`.
  /// Length is `capacity * 2`.
  final Float32List positions;

  /// Flattened velocity buffer: `[vx0, vy0, vx1, vy1, ...]`.
  /// Length is `capacity * 2`.
  final Float32List velocities;

  /// Flattened lifespan / state buffer: `[life0, life1, ...]`.
  /// Length is `capacity`.
  final Float32List lifespans;

  final Float32x4List _posSimd;
  final Float32x4List _velSimd;

  /// Creates a [ZeroParticleBuffer] with the specified [capacity].
  factory ZeroParticleBuffer(int capacity) {
    final int safeCap = capacity > 0 ? capacity : 0;
    final int paddedCap = (safeCap + 1) & ~1;
    final Float32List posBacking = Float32List(paddedCap * 2);
    final Float32List velBacking = Float32List(paddedCap * 2);
    final Float32List posView = Float32List.sublistView(posBacking, 0, safeCap * 2);
    final Float32List velView = Float32List.sublistView(velBacking, 0, safeCap * 2);
    final Float32x4List posSimd = posBacking.buffer.asFloat32x4List();
    final Float32x4List velSimd = velBacking.buffer.asFloat32x4List();
    return ZeroParticleBuffer._(
      capacity: safeCap,
      positions: posView,
      velocities: velView,
      lifespans: Float32List(safeCap),
      posSimd: posSimd,
      velSimd: velSimd,
    );
  }

  ZeroParticleBuffer._({
    required this.capacity,
    required this.positions,
    required this.velocities,
    required this.lifespans,
    required Float32x4List posSimd,
    required Float32x4List velSimd,
  })  : _posSimd = posSimd,
        _velSimd = velSimd;

  /// Initializes all particles with random positions and velocities within given bounds.
  void initRandom({
    required double width,
    required double height,
    Random? random,
    double maxSpeed = 150.0,
  }) {
    final Random rng = random ?? Random();
    final double safeWidth = width > 0 ? width : 100.0;
    final double safeHeight = height > 0 ? height : 100.0;

    for (int i = 0; i < capacity; i++) {
      final int posIdx = i << 1;
      positions[posIdx] = rng.nextDouble() * safeWidth;
      positions[posIdx + 1] = rng.nextDouble() * safeHeight;

      final double angle = rng.nextDouble() * 2.0 * pi;
      final double speed = (rng.nextDouble() * 0.8 + 0.2) * maxSpeed;
      velocities[posIdx] = cos(angle) * speed;
      velocities[posIdx + 1] = sin(angle) * speed;

      lifespans[i] = rng.nextDouble();
    }
  }

  /// Updates particle physics in-place using 4-lane SIMD ([Float32x4]) without heap allocations.
  ///
  /// When [useSimd] is true (default), 2 particles are stepped simultaneously per loop iteration
  /// using branchless vector comparisons (`lessThan | greaterThan` -> `select` -> `clamp`).
  void step({
    required double dt,
    required double width,
    required double height,
    double gravity = 98.0,
    double bounce = 0.8,
    double friction = 0.999,
    bool useSimd = true,
  }) {
    if (capacity <= 0) return;
    final double safeWidth = width > 0 ? width : 100.0;
    final double safeHeight = height > 0 ? height : 100.0;
    final double gravityDelta = gravity * dt;

    if (useSimd) {
      _stepSimd(
        dt: dt,
        width: safeWidth,
        height: safeHeight,
        gravityDelta: gravityDelta,
        bounce: bounce,
        friction: friction,
      );
      return;
    }

    for (int i = 0; i < capacity; i++) {
      _updateSingleParticle(
        posIdx: i << 1,
        dt: dt,
        width: safeWidth,
        height: safeHeight,
        gravityDelta: gravityDelta,
        bounce: bounce,
        friction: friction,
      );
    }
  }

  @pragma('vm:prefer-inline')
  void _stepSimd({
    required double dt,
    required double width,
    required double height,
    required double gravityDelta,
    required double bounce,
    required double friction,
  }) {
    final Float32x4List p4 = _posSimd;
    final Float32x4List v4 = _velSimd;
    final Float32x4 gd = Float32x4(0.0, gravityDelta, 0.0, gravityDelta);
    final Float32x4 dt4 = Float32x4.splat(dt);
    final Float32x4 lo = Float32x4.zero();
    final Float32x4 hi = Float32x4(width, height, width, height);
    final Float32x4 negBounce = Float32x4.splat(-bounce);
    final Float32x4 fr4 = Float32x4.splat(friction);

    final int quadCount = p4.length;
    for (int i = 0; i < quadCount; i++) {
      Float32x4 vel = v4[i] + gd;
      final Float32x4 pos = p4[i] + vel * dt4;
      final Int32x4 outOfBounds = pos.lessThan(lo) | pos.greaterThan(hi);
      vel = outOfBounds.select(vel * negBounce, vel);
      p4[i] = pos.clamp(lo, hi);
      v4[i] = vel * fr4;
    }
  }

  void _updateSingleParticle({
    required int posIdx,
    required double dt,
    required double width,
    required double height,
    required double gravityDelta,
    required double bounce,
    required double friction,
  }) {
    final int xIdx = posIdx;
    final int yIdx = posIdx + 1;

    double vx = velocities[xIdx];
    double vy = velocities[yIdx] + gravityDelta;

    double x = positions[xIdx] + vx * dt;
    double y = positions[yIdx] + vy * dt;

    if (x < 0.0) {
      x = 0.0;
      vx = -vx * bounce;
    } else if (x > width) {
      x = width;
      vx = -vx * bounce;
    }

    if (y < 0.0) {
      y = 0.0;
      vy = -vy * bounce;
    } else if (y > height) {
      y = height;
      vy = -vy * bounce;
    }

    velocities[xIdx] = vx * friction;
    velocities[yIdx] = vy * friction;
    positions[xIdx] = x;
    positions[yIdx] = y;
  }
}

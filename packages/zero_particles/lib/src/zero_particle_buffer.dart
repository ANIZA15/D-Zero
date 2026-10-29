import 'dart:math';
import 'dart:typed_data';

/// A flat, typed-data buffer for high-performance zero-allocation particle simulation.
///
/// Particle positions are stored in a contiguous [Float32List] in `[x0, y0, x1, y1, ...]` layout.
/// This flat layout allows zero-copy, direct passing to `Canvas.drawRawPoints`.
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

  /// Creates a [ZeroParticleBuffer] with the specified [capacity].
  ZeroParticleBuffer(this.capacity)
      : positions = Float32List(capacity * 2),
        velocities = Float32List(capacity * 2),
        lifespans = Float32List(capacity);

  /// Initializes all particles with random positions and velocities within given bounds.
  void initRandom({
    required double width,
    required double height,
    Random? random,
    double maxSpeed = 150.0,
  }) {
    final rng = random ?? Random();
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

  /// Updates particle physics in-place without generating any heap allocations.
  void step({
    required double dt,
    required double width,
    required double height,
    double gravity = 98.0,
    double bounce = 0.8,
    double friction = 0.999,
  }) {
    final double safeWidth = width > 0 ? width : 100.0;
    final double safeHeight = height > 0 ? height : 100.0;
    final double gravityDelta = gravity * dt;

    for (int i = 0; i < capacity; i++) {
      final int posIdx = i << 1;
      _updateSingleParticle(
        posIdx: posIdx,
        dt: dt,
        width: safeWidth,
        height: safeHeight,
        gravityDelta: gravityDelta,
        bounce: bounce,
        friction: friction,
      );
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

    // Boundary bounce handling
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

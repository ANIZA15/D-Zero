import 'dart:math';
import 'package:flutter/foundation.dart';
import 'zero_particle_buffer.dart';

/// Configuration options for the particle simulation physics.
@immutable
class ZeroParticleConfig {
  /// Downward gravitational acceleration in pixels/s^2.
  final double gravity;

  /// Restitution coefficient when bouncing against bounds (0.0 = inelastic, 1.0 = elastic).
  final double bounce;

  /// Air friction applied per tick (e.g. 0.999).
  final double friction;

  /// Maximum initial speed in pixels/s.
  final double maxSpeed;

  const ZeroParticleConfig({
    this.gravity = 98.0,
    this.bounce = 0.85,
    this.friction = 0.999,
    this.maxSpeed = 160.0,
  });
}

/// Controller managing the particle simulation state and lifetime.
///
/// Designed with strict resilience:
/// - Double dispose is safe and ignored.
/// - Accessing methods post-dispose is safe and does not throw or crash.
class ZeroParticleController with ChangeNotifier {
  static final ZeroParticleBuffer _emptyBuffer = ZeroParticleBuffer(0);

  final int capacity;
  final ZeroParticleConfig config;
  ZeroParticleBuffer? _buffer;
  bool _isDisposed = false;
  bool _isInitialized = false;

  /// Creates a [ZeroParticleController] with [capacity] particles and optional [config].
  ZeroParticleController({
    required this.capacity,
    this.config = const ZeroParticleConfig(),
  }) {
    _buffer = ZeroParticleBuffer(capacity);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether particles have been initialized.
  bool get isInitialized => _isInitialized;

  /// The underlying [ZeroParticleBuffer]. Returns a shared empty buffer if disposed (zero allocation).
  ZeroParticleBuffer get buffer {
    if (_isDisposed || _buffer == null) {
      return _emptyBuffer;
    }
    return _buffer!;
  }

  /// Initializes particle positions and velocities if not already initialized.
  void ensureInitialized({
    required double width,
    required double height,
    Random? random,
  }) {
    if (_isDisposed || _isInitialized || _buffer == null) return;
    _buffer!.initRandom(
      width: width,
      height: height,
      random: random,
      maxSpeed: config.maxSpeed,
    );
    _isInitialized = true;
  }

  /// Resets all particles to new random states.
  void reset({
    required double width,
    required double height,
    Random? random,
  }) {
    if (_isDisposed || _buffer == null) return;
    _buffer!.initRandom(
      width: width,
      height: height,
      random: random,
      maxSpeed: config.maxSpeed,
    );
    _isInitialized = true;
    notifyListeners();
  }

  /// Advances physics simulation by [dt] seconds.
  void step({
    required double dt,
    required double width,
    required double height,
  }) {
    if (_isDisposed || _buffer == null) return;
    if (!_isInitialized) {
      ensureInitialized(width: width, height: height);
    }
    _buffer!.step(
      dt: dt,
      width: width,
      height: height,
      gravity: config.gravity,
      bounce: config.bounce,
      friction: config.friction,
    );
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _buffer = null;
    super.dispose();
  }
}

import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';
import 'zero_particle_controller.dart';

/// An ultra high-performance, zero-allocation particle rendering widget.
///
/// Directly drives physics simulation and batch draws up to tens of thousands
/// of particles to the Canvas using [Canvas.drawRawPoints] without triggering
/// any Flutter widget rebuilds or GC pressure.
class ZParticles extends ZLeafWidget<RenderZParticles> {
  /// The controller managing the particle state and physics buffer.
  final ZeroParticleController controller;

  /// Whether the particle simulation is running.
  final bool isRunning;

  /// The color of the particles.
  final Color color;

  /// The size/diameter of each particle point in pixels.
  final double pointSize;

  const ZParticles({
    super.key,
    required this.controller,
    this.isRunning = true,
    this.color = const Color(0xFF00FF88),
    this.pointSize = 3.0,
  });

  @override
  RenderZParticles createRenderObject(BuildContext context) {
    return RenderZParticles(
      controller: controller,
      isRunning: isRunning,
      color: color,
      pointSize: pointSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZParticles renderObject) {
    renderObject
      ..controller = controller
      ..isRunning = isRunning
      ..color = color
      ..pointSize = pointSize;
  }
}

/// Backward compatibility alias for [ZParticles].
@Deprecated('Use ZParticles instead.')
typedef ZeroParticles = ZParticles;

/// Internal RenderBox executing direct-to-Canvas particle rendering with Impeller optimizations.
class RenderZParticles extends ZeroRenderBox {
  ZeroParticleController _controller;
  bool _isRunning;
  Color _color;
  double _pointSize;

  late final Paint _paint;
  Duration _lastElapsed = Duration.zero;

  RenderZParticles({
    required ZeroParticleController controller,
    required bool isRunning,
    required Color color,
    required double pointSize,
  })  : _controller = controller,
        _isRunning = isRunning,
        _color = color,
        _pointSize = pointSize,
        super(animatePerFrame: isRunning) {
    _paint = Paint()
      ..color = _color
      ..strokeWidth = _pointSize
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = false;
  }

  ZeroParticleController get controller => _controller;
  set controller(ZeroParticleController value) {
    if (_controller == value) return;
    _controller = value;
    markDirty();
  }

  bool get isRunning => _isRunning;
  set isRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    animatePerFrame = value;
    markDirty();
  }

  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    _paint.color = value;
    markDirty();
  }

  double get pointSize => _pointSize;
  set pointSize(double value) {
    if (_pointSize == value) return;
    _pointSize = value;
    _paint.strokeWidth = value;
    markDirty();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isRunning || _controller.isDisposed) return false;

    final double dt = _calculateDeltaSeconds(elapsed);
    _lastElapsed = elapsed;

    if (size.width > 0 && size.height > 0) {
      _controller.step(
        dt: dt,
        width: size.width,
        height: size.height,
      );
      return true;
    }
    return false;
  }

  double _calculateDeltaSeconds(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      return 1.0 / 60.0;
    }
    final int microDelta = (elapsed - _lastElapsed).inMicroseconds;
    if (microDelta <= 0) {
      return 1.0 / 60.0;
    }
    final double dt = microDelta / 1000000.0;
    // Clamp to 100ms max to prevent tunneling during app pause
    return dt > 0.1 ? 0.1 : dt;
  }

  @override
  void detach() {
    _lastElapsed = Duration.zero;
    super.detach();
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    if (_controller.isDisposed) return;

    final positions = _controller.buffer.positions;
    if (positions.isEmpty) return;

    final Canvas canvas = context.canvas;
    canvas.save();
    if (offset != Offset.zero) {
      canvas.translate(offset.dx, offset.dy);
    }

    // Direct batch-draw all particles to the GPU in a single call!
    canvas.drawRawPoints(PointMode.points, positions, _paint);

    canvas.restore();
  }
}

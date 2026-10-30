import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZJoystick].
typedef ZVirtualPad = ZJoystick;

/// Legacy alias for [ZJoystick].
@Deprecated('Use ZJoystick instead.')
typedef ZeroJoystick = ZJoystick;

/// Zero-allocation controller for [ZJoystick] storing normalized `(dx, dy)` in a [Float32List].
///
/// Safe against post-dispose access and repeated [dispose] calls.
class ZeroJoystickController extends ChangeNotifier {
  final Float32List _vector = Float32List(2);
  bool _isDisposed = false;

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Normalized X axis in `-1.0..1.0` (`0.0` if disposed).
  double get dx => _isDisposed ? 0.0 : _vector[0];

  /// Normalized Y axis in `-1.0..1.0` (`0.0` if disposed).
  double get dy => _isDisposed ? 0.0 : _vector[1];

  /// Euclidean magnitude in `0.0..1.0` (`0.0` if disposed).
  double get magnitude {
    if (_isDisposed) return 0.0;
    final double x = _vector[0];
    final double y = _vector[1];
    return math.sqrt(x * x + y * y).clamp(0.0, 1.0);
  }

  /// Updates the normalized vector `(nx, ny)` clamped to the unit circle.
  void update(double nx, double ny) {
    if (_isDisposed) return;
    double cx = nx;
    double cy = ny;
    final double magSq = cx * cx + cy * cy;
    if (magSq > 1.0) {
      final double invMag = 1.0 / math.sqrt(magSq);
      cx *= invMag;
      cy *= invMag;
    }
    if (_vector[0] == cx && _vector[1] == cy) return;
    _vector[0] = cx;
    _vector[1] = cy;
    notifyListeners();
  }

  /// Resets the joystick vector to `(0.0, 0.0)`.
  void reset() {
    if (_isDisposed) return;
    if (_vector[0] == 0.0 && _vector[1] == 0.0) return;
    _vector[0] = 0.0;
    _vector[1] = 0.0;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _vector[0] = 0.0;
    _vector[1] = 0.0;
    super.dispose();
  }
}

/// A zero-allocation, zero-rebuild virtual analog joystick widget.
class ZJoystick extends ZLeafWidget<RenderZJoystick> {
  /// Joystick vector controller.
  final ZeroJoystickController controller;

  /// Desired outer size of the joystick pad.
  final Size size;

  /// Base ring color.
  final Color baseColor;

  /// Stick thumb color.
  final Color stickColor;

  /// Creates a const [ZJoystick].
  const ZJoystick({
    super.key,
    required this.controller,
    this.size = const Size(120.0, 120.0),
    this.baseColor = const Color(0xFF263238),
    this.stickColor = const Color(0xFF00E5FF),
  });

  @override
  RenderZJoystick createRenderObject(BuildContext context) {
    return RenderZJoystick(
      controller: controller,
      preferredSize: size,
      baseColor: baseColor,
      stickColor: stickColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZJoystick renderObject) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..baseColor = baseColor
      ..stickColor = stickColor;
  }
}

/// Custom [ZeroRenderBox] for [ZJoystick] with zero heap allocations on pointer events.
class RenderZJoystick extends ZeroRenderBox {
  ZeroJoystickController _controller;
  Size _preferredSize;

  final Paint _basePaint = Paint()..style = PaintingStyle.fill;
  final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = const Color(0xFF546E7A);
  final Paint _stickPaint = Paint()..style = PaintingStyle.fill;

  /// Creates a [RenderZJoystick].
  RenderZJoystick({
    required ZeroJoystickController controller,
    required Size preferredSize,
    required Color baseColor,
    required Color stickColor,
  })  : _controller = controller,
        _preferredSize = preferredSize {
    _basePaint.color = baseColor;
    _stickPaint.color = stickColor;
  }

  /// Active joystick controller.
  ZeroJoystickController get controller => _controller;
  set controller(ZeroJoystickController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    markDirty();
  }

  /// Preferred size of the joystick.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Base circle color.
  Color get baseColor => _basePaint.color;
  set baseColor(Color value) {
    if (_basePaint.color == value) return;
    _basePaint.color = value;
    markDirty();
  }

  /// Stick knob color.
  Color get stickColor => _stickPaint.color;
  set stickColor(Color value) {
    if (_stickPaint.color == value) return;
    _stickPaint.color = value;
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markDirty);
  }

  @override
  void detach() {
    _controller.removeListener(markDirty);
    super.detach();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _updateStickFromPointer(event.localPosition.dx, event.localPosition.dy);
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _controller.reset();
    }
  }

  void _updateStickFromPointer(double px, double py) {
    final double cx = size.width * 0.5;
    final double cy = size.height * 0.5;
    final double maxRadius = math.max(1.0, math.min(cx, cy) * 0.7);
    final double nx = (px - cx) / maxRadius;
    final double ny = (py - cy) / maxRadius;
    _controller.update(nx, ny);
  }

  @override
  void performLayout() {
    size = constraints.constrain(_preferredSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double halfW = size.width * 0.5;
    final double halfH = size.height * 0.5;
    final double outerR = math.min(halfW, halfH) - 2.0;
    if (outerR <= 0.0) return;

    final double cx = offset.dx + halfW;
    final double cy = offset.dy + halfH;
    final Offset center = Offset(cx, cy);

    canvas.drawCircle(center, outerR, _basePaint);
    canvas.drawCircle(center, outerR, _ringPaint);

    final double travelR = outerR * 0.65;
    final double stickR = outerR * 0.32;
    final double sx = cx + _controller.dx * travelR;
    final double sy = cy + _controller.dy * travelR;
    canvas.drawCircle(Offset(sx, sy), stickR, _stickPaint);
  }
}

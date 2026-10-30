import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Active Z-prefixed alias for [ZRipple].
typedef ZInkWell = ZRipple;

/// Deprecated legacy alias for [ZRipple].
@Deprecated('Use ZRipple instead.')
typedef ZeroRipple = ZRipple;

/// Fixed-capacity Structure-of-Arrays (SoA) controller for concurrent touch ripples.
///
/// Stores up to [capacity] ripples in contiguous [Float32List] arrays (`x`, `y`, `progress`)
/// with zero heap allocation on `trigger` or `step`.
class ZeroRippleController {
  /// Maximum number of concurrent ripples tracked in the ring buffer.
  final int capacity;

  final Float32List _x;
  final Float32List _y;
  final Float32List _progress;
  final Uint8List _active;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _writeCursor = 0;
  int _activeCount = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroRippleController] with a fixed [capacity] (default 16).
  ZeroRippleController({this.capacity = 16})
      : assert(capacity > 0),
        _x = Float32List(capacity),
        _y = Float32List(capacity),
        _progress = Float32List(capacity),
        _active = Uint8List(capacity);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Number of currently expanding ripples.
  int get activeCount => _isDisposed ? 0 : _activeCount;

  /// Registers a listener notified when a ripple is triggered or cleared.
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Returns whether slot [index] currently holds an active ripple.
  bool isActiveAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return false;
    return _active[index] != 0;
  }

  /// Returns the X coordinate of ripple slot [index].
  double xAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return 0.0;
    return _x[index];
  }

  /// Returns the Y coordinate of ripple slot [index].
  double yAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return 0.0;
    return _y[index];
  }

  /// Returns the normalized progress (`0.0..1.0`) of ripple slot [index].
  double progressAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return 0.0;
    return _progress[index];
  }

  /// Spawns a new ripple at local coordinates ([x], [y]) in O(1) time with 0 allocations.
  void trigger(double x, double y) {
    if (_isDisposed) return;
    final int slot = _writeCursor;
    _writeCursor = (slot + 1) % capacity;
    if (_active[slot] == 0) {
      _active[slot] = 1;
      _activeCount++;
    }
    _x[slot] = x;
    _y[slot] = y;
    _progress[slot] = 0.0;
    _revision.add(1);
  }

  /// Advances all active ripples by [dt] seconds (default speed completes in ~0.55s).
  /// Returns `true` if any ripple was active during this step.
  bool step(double dt, {double speed = 1.8}) {
    if (_isDisposed || _activeCount == 0 || dt <= 0.0) return false;
    final double delta = dt * speed;
    for (int i = 0; i < capacity; i++) {
      if (_active[i] != 0) {
        _stepSlot(i, delta);
      }
    }
    return true;
  }

  void _stepSlot(int index, double delta) {
    final double next = _progress[index] + delta;
    if (next >= 1.0) {
      _progress[index] = 1.0;
      _active[index] = 0;
      _activeCount--;
    } else {
      _progress[index] = next;
    }
  }

  /// Clears all active ripples immediately.
  void clear() {
    if (_isDisposed) return;
    _active.fillRange(0, capacity, 0);
    _progress.fillRange(0, capacity, 0.0);
    _activeCount = 0;
    _writeCursor = 0;
    _revision.add(1);
  }

  /// Disposes the controller and releases listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeCount = 0;
    _revision.dispose();
  }
}

/// A zero-allocation multi-touch ripple surface widget.
///
/// Handles pointer down events directly in [RenderZRipple] and renders up to 16
/// simultaneous expanding/fading circles at 120fps without creating ink features,
/// animation controllers, or heap objects per tap.
class ZRipple extends ZLeafWidget<RenderZRipple> {
  /// Optional external [ZeroRippleController] to trigger ripples programmatically.
  final ZeroRippleController? controller;

  /// Target surface size.
  final Size size;

  /// Base surface fill color.
  final Color baseColor;

  /// Expanding ripple wave color.
  final Color rippleColor;

  /// Corner radius of the surface.
  final double borderRadius;

  /// Maximum radius of an expanded ripple.
  final double maxRadius;

  /// Creates a const [ZRipple] widget.
  const ZRipple({
    super.key,
    this.controller,
    this.size = const Size(240.0, 80.0),
    this.baseColor = const Color(0xFF1E293B),
    this.rippleColor = const Color(0xFF38BDF8),
    this.borderRadius = 12.0,
    this.maxRadius = 140.0,
  });

  @override
  RenderZRipple createRenderObject(BuildContext context) {
    return RenderZRipple(
      controller: controller,
      boxSize: size,
      baseColor: baseColor,
      rippleColor: rippleColor,
      borderRadius: borderRadius,
      maxRadius: maxRadius,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZRipple renderObject) {
    renderObject
      ..controller = controller
      ..boxSize = size
      ..baseColor = baseColor
      ..rippleColor = rippleColor
      ..borderRadius = borderRadius
      ..maxRadius = maxRadius;
  }
}

/// RenderBox for [ZRipple] that processes pointer events and renders SoA ripples
/// using a pre-allocated alpha palette of [Paint]s.
class RenderZRipple extends ZeroRenderBox {
  static const int _alphaSteps = 32;

  ZeroRippleController? _externalController;
  ZeroRippleController? _internalController;
  Size _boxSize;
  Color _baseColor;
  Color _rippleColor;
  double _borderRadius;
  double _maxRadius;
  Duration? _lastElapsed;

  final Paint _basePaint = Paint()..style = PaintingStyle.fill;
  final List<Paint> _alphaPaints = List<Paint>.generate(
    _alphaSteps,
    (_) => Paint()..style = PaintingStyle.fill,
    growable: false,
  );

  /// Creates a [RenderZRipple].
  RenderZRipple({
    required ZeroRippleController? controller,
    required Size boxSize,
    required Color baseColor,
    required Color rippleColor,
    required double borderRadius,
    required double maxRadius,
  })  : _externalController = controller,
        _boxSize = boxSize,
        _baseColor = baseColor,
        _rippleColor = rippleColor,
        _borderRadius = borderRadius,
        _maxRadius = maxRadius,
        super(animatePerFrame: true) {
    if (_externalController == null) {
      _internalController = ZeroRippleController();
    }
    _rebuildPaints();
  }

  ZeroRippleController get _activeController =>
      _externalController ?? (_internalController ??= ZeroRippleController());

  /// External ripple controller, if provided.
  ZeroRippleController? get controller => _externalController;
  set controller(ZeroRippleController? value) {
    if (identical(_externalController, value)) return;
    if (attached) {
      _externalController?.removeListener(_onControllerTriggered);
    }
    _externalController = value;
    if (value != null) {
      _internalController?.dispose();
      _internalController = null;
    } else {
      _internalController ??= ZeroRippleController();
    }
    if (attached) {
      _activeController.addListener(_onControllerTriggered);
    }
    markDirty();
  }

  /// Target surface size.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Surface background color.
  Color get baseColor => _baseColor;
  set baseColor(Color value) {
    if (_baseColor == value) return;
    _baseColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Ripple wave color.
  Color get rippleColor => _rippleColor;
  set rippleColor(Color value) {
    if (_rippleColor == value) return;
    _rippleColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Surface corner radius.
  double get borderRadius => _borderRadius;
  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markDirty();
  }

  /// Maximum radius of an expanded ripple.
  double get maxRadius => _maxRadius;
  set maxRadius(double value) {
    if (_maxRadius == value) return;
    _maxRadius = value;
    markDirty();
  }

  void _rebuildPaints() {
    _basePaint.color = _baseColor;
    final int baseAlpha = (_rippleColor.a * 255.0).round();
    final int r = (_rippleColor.r * 255.0).round();
    final int g = (_rippleColor.g * 255.0).round();
    final int b = (_rippleColor.b * 255.0).round();
    for (int i = 0; i < _alphaSteps; i++) {
      final double fade = 1.0 - (i / (_alphaSteps - 1));
      final int a = (baseAlpha * fade * 0.55).round().clamp(0, 255);
      _alphaPaints[i].color = Color.fromARGB(a, r, g, b);
    }
  }

  void _onControllerTriggered() {
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _activeController.addListener(_onControllerTriggered);
  }

  @override
  void detach() {
    _activeController.removeListener(_onControllerTriggered);
    super.detach();
  }

  @override
  void dispose() {
    _externalController?.removeListener(_onControllerTriggered);
    _internalController?.dispose();
    _internalController = null;
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _activeController.trigger(event.localPosition.dx, event.localPosition.dy);
    }
  }

  @override
  bool onFrameTick(Duration elapsed) {
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return _activeController.activeCount > 0;
    final int deltaUs = (elapsed - prev).inMicroseconds;
    if (deltaUs <= 0) return false;
    return _activeController.step(deltaUs / 1000000.0);
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(_borderRadius),
    );
    canvas.drawRRect(rrect, _basePaint);
    final ZeroRippleController ctrl = _activeController;
    if (ctrl.activeCount == 0) return;

    canvas.save();
    canvas.clipRRect(rrect);
    _paintActiveRipples(canvas, offset, ctrl);
    canvas.restore();
  }

  void _paintActiveRipples(
    Canvas canvas,
    Offset offset,
    ZeroRippleController ctrl,
  ) {
    final int cap = ctrl.capacity;
    for (int i = 0; i < cap; i++) {
      if (ctrl.isActiveAt(i)) {
        final double p = ctrl.progressAt(i);
        final int alphaIdx = (p * (_alphaSteps - 1)).floor().clamp(0, _alphaSteps - 1);
        final double radius = 8.0 + (_maxRadius - 8.0) * p;
        final double cx = offset.dx + ctrl.xAt(i);
        final double cy = offset.dy + ctrl.yAt(i);
        canvas.drawCircle(Offset(cx, cy), radius, _alphaPaints[alphaIdx]);
      }
    }
  }
}

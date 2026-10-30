import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Deprecated legacy alias for [ZFreehandCanvas].
@Deprecated('Use ZFreehandCanvas instead.')
typedef ZeroFreehandCanvas = ZFreehandCanvas;

/// Fixed-capacity Structure-of-Arrays (SoA) controller for 120Hz/240Hz freehand drawing.
///
/// Stores line segments `(x0, y0, x1, y1)` directly in a pre-allocated [Float32List]
/// so that [Canvas.drawRawPoints] can render thousands of stylus segments in a
/// single GPU call with 0 `Path` or `Offset` allocations during pointer movement.
class ZeroFreehandController {
  /// Maximum number of line segments stored in the flat float buffer.
  final int maxSegments;

  // Each line segment requires 4 floats: x0, y0, x1, y1.
  final Float32List _segmentFloats;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _segmentCount = 0;
  int _pointCount = 0;
  bool _hasActivePoint = false;
  double _lastX = 0.0;
  double _lastY = 0.0;
  bool _isDisposed = false;

  /// Creates a [ZeroFreehandController] with capacity for [maxSegments] line segments.
  ZeroFreehandController({this.maxSegments = 4096})
      : assert(maxSegments > 0),
        _segmentFloats = Float32List(maxSegments * 4);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Total number of recorded points across strokes.
  int get pointCount => _isDisposed ? 0 : _pointCount;

  /// Total number of line segments currently staged for [Canvas.drawRawPoints].
  int get segmentCount => _isDisposed ? 0 : _segmentCount;

  /// Registers a listener notified when points are added or cleared.
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Appends a point ([x], [y]) to the current stroke with 0 heap allocations.
  void addPoint(double x, double y) {
    if (_isDisposed) return;
    _pointCount++;
    if (!_hasActivePoint) {
      _hasActivePoint = true;
      _lastX = x;
      _lastY = y;
      _revision.add(1);
      return;
    }
    if (_segmentCount < maxSegments) {
      final int b = _segmentCount << 2;
      _segmentFloats[b] = _lastX;
      _segmentFloats[b + 1] = _lastY;
      _segmentFloats[b + 2] = x;
      _segmentFloats[b + 3] = y;
      _segmentCount++;
    }
    _lastX = x;
    _lastY = y;
    _revision.add(1);
  }

  /// Ends the current continuous stroke so the next [addPoint] starts a new stroke.
  void endStroke() {
    if (_isDisposed) return;
    _hasActivePoint = false;
  }

  /// Clears all recorded strokes and resets counters to zero.
  void clear() {
    if (_isDisposed) return;
    _segmentCount = 0;
    _pointCount = 0;
    _hasActivePoint = false;
    _revision.add(1);
  }

  /// Writes offset-adjusted segment coordinates into [target] and returns the float count.
  int copyTranslatedFloats(Float32List target, double dx, double dy) {
    if (_isDisposed || _segmentCount == 0) return 0;
    final int floatCount = _segmentCount << 2;
    final int limit = floatCount < target.length ? floatCount : target.length;
    for (int i = 0; i < limit; i += 2) {
      target[i] = _segmentFloats[i] + dx;
      target[i + 1] = _segmentFloats[i + 1] + dy;
    }
    return limit;
  }

  /// Disposes the controller and clears listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _segmentCount = 0;
    _pointCount = 0;
    _hasActivePoint = false;
    _revision.dispose();
  }
}

/// A zero-allocation 120Hz/240Hz freehand drawing canvas widget.
///
/// Captures pointer events directly inside [RenderZFreehandCanvas] and flushes
/// all stroke segments via [Canvas.drawRawPoints] without allocating `Path` or
/// `Offset` lists during pointer motion.
class ZFreehandCanvas extends ZLeafWidget<RenderZFreehandCanvas> {
  /// Optional external [ZeroFreehandController] for programmatic access.
  final ZeroFreehandController? controller;

  /// Target canvas size.
  final Size size;

  /// Stroke color.
  final Color strokeColor;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  /// Background fill color.
  final Color backgroundColor;

  /// Creates a const [ZFreehandCanvas] widget.
  const ZFreehandCanvas({
    super.key,
    this.controller,
    this.size = const Size(360.0, 220.0),
    this.strokeColor = const Color(0xFF38BDF8),
    this.strokeWidth = 3.0,
    this.backgroundColor = const Color(0xFF0F172A),
  });

  @override
  RenderZFreehandCanvas createRenderObject(BuildContext context) {
    return RenderZFreehandCanvas(
      controller: controller,
      boxSize: size,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      backgroundColor: backgroundColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZFreehandCanvas renderObject,
  ) {
    renderObject
      ..controller = controller
      ..boxSize = size
      ..strokeColor = strokeColor
      ..strokeWidth = strokeWidth
      ..backgroundColor = backgroundColor;
  }
}

/// RenderBox for [ZFreehandCanvas] that handles pointer down/move/up directly
/// and renders segments via [Canvas.drawRawPoints].
class RenderZFreehandCanvas extends ZeroRenderBox {
  ZeroFreehandController? _externalController;
  ZeroFreehandController? _internalController;
  Size _boxSize;
  Color _strokeColor;
  double _strokeWidth;
  Color _backgroundColor;

  late Float32List _scratchBuffer;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Creates a [RenderZFreehandCanvas].
  RenderZFreehandCanvas({
    required ZeroFreehandController? controller,
    required Size boxSize,
    required Color strokeColor,
    required double strokeWidth,
    required Color backgroundColor,
  })  : _externalController = controller,
        _boxSize = boxSize,
        _strokeColor = strokeColor,
        _strokeWidth = strokeWidth,
        _backgroundColor = backgroundColor,
        super(animatePerFrame: false) {
    if (_externalController == null) {
      _internalController = ZeroFreehandController();
    }
    _scratchBuffer = Float32List(_activeController.maxSegments * 4);
    _rebuildPaints();
  }

  ZeroFreehandController get _activeController =>
      _externalController ??
      (_internalController ??= ZeroFreehandController());

  /// External freehand controller, if supplied.
  ZeroFreehandController? get controller => _externalController;
  set controller(ZeroFreehandController? value) {
    if (identical(_externalController, value)) return;
    if (attached) {
      _externalController?.removeListener(_onStrokeUpdated);
    }
    _externalController = value;
    if (value != null) {
      _internalController?.dispose();
      _internalController = null;
    } else {
      _internalController ??= ZeroFreehandController();
    }
    final int needed = _activeController.maxSegments * 4;
    if (_scratchBuffer.length < needed) {
      _scratchBuffer = Float32List(needed);
    }
    if (attached) {
      _activeController.addListener(_onStrokeUpdated);
    }
    markDirty();
  }

  /// Target canvas size.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Ink stroke color.
  Color get strokeColor => _strokeColor;
  set strokeColor(Color value) {
    if (_strokeColor == value) return;
    _strokeColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Ink stroke width.
  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    _rebuildPaints();
    markDirty();
  }

  /// Canvas background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _rebuildPaints();
    markDirty();
  }

  void _rebuildPaints() {
    _bgPaint.color = _backgroundColor;
    _strokePaint
      ..color = _strokeColor
      ..strokeWidth = _strokeWidth;
  }

  void _onStrokeUpdated() {
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _activeController.addListener(_onStrokeUpdated);
  }

  @override
  void detach() {
    _activeController.removeListener(_onStrokeUpdated);
    super.detach();
  }

  @override
  void dispose() {
    _externalController?.removeListener(_onStrokeUpdated);
    _internalController?.dispose();
    _internalController = null;
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _activeController.addPoint(
        event.localPosition.dx,
        event.localPosition.dy,
      );
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _activeController.endStroke();
    }
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    canvas.drawRect(rect, _bgPaint);

    final ZeroFreehandController ctrl = _activeController;
    if (ctrl.segmentCount == 0) return;

    final int floatCount = ctrl.copyTranslatedFloats(
      _scratchBuffer,
      offset.dx,
      offset.dy,
    );
    if (floatCount <= 0) return;

    canvas.save();
    canvas.clipRect(rect);
    final Float32List view = Float32List.sublistView(_scratchBuffer, 0, floatCount);
    canvas.drawRawPoints(ui.PointMode.lines, view, _strokePaint);
    canvas.restore();
  }
}

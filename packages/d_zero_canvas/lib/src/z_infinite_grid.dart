import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZInfiniteGrid].
typedef ZCanvasGrid = ZInfiniteGrid;

/// Deprecated legacy alias for [ZInfiniteGrid].
@Deprecated('Use ZInfiniteGrid instead.')
typedef ZeroInfiniteGrid = ZInfiniteGrid;

/// Zero-allocation viewport state controller for 2D pan and zoom canvases.
class ZeroViewportController {
  final Float64List _state = Float64List(3);
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroViewportController] with initial [panX], [panY], and [zoom].
  ZeroViewportController({
    double panX = 0.0,
    double panY = 0.0,
    double zoom = 1.0,
  }) {
    _state[0] = panX;
    _state[1] = panY;
    _state[2] = zoom.clamp(0.25, 4.0);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Current horizontal pan offset in world units.
  double get panX => _isDisposed ? 0.0 : _state[0];

  /// Current vertical pan offset in world units.
  double get panY => _isDisposed ? 0.0 : _state[1];

  /// Current zoom factor (`0.25..4.0`).
  double get zoom => _isDisposed ? 1.0 : _state[2];

  /// Registers a listener notified when pan or zoom changes.
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Translates the viewport by ([dx], [dy]) pixels.
  void pan(double dx, double dy) {
    if (_isDisposed) return;
    if (dx == 0.0 && dy == 0.0) return;
    _state[0] += dx;
    _state[1] += dy;
    _revision.add(1);
  }

  /// Sets the zoom factor clamped to `0.25..4.0`.
  void setZoom(double z) {
    if (_isDisposed) return;
    final double clamped = z.clamp(0.25, 4.0);
    if (_state[2] == clamped) return;
    _state[2] = clamped;
    _revision.add(1);
  }

  /// Resets pan to `(0, 0)` and zoom to `1.0`.
  void reset() {
    if (_isDisposed) return;
    _state[0] = 0.0;
    _state[1] = 0.0;
    _state[2] = 1.0;
    _revision.add(1);
  }

  /// Disposes the viewport controller (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _revision.dispose();
  }
}

/// A zero-allocation infinite 2D pan/zoom grid canvas widget.
///
/// Renders visible minor and major grid lines in a single [Canvas.drawRawPoints]
/// batch using a pre-allocated [Float32List] buffer and paints live coordinates
/// via [ZeroNumberPainter].
class ZInfiniteGrid extends ZLeafWidget<RenderZInfiniteGrid> {
  /// Viewport controller holding pan and zoom state.
  final ZeroViewportController controller;

  /// Target size of the infinite grid viewport.
  final Size size;

  /// Base grid cell spacing at `1.0x` zoom.
  final double baseSpacing;

  /// Background color of the canvas.
  final Color backgroundColor;

  /// Minor grid line color.
  final Color minorGridColor;

  /// Major axis/grid line color.
  final Color majorGridColor;

  /// Creates a const [ZInfiniteGrid] widget.
  const ZInfiniteGrid({
    super.key,
    required this.controller,
    this.size = const Size(360.0, 220.0),
    this.baseSpacing = 24.0,
    this.backgroundColor = const Color(0xFF090D16),
    this.minorGridColor = const Color(0xFF1E293B),
    this.majorGridColor = const Color(0xFF38BDF8),
  });

  @override
  RenderZInfiniteGrid createRenderObject(BuildContext context) {
    return RenderZInfiniteGrid(
      controller: controller,
      boxSize: size,
      baseSpacing: baseSpacing,
      backgroundColor: backgroundColor,
      minorGridColor: minorGridColor,
      majorGridColor: majorGridColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZInfiniteGrid renderObject,
  ) {
    renderObject
      ..controller = controller
      ..boxSize = size
      ..baseSpacing = baseSpacing
      ..backgroundColor = backgroundColor
      ..minorGridColor = minorGridColor
      ..majorGridColor = majorGridColor;
  }
}

/// RenderBox for [ZInfiniteGrid] that batches grid lines into pre-allocated
/// [Float32List] buffers for single-call [Canvas.drawRawPoints] rendering.
class RenderZInfiniteGrid extends ZeroRenderBox {
  static const int _maxLines = 256;

  ZeroViewportController _controller;
  Size _boxSize;
  double _baseSpacing;
  Color _backgroundColor;
  Color _minorGridColor;
  Color _majorGridColor;

  final Float32List _lineBuffer = Float32List(_maxLines * 4);
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _minorPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _majorPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8;

  ZeroNumberPainter? _hudPainter;

  /// Creates a [RenderZInfiniteGrid].
  RenderZInfiniteGrid({
    required ZeroViewportController controller,
    required Size boxSize,
    required double baseSpacing,
    required Color backgroundColor,
    required Color minorGridColor,
    required Color majorGridColor,
  })  : _controller = controller,
        _boxSize = boxSize,
        _baseSpacing = baseSpacing,
        _backgroundColor = backgroundColor,
        _minorGridColor = minorGridColor,
        _majorGridColor = majorGridColor,
        super(animatePerFrame: false) {
    _rebuildPaints();
    _hudPainter = ZeroNumberPainter(
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 12.0,
        fontFamily: 'monospace',
      ),
    );
  }

  /// Viewport state controller.
  ZeroViewportController get controller => _controller;
  set controller(ZeroViewportController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(_onViewportChanged);
    }
    _controller = value;
    if (attached) {
      _controller.addListener(_onViewportChanged);
    }
    markDirty();
  }

  /// Viewport size.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Base spacing between grid lines at 1.0x zoom.
  double get baseSpacing => _baseSpacing;
  set baseSpacing(double value) {
    if (_baseSpacing == value) return;
    _baseSpacing = value;
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

  /// Minor grid line color.
  Color get minorGridColor => _minorGridColor;
  set minorGridColor(Color value) {
    if (_minorGridColor == value) return;
    _minorGridColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Major axis/grid line color.
  Color get majorGridColor => _majorGridColor;
  set majorGridColor(Color value) {
    if (_majorGridColor == value) return;
    _majorGridColor = value;
    _rebuildPaints();
    markDirty();
  }

  void _rebuildPaints() {
    _bgPaint.color = _backgroundColor;
    _minorPaint.color = _minorGridColor;
    _majorPaint.color = _majorGridColor;
  }

  void _onViewportChanged() {
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onViewportChanged);
  }

  @override
  void detach() {
    _controller.removeListener(_onViewportChanged);
    super.detach();
  }

  @override
  void dispose() {
    _controller.removeListener(_onViewportChanged);
    _hudPainter?.dispose();
    _hudPainter = null;
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerMoveEvent) {
      _controller.pan(event.delta.dx, event.delta.dy);
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

    canvas.save();
    canvas.clipRect(rect);
    _paintMinorGrid(canvas, rect);
    _paintOriginAxes(canvas, rect);
    _paintHudCoordinates(canvas, offset);
    canvas.restore();
  }

  void _paintMinorGrid(Canvas canvas, Rect rect) {
    final double step = (_baseSpacing * _controller.zoom).clamp(8.0, 200.0);
    int floatCount = _stageVerticalLines(rect, step, 0);
    floatCount = _stageHorizontalLines(rect, step, floatCount);
    if (floatCount > 0) {
      final Float32List view = Float32List.sublistView(_lineBuffer, 0, floatCount);
      canvas.drawRawPoints(ui.PointMode.lines, view, _minorPaint);
    }
  }

  int _stageVerticalLines(Rect rect, double step, int startFloatIdx) {
    int idx = startFloatIdx;
    final double modX = _controller.panX % step;
    double x = rect.left + (modX < 0.0 ? modX + step : modX);
    while (x <= rect.right && idx + 4 <= _lineBuffer.length) {
      _lineBuffer[idx] = x;
      _lineBuffer[idx + 1] = rect.top;
      _lineBuffer[idx + 2] = x;
      _lineBuffer[idx + 3] = rect.bottom;
      idx += 4;
      x += step;
    }
    return idx;
  }

  int _stageHorizontalLines(Rect rect, double step, int startFloatIdx) {
    int idx = startFloatIdx;
    final double modY = _controller.panY % step;
    double y = rect.top + (modY < 0.0 ? modY + step : modY);
    while (y <= rect.bottom && idx + 4 <= _lineBuffer.length) {
      _lineBuffer[idx] = rect.left;
      _lineBuffer[idx + 1] = y;
      _lineBuffer[idx + 2] = rect.right;
      _lineBuffer[idx + 3] = y;
      idx += 4;
      y += step;
    }
    return idx;
  }

  void _paintOriginAxes(Canvas canvas, Rect rect) {
    final double originX = rect.center.dx + _controller.panX;
    final double originY = rect.center.dy + _controller.panY;
    if (originX >= rect.left && originX <= rect.right) {
      canvas.drawLine(
        Offset(originX, rect.top),
        Offset(originX, rect.bottom),
        _majorPaint,
      );
    }
    if (originY >= rect.top && originY <= rect.bottom) {
      canvas.drawLine(
        Offset(rect.left, originY),
        Offset(rect.right, originY),
        _majorPaint,
      );
    }
  }

  void _paintHudCoordinates(Canvas canvas, Offset offset) {
    final ZeroNumberPainter? painter = _hudPainter;
    if (painter == null) return;
    final double baseX = offset.dx + 8.0;
    final double baseY = offset.dy + 8.0;
    final double w1 = painter.paintDouble(
      canvas,
      Offset(baseX, baseY),
      _controller.panX,
      fractionDigits: 0,
    );
    painter.paintDouble(
      canvas,
      Offset(baseX + w1 + 12.0, baseY),
      _controller.panY,
      fractionDigits: 0,
    );
  }
}

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Zero-allocation controller for high-frequency time-series ticks backed by [FloatRingBuffer].
class ZeroChartController implements Listenable {
  /// Maximum number of data points retained in the sliding window.
  final int capacity;
  final FloatRingBuffer _buffer;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroChartController] with the given fixed [capacity].
  ZeroChartController({this.capacity = 240})
      : _buffer = FloatRingBuffer(capacity > 1 ? capacity : 2);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Number of points currently stored, or `0` if disposed.
  int get length => _isDisposed ? 0 : _buffer.length;

  /// Most recently pushed value, or `0.0` if empty or disposed.
  double get latest => _isDisposed ? 0.0 : _buffer.latest;

  /// Minimum value in the current window, or `0.0` if empty or disposed.
  double get min => _isDisposed ? 0.0 : _buffer.min;

  /// Maximum value in the current window, or `0.0` if empty or disposed.
  double get max => _isDisposed ? 0.0 : _buffer.max;

  /// Arithmetic mean of the current window, or `0.0` if empty or disposed.
  double get average => _isDisposed ? 0.0 : _buffer.average;

  /// Returns the value at [index] (oldest = `0`), or `0.0` if disposed/out of range.
  double valueAt(int index) {
    if (_isDisposed) return 0.0;
    if (index < 0 || index >= _buffer.length) return 0.0;
    return _buffer[index];
  }

  /// Pushes a single tick value into the ring buffer and notifies listeners.
  void push(double value) {
    if (_isDisposed || value.isNaN || value.isInfinite) return;
    _buffer.push(value);
    _revision.add(1);
  }

  /// Pushes a batch of tick values and notifies listeners once.
  void pushBatch(List<double> values) {
    if (_isDisposed || values.isEmpty) return;
    _buffer.pushAll(values);
    _revision.add(1);
  }

  /// Clears all stored values and notifies listeners.
  void clear() {
    if (_isDisposed) return;
    _buffer.clear();
    _revision.add(1);
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Disposes this controller and releases all listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _buffer.clear();
    _revision.dispose();
  }
}

/// Active Z-prefixed alias for [ZSparkline].
typedef ZRealtimeChart = ZSparkline;

/// Legacy deprecated alias for [ZSparkline].
@Deprecated('Use ZSparkline instead.')
typedef ZeroSparkline = ZSparkline;

/// A zero-allocation real-time sparkline / telemetry line chart widget that
/// renders via `Canvas.drawRawPoints` and `ZeroNumberPainter` inside a [ZeroRenderBox].
class ZSparkline extends ZLeafWidget<RenderZSparkline> {
  /// Controller supplying real-time time-series values.
  final ZeroChartController controller;

  /// Stroke color of the sparkline polyline.
  final Color lineColor;

  /// Grid / baseline stroke color.
  final Color gridColor;

  /// Optional background color.
  final Color? backgroundColor;

  /// Stroke width of the polyline.
  final double strokeWidth;

  /// Whether to render horizontal grid lines.
  final bool showGrid;

  /// Whether to render min, max, and latest numeric labels via [ZeroNumberPainter].
  final bool showLabels;

  /// Number of decimal digits for numeric labels.
  final int fractionDigits;

  /// Text style for numeric labels.
  final TextStyle labelStyle;

  /// Fallback size when unconstrained.
  final Size preferredSize;

  /// Creates a const [ZSparkline].
  const ZSparkline({
    super.key,
    required this.controller,
    this.lineColor = const Color(0xFF00E5FF),
    this.gridColor = const Color(0x26FFFFFF),
    this.backgroundColor,
    this.strokeWidth = 2.0,
    this.showGrid = true,
    this.showLabels = true,
    this.fractionDigits = 2,
    this.labelStyle = const TextStyle(
      color: Color(0xFFB0BEC5),
      fontSize: 11.0,
      fontFamily: 'monospace',
    ),
    this.preferredSize = const Size(260.0, 96.0),
  });

  @override
  RenderZSparkline createRenderObject(BuildContext context) {
    return RenderZSparkline(
      controller: controller,
      lineColor: lineColor,
      gridColor: gridColor,
      backgroundColor: backgroundColor,
      strokeWidth: strokeWidth,
      showGrid: showGrid,
      showLabels: showLabels,
      fractionDigits: fractionDigits,
      labelStyle: labelStyle,
      preferredSize: preferredSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZSparkline renderObject) {
    renderObject
      ..controller = controller
      ..lineColor = lineColor
      ..gridColor = gridColor
      ..backgroundColor = backgroundColor
      ..strokeWidth = strokeWidth
      ..showGrid = showGrid
      ..showLabels = showLabels
      ..fractionDigits = fractionDigits
      ..labelStyle = labelStyle
      ..preferredSize = preferredSize;
  }
}

/// Direct-to-Canvas [ZeroRenderBox] for [ZSparkline].
class RenderZSparkline extends ZeroRenderBox {
  ZeroChartController _controller;
  Color _lineColor;
  Color _gridColor;
  Color? _backgroundColor;
  double _strokeWidth;
  bool _showGrid;
  bool _showLabels;
  int _fractionDigits;
  TextStyle _labelStyle;
  Size _preferredSize;

  final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  final Paint _gridPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;

  late Float32List _pointBuffer;
  ZeroNumberPainter? _numberPainter;

  /// Creates a [RenderZSparkline].
  RenderZSparkline({
    required ZeroChartController controller,
    required Color lineColor,
    required Color gridColor,
    required Color? backgroundColor,
    required double strokeWidth,
    required bool showGrid,
    required bool showLabels,
    required int fractionDigits,
    required TextStyle labelStyle,
    required Size preferredSize,
  })  : _controller = controller,
        _lineColor = lineColor,
        _gridColor = gridColor,
        _backgroundColor = backgroundColor,
        _strokeWidth = strokeWidth,
        _showGrid = showGrid,
        _showLabels = showLabels,
        _fractionDigits = fractionDigits,
        _labelStyle = labelStyle,
        _preferredSize = preferredSize {
    _linePaint
      ..color = lineColor
      ..strokeWidth = strokeWidth;
    _gridPaint.color = gridColor;
    if (backgroundColor != null) {
      _bgPaint.color = backgroundColor;
    }
    _pointBuffer = Float32List(controller.capacity * 2);
    _numberPainter = ZeroNumberPainter(style: labelStyle);
  }

  /// Active chart controller.
  ZeroChartController get controller => _controller;
  set controller(ZeroChartController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    if (_pointBuffer.length < value.capacity * 2) {
      _pointBuffer = Float32List(value.capacity * 2);
    }
    if (attached) {
      _controller.addListener(markDirty);
    }
    markDirty();
  }

  /// Line stroke color.
  Color get lineColor => _lineColor;
  set lineColor(Color value) {
    if (_lineColor == value) return;
    _lineColor = value;
    _linePaint.color = value;
    markDirty();
  }

  /// Grid line color.
  Color get gridColor => _gridColor;
  set gridColor(Color value) {
    if (_gridColor == value) return;
    _gridColor = value;
    _gridPaint.color = value;
    markDirty();
  }

  /// Optional background color.
  Color? get backgroundColor => _backgroundColor;
  set backgroundColor(Color? value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    if (value != null) {
      _bgPaint.color = value;
    }
    markDirty();
  }

  /// Polyline stroke width.
  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    _linePaint.strokeWidth = value;
    markDirty();
  }

  /// Whether to render grid lines.
  bool get showGrid => _showGrid;
  set showGrid(bool value) {
    if (_showGrid == value) return;
    _showGrid = value;
    markDirty();
  }

  /// Whether to render numeric labels.
  bool get showLabels => _showLabels;
  set showLabels(bool value) {
    if (_showLabels == value) return;
    _showLabels = value;
    markDirty();
  }

  /// Number of decimal places for labels.
  int get fractionDigits => _fractionDigits;
  set fractionDigits(int value) {
    if (_fractionDigits == value) return;
    _fractionDigits = value;
    markDirty();
  }

  /// Text style for numeric labels.
  TextStyle get labelStyle => _labelStyle;
  set labelStyle(TextStyle value) {
    if (_labelStyle == value) return;
    _labelStyle = value;
    _numberPainter?.dispose();
    _numberPainter = ZeroNumberPainter(style: value);
    markDirty();
  }

  /// Fallback size when unconstrained.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markDirty);
    _numberPainter ??= ZeroNumberPainter(style: _labelStyle);
  }

  @override
  void detach() {
    _controller.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _numberPainter?.dispose();
    _numberPainter = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.constrain(_preferredSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double w = size.width;
    final double h = size.height;
    if (w <= 0.0 || h <= 0.0) return;

    if (_backgroundColor != null) {
      canvas.drawRect(offset & size, _bgPaint);
    }
    if (_showGrid) {
      _paintGrid(canvas, offset.dx, offset.dy, w, h);
    }
    if (_controller.isDisposed || _controller.length == 0) return;

    final double minVal = _controller.min;
    final double maxVal = _controller.max;
    final double span = (maxVal - minVal) > 1e-6 ? (maxVal - minVal) : 1.0;

    _paintSparklinePoints(canvas, offset.dx, offset.dy + 4.0, w, h - 8.0, minVal, span);
    if (_showLabels) {
      _paintLabels(canvas, offset.dx + 4.0, offset.dy + 2.0, h, minVal, maxVal, _controller.latest);
    }
  }

  void _paintGrid(Canvas canvas, double left, double top, double w, double h) {
    final double right = left + w;
    canvas.drawLine(Offset(left, top + h * 0.25), Offset(right, top + h * 0.25), _gridPaint);
    canvas.drawLine(Offset(left, top + h * 0.50), Offset(right, top + h * 0.50), _gridPaint);
    canvas.drawLine(Offset(left, top + h * 0.75), Offset(right, top + h * 0.75), _gridPaint);
  }

  void _paintSparklinePoints(
    Canvas canvas,
    double left,
    double top,
    double width,
    double plotH,
    double minVal,
    double span,
  ) {
    final int cap = _controller.capacity;
    final int len = _controller.length;
    final double stepX = cap > 1 ? width / (cap - 1) : width;
    double lastX = left;
    double lastY = top + plotH * 0.5;

    for (int i = 0; i < cap; i++) {
      final int b = i << 1;
      if (i < len) {
        final double norm = (_controller.valueAt(i) - minVal) / span;
        lastX = left + i * stepX;
        lastY = top + (1.0 - norm) * plotH;
      }
      _pointBuffer[b] = lastX;
      _pointBuffer[b + 1] = lastY;
    }
    canvas.drawRawPoints(ui.PointMode.polygon, _pointBuffer, _linePaint);
  }

  void _paintLabels(
    Canvas canvas,
    double x,
    double top,
    double totalH,
    double minVal,
    double maxVal,
    double latestVal,
  ) {
    final ZeroNumberPainter? np = _numberPainter;
    if (np == null) return;
    np.paintDouble(canvas, Offset(x, top), maxVal, fractionDigits: _fractionDigits);
    np.paintDouble(
      canvas,
      Offset(x, top + totalH - np.height - 4.0),
      minVal,
      fractionDigits: _fractionDigits,
    );
    np.paintDouble(
      canvas,
      Offset(x, top + (totalH - np.height) * 0.5),
      latestVal,
      fractionDigits: _fractionDigits,
    );
  }
}

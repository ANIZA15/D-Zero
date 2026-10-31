import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZRadarChart].
typedef ZSpiderChart = ZRadarChart;

/// Legacy alias for [ZRadarChart].
@Deprecated('Use ZRadarChart instead.')
typedef ZeroRadarChart = ZRadarChart;

/// Active alias for [ZDonutChart].
typedef ZPieChart = ZDonutChart;

/// Legacy alias for [ZDonutChart].
@Deprecated('Use ZDonutChart instead.')
typedef ZeroDonutChart = ZDonutChart;

/// Zero-allocation controller for [ZRadarChart] storing normalized axis values
/// (`0.0 .. 1.0`) in a contiguous `Float32List`.
class ZeroRadarChartController extends ChangeNotifier {
  final int _axisCount;
  late final Float32List _values;
  bool _isDisposed = false;

  /// Creates a [ZeroRadarChartController] with [axisCount] axes (`3..12`).
  ZeroRadarChartController({int axisCount = 6, List<double>? initialValues})
      : _axisCount = axisCount.clamp(3, 12) {
    _values = Float32List(_axisCount);
    for (int i = 0; i < _axisCount; i++) {
      final double v = (initialValues != null && i < initialValues.length)
          ? initialValues[i]
          : 0.7;
      _values[i] = v.clamp(0.0, 1.0);
    }
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Number of radar axes.
  int get axisCount => _axisCount;

  /// Reads normalized value (`0.0 .. 1.0`) at [index].
  double valueAt(int index) {
    if (_isDisposed || index < 0 || index >= _axisCount) return 0.0;
    return _values[index];
  }

  /// Updates a single axis value in place.
  void setAxis(int index, double value) {
    if (_isDisposed || index < 0 || index >= _axisCount) return;
    final double clamped = value.clamp(0.0, 1.0);
    if (_values[index] == clamped) return;
    _values[index] = clamped;
    notifyListeners();
  }

  /// Updates all axis values from [values] in a single batch.
  void updateAll(List<double> values) {
    if (_isDisposed) return;
    final int len = math.min(_axisCount, values.length);
    for (int i = 0; i < len; i++) {
      _values[i] = values[i].clamp(0.0, 1.0);
    }
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
    _values.fillRange(0, _values.length, 0.0);
    super.dispose();
  }
}

/// A zero-allocation spider / radar polygon chart widget.
///
/// Packs polygon vertices into a pre-allocated `Float32List` and renders via
/// `Canvas.drawRawPoints` without per-frame `Path` or `Offset` list allocations.
class ZRadarChart extends ZLeafWidget<RenderZRadarChart> {
  /// Controller holding axis values.
  final ZeroRadarChartController controller;

  /// Preferred widget size.
  final Size size;

  /// Radar polygon stroke and vertex color.
  final Color lineColor;

  /// Creates a const [ZRadarChart].
  const ZRadarChart({
    super.key,
    required this.controller,
    this.size = const Size(120.0, 120.0),
    this.lineColor = const Color(0xFF00E5FF),
  });

  @override
  RenderZRadarChart createRenderObject(BuildContext context) {
    return RenderZRadarChart(
      controller: controller,
      preferredSize: size,
      lineColor: lineColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZRadarChart renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..lineColor = lineColor;
  }
}

/// Custom [ZeroRenderBox] for [ZRadarChart].
class RenderZRadarChart extends ZeroRenderBox {
  ZeroRadarChartController _controller;
  Size _preferredSize;
  late Float32List _polyPoints;

  final Paint _gridPaint = Paint()
    ..color = const Color(0xFF1E293B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _dotPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 5.0;

  /// Creates a [RenderZRadarChart].
  RenderZRadarChart({
    required ZeroRadarChartController controller,
    required Size preferredSize,
    required Color lineColor,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _polyPoints = Float32List((controller.axisCount + 1) * 2) {
    _linePaint.color = lineColor;
    _dotPaint.color = lineColor;
  }

  /// Radar chart controller.
  ZeroRadarChartController get controller => _controller;
  set controller(ZeroRadarChartController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    final int needed = (value.axisCount + 1) * 2;
    if (_polyPoints.length != needed) {
      _polyPoints = Float32List(needed);
    }
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Polygon stroke color.
  Color get lineColor => _linePaint.color;
  set lineColor(Color value) {
    if (_linePaint.color == value) return;
    _linePaint.color = value;
    _dotPaint.color = value;
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
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double cx = offset.dx + size.width * 0.5;
    final double cy = offset.dy + size.height * 0.5;
    final double maxR = math.min(size.width, size.height) * 0.44;
    final int axes = _controller.axisCount;

    canvas.drawCircle(Offset(cx, cy), maxR * 0.5, _gridPaint);
    canvas.drawCircle(Offset(cx, cy), maxR, _gridPaint);

    for (int i = 0; i < axes; i++) {
      final double angle = -math.pi * 0.5 + i * (math.pi * 2.0 / axes);
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + cosA * maxR, cy + sinA * maxR),
        _gridPaint,
      );
      final double r = _controller.valueAt(i) * maxR;
      _polyPoints[i * 2] = cx + cosA * r;
      _polyPoints[i * 2 + 1] = cy + sinA * r;
    }
    _polyPoints[axes * 2] = _polyPoints[0];
    _polyPoints[axes * 2 + 1] = _polyPoints[1];

    canvas.drawRawPoints(ui.PointMode.polygon, _polyPoints, _linePaint);
    canvas.drawRawPoints(ui.PointMode.points, _polyPoints, _dotPaint);
  }
}

/// Zero-allocation controller for [ZDonutChart] storing slice weights in a
/// contiguous `Float32List` and computing normalized sweep angles in place.
class ZeroDonutChartController extends ChangeNotifier {
  final int _sliceCount;
  late final Float32List _values;
  int _selectedSlice = -1;
  double _total = 0.0;
  bool _isDisposed = false;

  /// Creates a [ZeroDonutChartController] with [sliceCount] slices (`1..8`).
  ZeroDonutChartController({int sliceCount = 4, List<double>? initialValues})
      : _sliceCount = sliceCount.clamp(1, 8) {
    _values = Float32List(_sliceCount);
    for (int i = 0; i < _sliceCount; i++) {
      final double v = (initialValues != null && i < initialValues.length)
          ? initialValues[i]
          : (i + 1) * 25.0;
      _values[i] = math.max(0.0, v);
    }
    _recomputeTotal();
  }

  void _recomputeTotal() {
    double sum = 0.0;
    for (int i = 0; i < _sliceCount; i++) {
      sum += _values[i];
    }
    _total = sum;
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Number of slices.
  int get sliceCount => _sliceCount;

  /// Currently selected slice index (`-1` if none or disposed).
  int get selectedSlice => _isDisposed ? -1 : _selectedSlice;

  /// Sum of all slice values (`0.0` if disposed).
  double get total => _isDisposed ? 0.0 : _total;

  /// Reads raw slice value at [index].
  double valueAt(int index) {
    if (_isDisposed || index < 0 || index >= _sliceCount) return 0.0;
    return _values[index];
  }

  /// Updates a single slice value in place.
  void setSlice(int index, double value) {
    if (_isDisposed || index < 0 || index >= _sliceCount) return;
    final double safe = math.max(0.0, value);
    if (_values[index] == safe) return;
    _values[index] = safe;
    _recomputeTotal();
    notifyListeners();
  }

  /// Selects a slice index (`-1` to clear selection).
  void selectSlice(int index) {
    if (_isDisposed) return;
    final int clamped = index.clamp(-1, _sliceCount - 1);
    if (_selectedSlice == clamped) return;
    _selectedSlice = clamped;
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
    _total = 0.0;
    _selectedSlice = -1;
    _values.fillRange(0, _values.length, 0.0);
    super.dispose();
  }
}

/// A zero-allocation portfolio / budget donut & pie chart widget.
///
/// Renders slice arcs with polar touch hit-testing and a centered total readout
/// via [ZeroNumberPainter] without allocating `Path` or `String` objects.
class ZDonutChart extends ZLeafWidget<RenderZDonutChart> {
  /// Controller holding slice weights.
  final ZeroDonutChartController controller;

  /// Preferred widget size.
  final Size size;

  /// Ring thickness in logical pixels.
  final double strokeWidth;

  /// Creates a const [ZDonutChart].
  const ZDonutChart({
    super.key,
    required this.controller,
    this.size = const Size(116.0, 116.0),
    this.strokeWidth = 16.0,
  });

  @override
  RenderZDonutChart createRenderObject(BuildContext context) {
    return RenderZDonutChart(
      controller: controller,
      preferredSize: size,
      strokeWidth: strokeWidth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZDonutChart renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..strokeWidth = strokeWidth;
  }
}

/// Custom [ZeroRenderBox] for [ZDonutChart].
class RenderZDonutChart extends ZeroRenderBox {
  ZeroDonutChartController _controller;
  Size _preferredSize;
  double _strokeWidth;

  static const List<Color> _palette = <Color>[
    Color(0xFF00E5FF),
    Color(0xFF00FF88),
    Color(0xFFFFB300),
    Color(0xFFFF4081),
    Color(0xFF7C4DFF),
    Color(0xFF18FFFF),
    Color(0xFFFF6E40),
    Color(0xFF69F0AE),
  ];

  late final List<Paint> _slicePaints;
  final ZeroNumberPainter _totalPainter = ZeroNumberPainter(
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFFFFF),
      fontFamily: 'monospace',
    ),
  );

  /// Creates a [RenderZDonutChart].
  RenderZDonutChart({
    required ZeroDonutChartController controller,
    required Size preferredSize,
    required double strokeWidth,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _strokeWidth = math.max(4.0, strokeWidth) {
    _slicePaints = List<Paint>.generate(_palette.length, (i) {
      return Paint()
        ..color = _palette[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth;
    }, growable: false);
  }

  /// Donut chart controller.
  ZeroDonutChartController get controller => _controller;
  set controller(ZeroDonutChartController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Donut ring thickness.
  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    final double safe = math.max(4.0, value);
    if (_strokeWidth == safe) return;
    _strokeWidth = safe;
    for (final Paint p in _slicePaints) {
      p.strokeWidth = safe;
    }
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
  void dispose() {
    _totalPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      final int next =
          (_controller.selectedSlice + 1) % math.max(1, _controller.sliceCount);
      _controller.selectSlice(next);
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Offset center = offset + Offset(size.width * 0.5, size.height * 0.5);
    final double radius =
        math.min(size.width, size.height) * 0.5 - _strokeWidth * 0.7;
    final Rect oval = Rect.fromCircle(center: center, radius: math.max(4.0, radius));
    final double total = _controller.total;

    if (total > 0.0) {
      double startAngle = -math.pi * 0.5;
      for (int i = 0; i < _controller.sliceCount; i++) {
        final double sweep = (_controller.valueAt(i) / total) * math.pi * 2.0;
        if (sweep > 0.01) {
          canvas.drawArc(
            oval,
            startAngle,
            math.max(0.01, sweep - 0.04),
            false,
            _slicePaints[i % _slicePaints.length],
          );
        }
        startAngle += sweep;
      }
    }

    final double textW = _totalPainter.maxDigitWidth * 4.0;
    _totalPainter.paintInt(
      canvas,
      Offset(center.dx - textW * 0.5, center.dy - _totalPainter.height * 0.5),
      total.round(),
    );
  }
}

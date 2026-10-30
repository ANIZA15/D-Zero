import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZRibbon].
typedef ZLowLatencyInk = ZRibbon;

/// Deprecated legacy alias for [ZRibbon].
@Deprecated('Use ZRibbon instead.')
typedef ZeroRibbon = ZRibbon;

/// Fixed-capacity Structure-of-Arrays (SoA) triangle-strip controller for [ZRibbon].
///
/// Extrudes stylus/touch input samples `(x, y, pressure)` into left/right ribbon
/// edge vertices in a pre-allocated [Float32List] (`_stripFloats`). Separated strokes
/// are bridged via zero-area degenerate triangles so that all strokes across the
/// canvas render in **a single [ui.Vertices.raw] (`VertexMode.triangleStrip`) GPU call**
/// without `Path` allocation or CPU/GPU path tessellation.
class ZeroRibbonController implements Listenable {
  /// Maximum allowed spine sample capacity (`32,768`).
  static const int maxAllowedSamples = 32768;

  /// Maximum number of spine samples stored in the buffer.
  final int maxSamples;

  // Each sample can emit up to 2 strip vertices (+2 degenerate vertices on stroke start).
  // Allocate 4 vertices (8 floats) per sample slot for worst-case degenerate bridging.
  late final Float32List _stripFloats;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _vertexCount = 0;
  int _sampleCount = 0;
  bool _inStroke = false;
  double _lastX = 0.0;
  double _lastY = 0.0;
  bool _isDisposed = false;

  /// Creates a [ZeroRibbonController] with capacity for [maxSamples] spine points.
  ZeroRibbonController({int maxSamples = 2048})
      : maxSamples = _clampSamples(maxSamples) {
    _stripFloats = Float32List(this.maxSamples * 8);
  }

  static int _clampSamples(int v) {
    if (v < 2) return 2;
    if (v > maxAllowedSamples) return maxAllowedSamples;
    return v;
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Total number of spine samples added across strokes.
  int get sampleCount => _isDisposed ? 0 : _sampleCount;

  /// Total number of triangle-strip vertices currently staged for [ui.Vertices.raw].
  int get vertexCount => _isDisposed ? 0 : _vertexCount;

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

  /// Appends a stylus/touch sample at `([x], [y])` with normalized [pressure] (`0.0..1.0`)
  /// and extrudes ribbon strip vertices using [minWidth] and [maxWidth].
  void addSample(
    double x,
    double y, {
    double pressure = 0.5,
    double minWidth = 2.0,
    double maxWidth = 14.0,
  }) {
    if (_isDisposed || x.isNaN || y.isNaN) return;
    final int maxVerts = _stripFloats.length >> 1;
    if (_vertexCount + 4 > maxVerts) return;

    final double p = pressure.isNaN ? 0.5 : pressure.clamp(0.0, 1.0);
    final double halfW = (minWidth + (maxWidth - minWidth) * p) * 0.5;

    if (!_inStroke) {
      _startNewStroke(x, y, halfW);
      return;
    }

    final double dx = x - _lastX;
    final double dy = y - _lastY;
    final double distSq = dx * dx + dy * dy;
    if (distSq < 0.25) return; // Skip sub-0.5px jitter

    final double dist = math.sqrt(distSq);
    final double nx = -dy / dist;
    final double ny = dx / dist;

    _emitVertex(x + nx * halfW, y + ny * halfW);
    _emitVertex(x - nx * halfW, y - ny * halfW);
    _lastX = x;
    _lastY = y;
    _sampleCount++;
    _revision.add(1);
  }

  void _startNewStroke(double x, double y, double halfW) {
    _inStroke = true;
    _lastX = x;
    _lastY = y;

    final double lx = x;
    final double ly = y - halfW;
    final double rx = x;
    final double ry = y + halfW;

    if (_vertexCount > 0) {
      // Degenerate bridge: repeat last vertex of previous stroke and first vertex of new stroke.
      final int prevIdx = (_vertexCount - 1) << 1;
      _emitVertex(_stripFloats[prevIdx], _stripFloats[prevIdx + 1]);
      _emitVertex(lx, ly);
    }

    _emitVertex(lx, ly);
    _emitVertex(rx, ry);
    _sampleCount++;
    _revision.add(1);
  }

  void _emitVertex(double vx, double vy) {
    final int idx = _vertexCount << 1;
    _stripFloats[idx] = vx;
    _stripFloats[idx + 1] = vy;
    _vertexCount++;
  }

  /// Ends the active continuous stroke so the next [addSample] bridges via degenerate vertices.
  void endStroke() {
    if (_isDisposed) return;
    _inStroke = false;
  }

  /// Clears all recorded ribbon geometry.
  void clear() {
    if (_isDisposed) return;
    _vertexCount = 0;
    _sampleCount = 0;
    _inStroke = false;
    _revision.add(1);
  }

  /// Copies offset-translated vertex coordinates into [targetPositions] and fills [targetColors]
  /// with a gradient from [startColor] to [endColor]. Returns the number of vertices copied.
  int buildTranslatedStrip({
    required Float32List targetPositions,
    required Int32List targetColors,
    required double dx,
    required double dy,
    required Color startColor,
    required Color endColor,
  }) {
    if (_isDisposed || _vertexCount < 4) return 0;
    final int maxByPos = targetPositions.length >> 1;
    final int maxByCol = targetColors.length;
    final int maxCap = maxByPos < maxByCol ? maxByPos : maxByCol;
    final int count = _vertexCount < maxCap ? _vertexCount : maxCap;

    final int floatCount = count << 1;
    for (int i = 0; i < floatCount; i += 2) {
      targetPositions[i] = _stripFloats[i] + dx;
      targetPositions[i + 1] = _stripFloats[i + 1] + dy;
    }

    _fillColorGradient(targetColors, count, startColor, endColor);
    return count;
  }

  void _fillColorGradient(
    Int32List targetColors,
    int count,
    Color startColor,
    Color endColor,
  ) {
    final int sr = (startColor.r * 255.0).round() & 0xFF;
    final int sg = (startColor.g * 255.0).round() & 0xFF;
    final int sb = (startColor.b * 255.0).round() & 0xFF;
    final int sa = (startColor.a * 255.0).round() & 0xFF;

    final int dr = ((endColor.r * 255.0).round() & 0xFF) - sr;
    final int dg = ((endColor.g * 255.0).round() & 0xFF) - sg;
    final int db = ((endColor.b * 255.0).round() & 0xFF) - sb;
    final int da = ((endColor.a * 255.0).round() & 0xFF) - sa;

    final int denom = count > 1 ? count - 1 : 1;
    for (int i = 0; i < count; i++) {
      final int r = (sr + (dr * i) ~/ denom) & 0xFF;
      final int g = (sg + (dg * i) ~/ denom) & 0xFF;
      final int b = (sb + (db * i) ~/ denom) & 0xFF;
      final int a = (sa + (da * i) ~/ denom) & 0xFF;
      targetColors[i] = ((a << 24) | (r << 16) | (g << 8) | b).toSigned(32);
    }
  }

  /// Disposes the controller and zeroes internal buffers (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _vertexCount = 0;
    _sampleCount = 0;
    _inStroke = false;
    _stripFloats.fillRange(0, _stripFloats.length, 0.0);
    _revision.dispose();
  }
}

/// A zero-allocation, variable-width triangle-strip ribbon & low-latency ink widget.
///
/// Renders pressure- and velocity-responsive calligraphic strokes in a single
/// [ui.Vertices.raw] (`VertexMode.triangleStrip`) draw call without creating any
/// [Path] objects or running path tessellation on the CPU/GPU.
class ZRibbon extends ZLeafWidget<RenderZRibbon> {
  /// Backing triangle-strip controller.
  final ZeroRibbonController controller;

  /// Preferred canvas size when unconstrained.
  final Size size;

  /// Starting gradient color of the ribbon stroke.
  final Color startColor;

  /// Ending gradient color of the ribbon stroke.
  final Color endColor;

  /// Canvas background color.
  final Color backgroundColor;

  /// Minimum ribbon width in logical pixels (at pressure `0.0`).
  final double minWidth;

  /// Maximum ribbon width in logical pixels (at pressure `1.0`).
  final double maxWidth;

  /// Creates a const [ZRibbon] widget.
  const ZRibbon({
    super.key,
    required this.controller,
    this.size = const Size(320.0, 200.0),
    this.startColor = const Color(0xFF00F5D4),
    this.endColor = const Color(0xFF7B2CBF),
    this.backgroundColor = const Color(0xFF0F172A),
    this.minWidth = 2.0,
    this.maxWidth = 14.0,
  });

  @override
  RenderZRibbon createRenderObject(BuildContext context) {
    return RenderZRibbon(
      controller: controller,
      preferredSize: size,
      startColor: startColor,
      endColor: endColor,
      backgroundColor: backgroundColor,
      minWidth: minWidth,
      maxWidth: maxWidth,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZRibbon renderObject) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..startColor = startColor
      ..endColor = endColor
      ..backgroundColor = backgroundColor
      ..minWidth = minWidth
      ..maxWidth = maxWidth;
  }
}

/// Custom [ZeroRenderBox] for [ZRibbon] that renders variable-width ink via [ui.Vertices.raw].
class RenderZRibbon extends ZeroRenderBox {
  ZeroRibbonController _controller;
  Size _preferredSize;
  Color _startColor;
  Color _endColor;
  Color _backgroundColor;
  double _minWidth;
  double _maxWidth;

  late Float32List _translatedPositions;
  late Int32List _vertexColors;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _ribbonPaint = Paint()..style = PaintingStyle.fill;

  /// Creates a [RenderZRibbon].
  RenderZRibbon({
    required ZeroRibbonController controller,
    required Size preferredSize,
    required Color startColor,
    required Color endColor,
    required Color backgroundColor,
    required double minWidth,
    required double maxWidth,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _startColor = startColor,
        _endColor = endColor,
        _backgroundColor = backgroundColor,
        _minWidth = minWidth > 0.5 ? minWidth : 0.5,
        _maxWidth = maxWidth >= minWidth ? maxWidth : minWidth {
    _bgPaint.color = _backgroundColor;
    final int maxVerts = _controller.maxSamples * 4;
    _translatedPositions = Float32List(maxVerts * 2);
    _vertexColors = Int32List(maxVerts);
  }

  /// Backing ribbon controller.
  ZeroRibbonController get controller => _controller;
  set controller(ZeroRibbonController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    final int maxVerts = _controller.maxSamples * 4;
    if (_vertexColors.length < maxVerts) {
      _translatedPositions = Float32List(maxVerts * 2);
      _vertexColors = Int32List(maxVerts);
    }
    if (attached) {
      _controller.addListener(markDirty);
    }
    markDirty();
  }

  /// Preferred canvas size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Starting gradient color of the ribbon.
  Color get startColor => _startColor;
  set startColor(Color value) {
    if (_startColor == value) return;
    _startColor = value;
    markDirty();
  }

  /// Ending gradient color of the ribbon.
  Color get endColor => _endColor;
  set endColor(Color value) {
    if (_endColor == value) return;
    _endColor = value;
    markDirty();
  }

  /// Background fill color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Minimum ribbon stroke width.
  double get minWidth => _minWidth;
  set minWidth(double value) {
    final double clamped = value > 0.5 ? value : 0.5;
    if (_minWidth == clamped) return;
    _minWidth = clamped;
    markDirty();
  }

  /// Maximum ribbon stroke width.
  double get maxWidth => _maxWidth;
  set maxWidth(double value) {
    final double clamped = value >= _minWidth ? value : _minWidth;
    if (_maxWidth == clamped) return;
    _maxWidth = clamped;
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
    _controller.removeListener(markDirty);
    super.dispose();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.constrain(_preferredSize);
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (_controller.isDisposed) return;
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      final double pressure = _extractPressure(event);
      _controller.addSample(
        event.localPosition.dx,
        event.localPosition.dy,
        pressure: pressure,
        minWidth: _minWidth,
        maxWidth: _maxWidth,
      );
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _controller.endStroke();
    }
  }

  double _extractPressure(PointerEvent event) {
    final double minP = event.pressureMin;
    final double maxP = event.pressureMax;
    if (maxP > minP && event.pressure >= minP) {
      return ((event.pressure - minP) / (maxP - minP)).clamp(0.1, 1.0);
    }
    if (event is PointerMoveEvent) {
      final double speed = event.delta.distance;
      return (1.0 - (speed / 36.0)).clamp(0.2, 0.95);
    }
    return 0.5;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    canvas.drawRect(bounds, _bgPaint);
    if (_controller.isDisposed || _controller.vertexCount < 4) return;

    final int count = _controller.buildTranslatedStrip(
      targetPositions: _translatedPositions,
      targetColors: _vertexColors,
      dx: offset.dx,
      dy: offset.dy,
      startColor: _startColor,
      endColor: _endColor,
    );
    if (count < 4) return;

    canvas.save();
    canvas.clipRect(bounds);
    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangleStrip,
      Float32List.sublistView(_translatedPositions, 0, count << 1),
      colors: Int32List.sublistView(_vertexColors, 0, count),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _ribbonPaint);
    vertices.dispose();
    canvas.restore();
  }
}

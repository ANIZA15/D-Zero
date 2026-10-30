import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Active alias for [ZGauge].
typedef ZSpeedometer = ZGauge;

/// Legacy alias for [ZGauge].
@Deprecated('Use ZGauge instead.')
typedef ZeroGauge = ZGauge;

/// A zero-allocation, zero-rebuild radial gauge / speedometer widget.
///
/// Caches static background tick marks into a [ui.Picture] on layout/size changes
/// and in [RenderZGauge.paintZero] draws the cached picture, active arc, needle line,
/// and center value via [ZeroNumberPainter.paintDouble].
class ZGauge extends ZLeafWidget<RenderZGauge> {
  /// Reactive value source.
  final ValueListenable<double> valueListenable;

  /// Minimum gauge value.
  final double min;

  /// Maximum gauge value.
  final double max;

  /// Active arc color.
  final Color arcColor;

  /// Indicator needle color.
  final Color needleColor;

  /// Text style for the numeric readout.
  final TextStyle valueStyle;

  /// Creates a const [ZGauge].
  const ZGauge({
    super.key,
    required this.valueListenable,
    this.min = 0.0,
    this.max = 100.0,
    this.arcColor = const Color(0xFF00E5FF),
    this.needleColor = const Color(0xFFFF5252),
    this.valueStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 16.0,
      fontFamily: 'monospace',
    ),
  });

  @override
  RenderZGauge createRenderObject(BuildContext context) {
    return RenderZGauge(
      valueListenable: valueListenable,
      min: min,
      max: max,
      arcColor: arcColor,
      needleColor: needleColor,
      valueStyle: valueStyle,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZGauge renderObject) {
    renderObject
      ..valueListenable = valueListenable
      ..min = min
      ..max = max
      ..arcColor = arcColor
      ..needleColor = needleColor
      ..valueStyle = valueStyle;
  }
}

/// Custom [ZeroRenderBox] for [ZGauge].
class RenderZGauge extends ZeroRenderBox {
  static const double _startAngle = math.pi * 0.75;
  static const double _sweepSpan = math.pi * 1.5;

  ValueListenable<double> _valueListenable;
  double _min;
  double _max;
  TextStyle _valueStyle;

  final Paint _arcPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 8.0
    ..strokeCap = StrokeCap.round;
  final Paint _needlePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;
  final Paint _hubPaint = Paint()..style = PaintingStyle.fill;

  ZeroNumberPainter _numberPainter;
  ui.Picture? _dialPicture;
  Size _cachedDialSize = Size.zero;

  /// Creates a [RenderZGauge].
  RenderZGauge({
    required ValueListenable<double> valueListenable,
    required double min,
    required double max,
    required Color arcColor,
    required Color needleColor,
    required TextStyle valueStyle,
  })  : _valueListenable = valueListenable,
        _min = min,
        _max = max,
        _valueStyle = valueStyle,
        _numberPainter = ZeroNumberPainter(style: valueStyle) {
    _arcPaint.color = arcColor;
    _needlePaint.color = needleColor;
    _hubPaint.color = needleColor;
  }

  /// Reactive value listenable.
  ValueListenable<double> get valueListenable => _valueListenable;
  set valueListenable(ValueListenable<double> value) {
    if (identical(_valueListenable, value)) return;
    if (attached) {
      _valueListenable.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _valueListenable = value;
    markDirty();
  }

  /// Minimum gauge bound.
  double get min => _min;
  set min(double value) {
    if (_min == value) return;
    _min = value;
    markDirty();
  }

  /// Maximum gauge bound.
  double get max => _max;
  set max(double value) {
    if (_max == value) return;
    _max = value;
    markDirty();
  }

  /// Active arc color.
  Color get arcColor => _arcPaint.color;
  set arcColor(Color value) {
    if (_arcPaint.color == value) return;
    _arcPaint.color = value;
    markDirty();
  }

  /// Needle color.
  Color get needleColor => _needlePaint.color;
  set needleColor(Color value) {
    if (_needlePaint.color == value) return;
    _needlePaint.color = value;
    _hubPaint.color = value;
    markDirty();
  }

  /// Center readout text style.
  TextStyle get valueStyle => _valueStyle;
  set valueStyle(TextStyle value) {
    if (_valueStyle == value) return;
    _valueStyle = value;
    _numberPainter.dispose();
    _numberPainter = ZeroNumberPainter(style: value);
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _valueListenable.addListener(markDirty);
  }

  @override
  void detach() {
    _valueListenable.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _dialPicture?.dispose();
    _dialPicture = null;
    _numberPainter.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    final double w =
        constraints.hasBoundedWidth ? constraints.maxWidth : 140.0;
    final double h =
        constraints.hasBoundedHeight ? constraints.maxHeight : 140.0;
    final double side = math.min(w, h);
    size = constraints.constrain(Size(side, side));
    _ensureDialPicture();
  }

  void _ensureDialPicture() {
    if (_dialPicture != null && _cachedDialSize == size) return;
    _dialPicture?.dispose();
    _cachedDialSize = size;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas c = Canvas(recorder);
    final double radius = math.min(size.width, size.height) * 0.5 - 8.0;
    final Offset center = Offset(size.width * 0.5, size.height * 0.5);

    final Paint trackPaint = Paint()
      ..color = const Color(0xFF263238)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    if (radius > 0.0) {
      c.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        _sweepSpan,
        false,
        trackPaint,
      );
      _recordTicks(c, center, radius);
    }
    _dialPicture = recorder.endRecording();
  }

  void _recordTicks(Canvas c, Offset center, double radius) {
    final Paint tickPaint = Paint()
      ..color = const Color(0xFF78909C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const int tickCount = 20;
    for (int i = 0; i <= tickCount; i++) {
      final double angle = _startAngle + (_sweepSpan * i / tickCount);
      final double innerR = (i % 5 == 0) ? radius - 12.0 : radius - 7.0;
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);
      c.drawLine(
        Offset(center.dx + innerR * cosA, center.dy + innerR * sinA),
        Offset(center.dx + (radius - 2.0) * cosA, center.dy + (radius - 2.0) * sinA),
        tickPaint,
      );
    }
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    _ensureDialPicture();
    final Canvas canvas = context.canvas;
    final ui.Picture? pic = _dialPicture;
    if (pic != null) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawPicture(pic);
      canvas.restore();
    }

    final double radius = math.min(size.width, size.height) * 0.5 - 8.0;
    if (radius <= 0.0) return;

    final Offset center =
        Offset(offset.dx + size.width * 0.5, offset.dy + size.height * 0.5);
    final double span = _max - _min;
    final double val = _valueListenable.value.clamp(_min, _max);
    final double norm = span > 0.0 ? ((val - _min) / span).clamp(0.0, 1.0) : 0.0;

    if (norm > 0.0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        _sweepSpan * norm,
        false,
        _arcPaint,
      );
    }

    final double needleAngle = _startAngle + _sweepSpan * norm;
    final double needleLen = radius - 14.0;
    final Offset tip = Offset(
      center.dx + needleLen * math.cos(needleAngle),
      center.dy + needleLen * math.sin(needleAngle),
    );
    canvas.drawLine(center, tip, _needlePaint);
    canvas.drawCircle(center, 4.5, _hubPaint);

    final double labelW = _numberPainter.maxDigitWidth * 4.5;
    final Offset textPos = Offset(
      center.dx - labelW * 0.5,
      center.dy + radius * 0.45 - _numberPainter.height * 0.5,
    );
    _numberPainter.paintDouble(canvas, textPos, val, fractionDigits: 1);
  }
}

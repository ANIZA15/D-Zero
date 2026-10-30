import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Active alias for [ZKnob].
typedef ZRotaryDial = ZKnob;

/// Legacy alias for [ZKnob].
@Deprecated('Use ZKnob instead.')
typedef ZeroKnob = ZKnob;

/// A zero-allocation, zero-rebuild DAW-style rotary knob widget.
///
/// Handles vertical pointer drag directly in [RenderZKnob] and renders the rotary arc,
/// indicator tick, and centered numeric readout via [ZeroNumberPainter.paintDouble].
class ZKnob extends ZLeafWidget<RenderZKnob> {
  /// Reactive value controller updated on vertical drag.
  final ValueNotifier<double> controller;

  /// Minimum knob value.
  final double min;

  /// Maximum knob value.
  final double max;

  /// Diameter of the rotary knob in logical pixels.
  final double size;

  /// Active rotary arc and tick color.
  final Color arcColor;

  /// Text style for the centered value readout.
  final TextStyle labelStyle;

  /// Creates a const [ZKnob].
  const ZKnob({
    super.key,
    required this.controller,
    this.min = 0.0,
    this.max = 100.0,
    this.size = 72.0,
    this.arcColor = const Color(0xFF00E5FF),
    this.labelStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 12.0,
      fontFamily: 'monospace',
    ),
  });

  @override
  RenderZKnob createRenderObject(BuildContext context) {
    return RenderZKnob(
      controller: controller,
      min: min,
      max: max,
      knobSize: size,
      arcColor: arcColor,
      labelStyle: labelStyle,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZKnob renderObject) {
    renderObject
      ..controller = controller
      ..min = min
      ..max = max
      ..knobSize = size
      ..arcColor = arcColor
      ..labelStyle = labelStyle;
  }
}

/// Custom [ZeroRenderBox] for [ZKnob].
class RenderZKnob extends ZeroRenderBox {
  static const double _startAngle = math.pi * 0.75;
  static const double _sweepSpan = math.pi * 1.5;

  ValueNotifier<double> _controller;
  double _min;
  double _max;
  double _knobSize;
  TextStyle _labelStyle;

  double _lastDragY = 0.0;

  final Paint _bodyPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF263238);
  final Paint _trackPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xFF37474F);
  final Paint _arcPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0
    ..strokeCap = StrokeCap.round;
  final Paint _tickPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;

  ZeroNumberPainter _numberPainter;

  /// Creates a [RenderZKnob].
  RenderZKnob({
    required ValueNotifier<double> controller,
    required double min,
    required double max,
    required double knobSize,
    required Color arcColor,
    required TextStyle labelStyle,
  })  : _controller = controller,
        _min = min,
        _max = max,
        _knobSize = knobSize,
        _labelStyle = labelStyle,
        _numberPainter = ZeroNumberPainter(style: labelStyle) {
    _arcPaint.color = arcColor;
    _tickPaint.color = arcColor;
  }

  /// Value controller.
  ValueNotifier<double> get controller => _controller;
  set controller(ValueNotifier<double> value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    markDirty();
  }

  /// Minimum bound.
  double get min => _min;
  set min(double value) {
    if (_min == value) return;
    _min = value;
    markDirty();
  }

  /// Maximum bound.
  double get max => _max;
  set max(double value) {
    if (_max == value) return;
    _max = value;
    markDirty();
  }

  /// Knob diameter.
  double get knobSize => _knobSize;
  set knobSize(double value) {
    if (_knobSize == value) return;
    _knobSize = value;
    markNeedsLayout();
  }

  /// Active arc color.
  Color get arcColor => _arcPaint.color;
  set arcColor(Color value) {
    if (_arcPaint.color == value) return;
    _arcPaint.color = value;
    _tickPaint.color = value;
    markDirty();
  }

  /// Center readout text style.
  TextStyle get labelStyle => _labelStyle;
  set labelStyle(TextStyle value) {
    if (_labelStyle == value) return;
    _labelStyle = value;
    _numberPainter.dispose();
    _numberPainter = ZeroNumberPainter(style: value);
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
    _numberPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _lastDragY = event.localPosition.dy;
      return;
    }
    if (event is PointerMoveEvent) {
      final double dy = _lastDragY - event.localPosition.dy;
      _lastDragY = event.localPosition.dy;
      final double sensitivity = (_max - _min) / 120.0;
      final double next = (_controller.value + dy * sensitivity).clamp(_min, _max);
      _controller.value = next;
    }
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size(_knobSize, _knobSize));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double side = math.min(size.width, size.height);
    final double outerR = side * 0.5 - 4.0;
    if (outerR <= 0.0) return;

    final Offset center =
        Offset(offset.dx + size.width * 0.5, offset.dy + size.height * 0.5);
    final double span = _max - _min;
    final double val = _controller.value.clamp(_min, _max);
    final double norm = span > 0.0 ? ((val - _min) / span).clamp(0.0, 1.0) : 0.0;

    final Rect arcRect = Rect.fromCircle(center: center, radius: outerR);
    canvas.drawArc(arcRect, _startAngle, _sweepSpan, false, _trackPaint);
    if (norm > 0.0) {
      canvas.drawArc(arcRect, _startAngle, _sweepSpan * norm, false, _arcPaint);
    }

    final double bodyR = outerR - 6.0;
    if (bodyR > 0.0) {
      canvas.drawCircle(center, bodyR, _bodyPaint);
      final double angle = _startAngle + _sweepSpan * norm;
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);
      canvas.drawLine(
        Offset(center.dx + bodyR * 0.55 * cosA, center.dy + bodyR * 0.55 * sinA),
        Offset(center.dx + bodyR * 0.9 * cosA, center.dy + bodyR * 0.9 * sinA),
        _tickPaint,
      );
    }

    final double labelW = _numberPainter.maxDigitWidth * 3.5;
    final Offset textPos = Offset(
      center.dx - labelW * 0.5,
      center.dy - _numberPainter.height * 0.5,
    );
    _numberPainter.paintDouble(canvas, textPos, val, fractionDigits: 1);
  }
}

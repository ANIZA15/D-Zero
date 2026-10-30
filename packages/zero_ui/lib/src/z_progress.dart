import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Legacy alias for [ZLinearProgress].
@Deprecated('Use ZLinearProgress instead.')
typedef ZeroLinearProgress = ZLinearProgress;

/// Legacy alias for [ZCircularProgress].
@Deprecated('Use ZCircularProgress instead.')
typedef ZeroCircularProgress = ZCircularProgress;

/// A zero-allocation, zero-rebuild linear progress bar widget.
///
/// Listens directly to [valueListenable] (`0.0..1.0`) and renders the track,
/// active bar, and optional percentage readout via [ZeroNumberPainter.paintPercent]
/// with zero heap allocations.
class ZLinearProgress extends ZLeafWidget<RenderZLinearProgress> {
  /// Reactive progress source in the range `0.0..1.0`.
  final ValueListenable<double> valueListenable;

  /// Background track color.
  final Color trackColor;

  /// Foreground active bar color.
  final Color valueColor;

  /// Bar stroke thickness in logical pixels.
  final double strokeWidth;

  /// Whether to render a numeric percentage label (`value * 100.0`).
  final bool showPercentage;

  /// Text style for the percentage label when [showPercentage] is true.
  final TextStyle labelStyle;

  /// Creates a const [ZLinearProgress].
  const ZLinearProgress({
    super.key,
    required this.valueListenable,
    this.trackColor = const Color(0xFF263238),
    this.valueColor = const Color(0xFF00E5FF),
    this.strokeWidth = 8.0,
    this.showPercentage = false,
    this.labelStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 12.0,
      fontFamily: 'monospace',
    ),
  });

  @override
  RenderZLinearProgress createRenderObject(BuildContext context) {
    return RenderZLinearProgress(
      valueListenable: valueListenable,
      trackColor: trackColor,
      valueColor: valueColor,
      strokeWidth: strokeWidth,
      showPercentage: showPercentage,
      labelStyle: labelStyle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZLinearProgress renderObject,
  ) {
    renderObject
      ..valueListenable = valueListenable
      ..trackColor = trackColor
      ..valueColor = valueColor
      ..strokeWidth = strokeWidth
      ..showPercentage = showPercentage
      ..labelStyle = labelStyle;
  }
}

/// Custom [ZeroRenderBox] for [ZLinearProgress].
class RenderZLinearProgress extends ZeroRenderBox {
  ValueListenable<double> _valueListenable;
  double _strokeWidth;
  bool _showPercentage;
  TextStyle _labelStyle;

  final Paint _trackPaint = Paint()..style = PaintingStyle.fill;
  final Paint _valuePaint = Paint()..style = PaintingStyle.fill;
  ZeroNumberPainter _numberPainter;

  /// Creates a [RenderZLinearProgress].
  RenderZLinearProgress({
    required ValueListenable<double> valueListenable,
    required Color trackColor,
    required Color valueColor,
    required double strokeWidth,
    required bool showPercentage,
    required TextStyle labelStyle,
  })  : _valueListenable = valueListenable,
        _strokeWidth = strokeWidth,
        _showPercentage = showPercentage,
        _labelStyle = labelStyle,
        _numberPainter = ZeroNumberPainter(style: labelStyle) {
    _trackPaint.color = trackColor;
    _valuePaint.color = valueColor;
  }

  /// Reactive progress source.
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

  /// Track color.
  Color get trackColor => _trackPaint.color;
  set trackColor(Color value) {
    if (_trackPaint.color == value) return;
    _trackPaint.color = value;
    markDirty();
  }

  /// Active value color.
  Color get valueColor => _valuePaint.color;
  set valueColor(Color value) {
    if (_valuePaint.color == value) return;
    _valuePaint.color = value;
    markDirty();
  }

  /// Stroke height of the bar.
  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    markNeedsLayout();
  }

  /// Whether percentage text is shown.
  bool get showPercentage => _showPercentage;
  set showPercentage(bool value) {
    if (_showPercentage == value) return;
    _showPercentage = value;
    markNeedsLayout();
  }

  /// Percentage label style.
  TextStyle get labelStyle => _labelStyle;
  set labelStyle(TextStyle value) {
    if (_labelStyle == value) return;
    _labelStyle = value;
    _numberPainter.dispose();
    _numberPainter = ZeroNumberPainter(style: value);
    markNeedsLayout();
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
    _numberPainter.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    final double w =
        constraints.hasBoundedWidth ? constraints.maxWidth : 200.0;
    final double minH = _showPercentage
        ? math.max(_strokeWidth, _numberPainter.height)
        : _strokeWidth;
    final double h =
        constraints.hasBoundedHeight ? constraints.maxHeight : minH;
    size = constraints.constrain(Size(w, h));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double progress = _valueListenable.value.clamp(0.0, 1.0);
    final double labelReserve =
        _showPercentage ? (_numberPainter.maxDigitWidth * 5.5 + 8.0) : 0.0;
    final double barW = math.max(0.0, size.width - labelReserve);
    final double barY = offset.dy + (size.height - _strokeWidth) * 0.5;
    final Radius radius = Radius.circular(_strokeWidth * 0.5);

    final Rect trackRect =
        Rect.fromLTWH(offset.dx, barY, barW, _strokeWidth);
    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), _trackPaint);

    final double activeW = barW * progress;
    if (activeW > 0.0) {
      final Rect activeRect =
          Rect.fromLTWH(offset.dx, barY, activeW, _strokeWidth);
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        _valuePaint,
      );
    }

    if (_showPercentage) {
      final double textY =
          offset.dy + (size.height - _numberPainter.height) * 0.5;
      _numberPainter.paintPercent(
        canvas,
        Offset(offset.dx + barW + 8.0, textY),
        progress * 100.0,
        fractionDigits: 1,
      );
    }
  }
}

/// A zero-allocation, zero-rebuild circular progress indicator widget.
///
/// Listens directly to [valueListenable] (`0.0..1.0`) and renders the circular
/// track, active arc, and optional centered percentage via [ZeroNumberPainter.paintPercent].
class ZCircularProgress extends ZLeafWidget<RenderZCircularProgress> {
  /// Reactive progress source in the range `0.0..1.0`.
  final ValueListenable<double> valueListenable;

  /// Background ring color.
  final Color trackColor;

  /// Foreground active arc color.
  final Color valueColor;

  /// Ring stroke width in logical pixels.
  final double strokeWidth;

  /// Whether to render a centered percentage label (`value * 100.0`).
  final bool showPercentage;

  /// Text style for the centered percentage label.
  final TextStyle labelStyle;

  /// Creates a const [ZCircularProgress].
  const ZCircularProgress({
    super.key,
    required this.valueListenable,
    this.trackColor = const Color(0xFF263238),
    this.valueColor = const Color(0xFF00E5FF),
    this.strokeWidth = 6.0,
    this.showPercentage = false,
    this.labelStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 12.0,
      fontFamily: 'monospace',
    ),
  });

  @override
  RenderZCircularProgress createRenderObject(BuildContext context) {
    return RenderZCircularProgress(
      valueListenable: valueListenable,
      trackColor: trackColor,
      valueColor: valueColor,
      strokeWidth: strokeWidth,
      showPercentage: showPercentage,
      labelStyle: labelStyle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZCircularProgress renderObject,
  ) {
    renderObject
      ..valueListenable = valueListenable
      ..trackColor = trackColor
      ..valueColor = valueColor
      ..strokeWidth = strokeWidth
      ..showPercentage = showPercentage
      ..labelStyle = labelStyle;
  }
}

/// Custom [ZeroRenderBox] for [ZCircularProgress].
class RenderZCircularProgress extends ZeroRenderBox {
  ValueListenable<double> _valueListenable;
  double _strokeWidth;
  bool _showPercentage;
  TextStyle _labelStyle;

  final Paint _trackPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _valuePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  ZeroNumberPainter _numberPainter;

  /// Creates a [RenderZCircularProgress].
  RenderZCircularProgress({
    required ValueListenable<double> valueListenable,
    required Color trackColor,
    required Color valueColor,
    required double strokeWidth,
    required bool showPercentage,
    required TextStyle labelStyle,
  })  : _valueListenable = valueListenable,
        _strokeWidth = strokeWidth,
        _showPercentage = showPercentage,
        _labelStyle = labelStyle,
        _numberPainter = ZeroNumberPainter(style: labelStyle) {
    _trackPaint
      ..color = trackColor
      ..strokeWidth = strokeWidth;
    _valuePaint
      ..color = valueColor
      ..strokeWidth = strokeWidth;
  }

  /// Reactive progress source.
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

  /// Track color.
  Color get trackColor => _trackPaint.color;
  set trackColor(Color value) {
    if (_trackPaint.color == value) return;
    _trackPaint.color = value;
    markDirty();
  }

  /// Value arc color.
  Color get valueColor => _valuePaint.color;
  set valueColor(Color value) {
    if (_valuePaint.color == value) return;
    _valuePaint.color = value;
    markDirty();
  }

  /// Stroke width.
  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    _trackPaint.strokeWidth = value;
    _valuePaint.strokeWidth = value;
    markDirty();
  }

  /// Whether percentage is displayed.
  bool get showPercentage => _showPercentage;
  set showPercentage(bool value) {
    if (_showPercentage == value) return;
    _showPercentage = value;
    markDirty();
  }

  /// Label style.
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
    _valueListenable.addListener(markDirty);
  }

  @override
  void detach() {
    _valueListenable.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _numberPainter.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    final double w = constraints.hasBoundedWidth ? constraints.maxWidth : 64.0;
    final double h =
        constraints.hasBoundedHeight ? constraints.maxHeight : 64.0;
    final double side = math.min(w, h);
    size = constraints.constrain(Size(side, side));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double progress = _valueListenable.value.clamp(0.0, 1.0);
    final double side = math.min(size.width, size.height);
    final double radius = (side - _strokeWidth) * 0.5;
    if (radius <= 0.0) return;

    final Offset center =
        Offset(offset.dx + size.width * 0.5, offset.dy + size.height * 0.5);
    canvas.drawCircle(center, radius, _trackPaint);

    if (progress > 0.0) {
      final Rect arcRect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        arcRect,
        -math.pi * 0.5,
        math.pi * 2.0 * progress,
        false,
        _valuePaint,
      );
    }

    if (_showPercentage) {
      final double pct = progress * 100.0;
      final double estW = _numberPainter.maxDigitWidth * 4.5;
      final Offset textPos = Offset(
        center.dx - estW * 0.5,
        center.dy - _numberPainter.height * 0.5,
      );
      _numberPainter.paintPercent(canvas, textPos, pct, fractionDigits: 0);
    }
  }
}

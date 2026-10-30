import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Active Z-prefixed alias for [ZLiquidProgress].
typedef ZWaveFilter = ZLiquidProgress;

/// Deprecated legacy alias for [ZLiquidProgress].
@Deprecated('Use ZLiquidProgress instead.')
typedef ZeroLiquidProgress = ZLiquidProgress;

/// A zero-allocation liquid wave progress gauge widget.
///
/// Listens to [valueListenable] (`0.0..1.0`), computes sine-wave surface columns
/// into a pre-allocated [Float32List] line buffer rendered via [Canvas.drawRawPoints],
/// and draws the center percentage readout via [ZeroNumberPainter.paintPercent]
/// with zero heap allocations per frame.
class ZLiquidProgress extends ZLeafWidget<RenderZLiquidProgress> {
  /// Reactive progress source in `0.0..1.0`.
  final ValueListenable<double> valueListenable;

  /// Diameter / size of the circular liquid gauge.
  final Size size;

  /// Liquid wave fill color.
  final Color waveColor;

  /// Gauge background color.
  final Color backgroundColor;

  /// Outer ring border color.
  final Color borderColor;

  /// Peak-to-trough wave amplitude in logical pixels.
  final double waveAmplitude;

  /// Optional text style for the center percentage readout.
  final TextStyle? textStyle;

  /// Whether to render the numeric percentage in the center.
  final bool showPercentage;

  /// Whether the wave surface animation is active.
  final bool isAnimating;

  /// Creates a const [ZLiquidProgress] widget.
  const ZLiquidProgress({
    super.key,
    required this.valueListenable,
    this.size = const Size(140.0, 140.0),
    this.waveColor = const Color(0xFF0EA5E9),
    this.backgroundColor = const Color(0xFF0F172A),
    this.borderColor = const Color(0xFF38BDF8),
    this.waveAmplitude = 6.0,
    this.textStyle,
    this.showPercentage = true,
    this.isAnimating = true,
  });

  @override
  RenderZLiquidProgress createRenderObject(BuildContext context) {
    return RenderZLiquidProgress(
      valueListenable: valueListenable,
      boxSize: size,
      waveColor: waveColor,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      waveAmplitude: waveAmplitude,
      textStyle: textStyle,
      showPercentage: showPercentage,
      isAnimating: isAnimating,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZLiquidProgress renderObject,
  ) {
    renderObject
      ..valueListenable = valueListenable
      ..boxSize = size
      ..waveColor = waveColor
      ..backgroundColor = backgroundColor
      ..borderColor = borderColor
      ..waveAmplitude = waveAmplitude
      ..textStyle = textStyle
      ..showPercentage = showPercentage
      ..isAnimating = isAnimating;
  }
}

/// RenderBox for [ZLiquidProgress] that renders a sine-wave liquid column buffer
/// and center percentage glyph atlas without per-frame heap allocations.
class RenderZLiquidProgress extends ZeroRenderBox {
  static const int _columnCount = 64;

  ValueListenable<double> _valueListenable;
  Size _boxSize;
  Color _waveColor;
  Color _backgroundColor;
  Color _borderColor;
  double _waveAmplitude;
  TextStyle? _textStyle;
  bool _showPercentage;
  bool _isAnimating;

  double _phase = 0.0;
  Duration? _lastElapsed;
  ZeroNumberPainter? _numberPainter;

  // Each vertical column is a line segment (x0, y0, x1, y1) = 4 floats
  final Float32List _columnLines = Float32List(_columnCount * 4);
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _wavePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  /// Creates a [RenderZLiquidProgress].
  RenderZLiquidProgress({
    required ValueListenable<double> valueListenable,
    required Size boxSize,
    required Color waveColor,
    required Color backgroundColor,
    required Color borderColor,
    required double waveAmplitude,
    required TextStyle? textStyle,
    required bool showPercentage,
    required bool isAnimating,
  })  : _valueListenable = valueListenable,
        _boxSize = boxSize,
        _waveColor = waveColor,
        _backgroundColor = backgroundColor,
        _borderColor = borderColor,
        _waveAmplitude = waveAmplitude,
        _textStyle = textStyle,
        _showPercentage = showPercentage,
        _isAnimating = isAnimating,
        super(animatePerFrame: isAnimating) {
    _rebuildPaints();
    _rebuildNumberPainter();
  }

  /// Reactive progress listenable (`0.0..1.0`).
  ValueListenable<double> get valueListenable => _valueListenable;
  set valueListenable(ValueListenable<double> value) {
    if (identical(_valueListenable, value)) return;
    if (attached) {
      _valueListenable.removeListener(_onValueChanged);
    }
    _valueListenable = value;
    if (attached) {
      _valueListenable.addListener(_onValueChanged);
    }
    markDirty();
  }

  /// Target size of the gauge.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Liquid wave color.
  Color get waveColor => _waveColor;
  set waveColor(Color value) {
    if (_waveColor == value) return;
    _waveColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Background circle color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Outer ring border color.
  Color get borderColor => _borderColor;
  set borderColor(Color value) {
    if (_borderColor == value) return;
    _borderColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Sine-wave amplitude in pixels.
  double get waveAmplitude => _waveAmplitude;
  set waveAmplitude(double value) {
    if (_waveAmplitude == value) return;
    _waveAmplitude = value;
    markDirty();
  }

  /// Percentage readout text style.
  TextStyle? get textStyle => _textStyle;
  set textStyle(TextStyle? value) {
    if (_textStyle == value) return;
    _textStyle = value;
    _rebuildNumberPainter();
    markDirty();
  }

  /// Whether the center percentage readout is shown.
  bool get showPercentage => _showPercentage;
  set showPercentage(bool value) {
    if (_showPercentage == value) return;
    _showPercentage = value;
    markDirty();
  }

  /// Whether the wave animation is running.
  bool get isAnimating => _isAnimating;
  set isAnimating(bool value) {
    if (_isAnimating == value) return;
    _isAnimating = value;
    _lastElapsed = null;
    animatePerFrame = value;
    markDirty();
  }

  void _rebuildPaints() {
    _bgPaint.color = _backgroundColor;
    _wavePaint.color = _waveColor;
    _borderPaint.color = _borderColor;
  }

  void _rebuildNumberPainter() {
    _numberPainter?.dispose();
    _numberPainter = ZeroNumberPainter(
      style: _textStyle ??
          const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
    );
  }

  void _onValueChanged() {
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _valueListenable.addListener(_onValueChanged);
  }

  @override
  void detach() {
    _valueListenable.removeListener(_onValueChanged);
    super.detach();
  }

  @override
  void dispose() {
    _valueListenable.removeListener(_onValueChanged);
    _numberPainter?.dispose();
    _numberPainter = null;
    super.dispose();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isAnimating) return false;
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return true;
    final int deltaUs = (elapsed - prev).inMicroseconds;
    if (deltaUs <= 0) return false;
    _phase = (_phase + (deltaUs / 1000000.0) * 4.0) % (math.pi * 2.0);
    return true;
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    final double radius = math.min(rect.width, rect.height) * 0.5;
    final Offset center = rect.center;
    final Rect circleRect = Rect.fromCircle(center: center, radius: radius);
    final RRect clipRRect = RRect.fromRectAndRadius(
      circleRect,
      Radius.circular(radius),
    );

    canvas.drawRRect(clipRRect, _bgPaint);
    final double progress = _valueListenable.value.clamp(0.0, 1.0);
    _paintLiquidColumns(canvas, circleRect, clipRRect, progress);
    canvas.drawRRect(clipRRect, _borderPaint);
    if (_showPercentage) {
      _paintCenterPercentage(canvas, center, progress * 100.0);
    }
  }

  void _paintLiquidColumns(
    Canvas canvas,
    Rect circleRect,
    RRect clipRRect,
    double progress,
  ) {
    final double baseLevel =
        circleRect.bottom - (circleRect.height * progress);
    final double colStep = circleRect.width / _columnCount;
    _wavePaint.strokeWidth = colStep + 1.0;

    for (int i = 0; i < _columnCount; i++) {
      final double x = circleRect.left + (i + 0.5) * colStep;
      final double angle = (i / _columnCount) * math.pi * 2.0 + _phase;
      final double waveY = baseLevel + math.sin(angle) * _waveAmplitude;
      final int b = i << 2;
      _columnLines[b] = x;
      _columnLines[b + 1] = waveY.clamp(circleRect.top, circleRect.bottom);
      _columnLines[b + 2] = x;
      _columnLines[b + 3] = circleRect.bottom;
    }

    canvas.save();
    canvas.clipRRect(clipRRect);
    canvas.drawRawPoints(ui.PointMode.lines, _columnLines, _wavePaint);
    canvas.restore();
  }

  void _paintCenterPercentage(Canvas canvas, Offset center, double percent) {
    final ZeroNumberPainter? painter = _numberPainter;
    if (painter == null) return;
    final double approxW = painter.maxDigitWidth * 4.5;
    final double textX = center.dx - approxW * 0.5;
    final double textY = center.dy - painter.height * 0.5;
    painter.paintPercent(
      canvas,
      Offset(textX, textY),
      percent,
      fractionDigits: 1,
    );
  }
}

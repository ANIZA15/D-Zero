import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// A zero-allocation vertical rolling odometer widget.
///
/// Smoothly interpolates toward the latest [valueListenable] value on each VSync tick
/// and paints rolling digit columns in a single [Canvas.drawRawAtlas] call without
/// rebuilding the widget tree or allocating [String]s.
class ZOdometer extends ZLeafWidget<RenderZOdometer> {
  /// The numeric value source to display and animate toward.
  final ValueListenable<double> valueListenable;

  /// Text style applied to the odometer digits.
  final TextStyle style;

  /// Minimum number of integer digits to display (padded with leading zeros).
  final int minDigits;

  /// Exponential damping speed for smooth value transitions (higher = faster).
  final double dampingSpeed;

  const ZOdometer({
    super.key,
    required this.valueListenable,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 20.0,
      fontFamily: 'monospace',
    ),
    this.minDigits = 1,
    this.dampingSpeed = 12.0,
  });

  @override
  RenderZOdometer createRenderObject(BuildContext context) {
    return RenderZOdometer(
      valueListenable: valueListenable,
      style: style,
      minDigits: minDigits,
      dampingSpeed: dampingSpeed,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZOdometer renderObject) {
    renderObject
      ..valueListenable = valueListenable
      ..style = style
      ..minDigits = minDigits
      ..dampingSpeed = dampingSpeed;
  }
}

/// Alias for [ZOdometer] representing a general animated number display.
typedef ZAnimatedNumber = ZOdometer;

/// Backward compatibility alias for [ZOdometer].
@Deprecated('Use ZOdometer instead.')
typedef ZeroOdometer = ZOdometer;

/// Internal RenderBox for [ZOdometer] performing zero-allocation rolling digit animation.
class RenderZOdometer extends ZeroRenderBox {
  ValueListenable<double> _valueListenable;
  TextStyle _style;
  int _minDigits;
  double _dampingSpeed;
  late ZeroNumberPainter _painter;

  double _displayValue;
  Duration _lastElapsed = Duration.zero;

  RenderZOdometer({
    required ValueListenable<double> valueListenable,
    required TextStyle style,
    required int minDigits,
    required double dampingSpeed,
  })  : _valueListenable = valueListenable,
        _style = style,
        _minDigits = minDigits,
        _dampingSpeed = dampingSpeed,
        _displayValue = valueListenable.value,
        super(animatePerFrame: false) {
    _painter = ZeroNumberPainter(style: _style);
  }

  ValueListenable<double> get valueListenable => _valueListenable;
  set valueListenable(ValueListenable<double> value) {
    if (_valueListenable == value) return;
    if (attached) {
      _valueListenable.removeListener(_onTargetChanged);
      value.addListener(_onTargetChanged);
    }
    _valueListenable = value;
    _onTargetChanged();
  }

  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _painter.dispose();
    _painter = ZeroNumberPainter(style: _style);
    markNeedsLayout();
  }

  int get minDigits => _minDigits;
  set minDigits(int value) {
    if (_minDigits == value) return;
    _minDigits = value;
    markNeedsLayout();
  }

  double get dampingSpeed => _dampingSpeed;
  set dampingSpeed(double value) {
    if (_dampingSpeed == value) return;
    _dampingSpeed = value;
  }

  void _onTargetChanged() {
    final double target = _valueListenable.value;
    if ((target - _displayValue).abs() > 0.0005) {
      animatePerFrame = true;
    }
    markNeedsLayout();
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _valueListenable.addListener(_onTargetChanged);
  }

  @override
  void detach() {
    _valueListenable.removeListener(_onTargetChanged);
    _lastElapsed = Duration.zero;
    super.detach();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    final double target = _valueListenable.value;
    final double diff = target - _displayValue;
    if (diff.abs() <= 0.001) {
      _displayValue = target;
      _lastElapsed = Duration.zero;
      animatePerFrame = false;
      return true;
    }
    final double dt = _computeDeltaSeconds(elapsed);
    final double factor = (dt * _dampingSpeed).clamp(0.05, 1.0);
    _displayValue += diff * factor;
    return true;
  }

  double _computeDeltaSeconds(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return 1.0 / 60.0;
    }
    final int microDelta = (elapsed - _lastElapsed).inMicroseconds;
    _lastElapsed = elapsed;
    if (microDelta <= 0) return 1.0 / 60.0;
    final double dt = microDelta / 1000000.0;
    return dt > 0.1 ? 0.1 : dt;
  }

  int _computeDigitColumns() {
    final double absVal = _valueListenable.value.abs();
    int v = absVal.floor();
    int digits = 1;
    while (v >= 10) {
      v ~/= 10;
      digits++;
    }
    final int safeMin = _minDigits > 0 ? _minDigits : 1;
    return digits > safeMin ? digits : safeMin;
  }

  @override
  void performLayout() {
    final int cols = _computeDigitColumns();
    final double width = _painter.maxDigitWidth * cols;
    final double height = _painter.height;
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    _painter.paintOdometer(
      context.canvas,
      offset,
      _displayValue,
      minDigits: _minDigits,
    );
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}

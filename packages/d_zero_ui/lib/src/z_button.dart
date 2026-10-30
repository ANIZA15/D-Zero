import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZButton].
typedef ZActionButton = ZButton;

/// Deprecated legacy alias for [ZButton].
@Deprecated('Use ZButton instead.')
typedef ZeroButton = ZButton;

/// A zero-allocation, zero-rebuild interactive button widget.
///
/// Handles pointer events and press-ripple / highlight interpolation directly
/// inside [RenderZButton] via [ZeroFrameScheduler] without `setState`,
/// `AnimationController`, or `Material` ink layer overhead.
class ZButton extends ZSingleChildWidget<RenderZButton> {
  /// Optional text label baked into a cached [TextPainter] when [child] is null.
  final String? label;

  /// Callback invoked when the button is tapped while enabled.
  final VoidCallback? onPressed;

  /// Optional reactive enabled state observed directly without widget rebuilds.
  final ValueListenable<bool>? enabledListenable;

  /// Background color when enabled.
  final Color color;

  /// Background color when disabled.
  final Color disabledColor;

  /// Press highlight & ripple overlay color.
  final Color splashColor;

  /// Border stroke color.
  final Color borderColor;

  /// Corner radius in logical pixels.
  final double borderRadius;

  /// Border stroke width (`0.0` disables border).
  final double borderWidth;

  /// Inner padding around [child] or [label].
  final EdgeInsets padding;

  /// Text style for [label].
  final TextStyle textStyle;

  /// Creates a const [ZButton].
  const ZButton({
    super.key,
    super.child,
    this.label,
    this.onPressed,
    this.enabledListenable,
    this.color = const Color(0xFF0284C7),
    this.disabledColor = const Color(0xFF334155),
    this.splashColor = const Color(0x5538BDF8),
    this.borderColor = const Color(0xFF38BDF8),
    this.borderRadius = 10.0,
    this.borderWidth = 1.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
    this.textStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 14.0,
      fontWeight: FontWeight.w600,
    ),
  });

  @override
  RenderZButton createRenderObject(BuildContext context) {
    return RenderZButton(
      label: label,
      onPressed: onPressed,
      enabledListenable: enabledListenable,
      color: color,
      disabledColor: disabledColor,
      splashColor: splashColor,
      borderColor: borderColor,
      borderRadius: borderRadius,
      borderWidth: borderWidth,
      padding: padding,
      textStyle: textStyle,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZButton renderObject) {
    renderObject
      ..label = label
      ..onPressed = onPressed
      ..enabledListenable = enabledListenable
      ..color = color
      ..disabledColor = disabledColor
      ..splashColor = splashColor
      ..borderColor = borderColor
      ..borderRadius = borderRadius
      ..borderWidth = borderWidth
      ..padding = padding
      ..textStyle = textStyle
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

/// Custom [RenderShiftedBox] for [ZButton] that handles tap gestures and
/// animates press feedback via [ZeroFrameScheduler] with zero heap allocations.
class RenderZButton extends RenderShiftedBox implements ZeroSlottedFrameListener {
  static const int _splashSteps = 16;

  String? _label;

  /// Callback invoked on tap release inside bounds.
  VoidCallback? onPressed;

  ValueListenable<bool>? _enabledListenable;
  Color _color;
  Color _disabledColor;
  Color _splashColor;
  Color _borderColor;
  double _borderRadius;
  double _borderWidth;
  EdgeInsets _padding;
  TextStyle _textStyle;
  TextDirection _textDirection;

  int _schedulerSlot = -1;
  bool _isSubscribed = false;
  bool _isPressed = false;
  double _pressProgress = 0.0;
  double _tapX = 0.0;
  double _tapY = 0.0;
  Duration? _lastElapsed;

  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _disabledPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()..style = PaintingStyle.stroke;
  final List<Paint> _splashPaints = List<Paint>.generate(
    _splashSteps,
    (_) => Paint()..style = PaintingStyle.fill,
    growable: false,
  );
  final TextPainter _labelPainter = TextPainter();

  /// Creates a [RenderZButton].
  RenderZButton({
    RenderBox? child,
    required String? label,
    required this.onPressed,
    required ValueListenable<bool>? enabledListenable,
    required Color color,
    required Color disabledColor,
    required Color splashColor,
    required Color borderColor,
    required double borderRadius,
    required double borderWidth,
    required EdgeInsets padding,
    required TextStyle textStyle,
    required TextDirection textDirection,
  })  : _label = label,
        _enabledListenable = enabledListenable,
        _color = color,
        _disabledColor = disabledColor,
        _splashColor = splashColor,
        _borderColor = borderColor,
        _borderRadius = borderRadius,
        _borderWidth = borderWidth,
        _padding = padding,
        _textStyle = textStyle,
        _textDirection = textDirection,
        super(child) {
    _syncPaints();
    _layoutLabel();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) {
    _schedulerSlot = slot;
  }

  /// Whether this button is currently enabled.
  bool get isEnabled =>
      onPressed != null && (_enabledListenable?.value ?? true);

  /// Current press animation progress in `0.0..1.0`.
  double get pressProgress => _pressProgress;

  /// Button text label when [child] is null.
  String? get label => _label;
  set label(String? value) {
    if (_label == value) return;
    _label = value;
    _layoutLabel();
    markNeedsLayout();
  }

  /// Reactive enabled state source.
  ValueListenable<bool>? get enabledListenable => _enabledListenable;
  set enabledListenable(ValueListenable<bool>? value) {
    if (identical(_enabledListenable, value)) return;
    if (attached) {
      _enabledListenable?.removeListener(_onEnabledChanged);
      value?.addListener(_onEnabledChanged);
    }
    _enabledListenable = value;
    _onEnabledChanged();
  }

  /// Enabled background color.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    _fillPaint.color = value;
    markNeedsPaint();
  }

  /// Disabled background color.
  Color get disabledColor => _disabledColor;
  set disabledColor(Color value) {
    if (_disabledColor == value) return;
    _disabledColor = value;
    _disabledPaint.color = value;
    markNeedsPaint();
  }

  /// Press splash overlay color.
  Color get splashColor => _splashColor;
  set splashColor(Color value) {
    if (_splashColor == value) return;
    _splashColor = value;
    _syncSplashPaints();
    markNeedsPaint();
  }

  /// Border stroke color.
  Color get borderColor => _borderColor;
  set borderColor(Color value) {
    if (_borderColor == value) return;
    _borderColor = value;
    _borderPaint.color = value;
    markNeedsPaint();
  }

  /// Corner radius.
  double get borderRadius => _borderRadius;
  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  /// Border stroke width.
  double get borderWidth => _borderWidth;
  set borderWidth(double value) {
    if (_borderWidth == value) return;
    _borderWidth = value;
    _borderPaint.strokeWidth = math.max(0.0, value);
    markNeedsPaint();
  }

  /// Inner button padding.
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  /// Label text style.
  TextStyle get textStyle => _textStyle;
  set textStyle(TextStyle value) {
    if (_textStyle == value) return;
    _textStyle = value;
    _layoutLabel();
    markNeedsLayout();
  }

  /// Text direction for label layout.
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _layoutLabel();
    markNeedsLayout();
  }

  void _syncPaints() {
    _fillPaint.color = _color;
    _disabledPaint.color = _disabledColor;
    _borderPaint
      ..color = _borderColor
      ..strokeWidth = math.max(0.0, _borderWidth);
    _syncSplashPaints();
  }

  void _syncSplashPaints() {
    final int baseAlpha = (_splashColor.a * 255.0).round();
    final int r = (_splashColor.r * 255.0).round();
    final int g = (_splashColor.g * 255.0).round();
    final int b = (_splashColor.b * 255.0).round();
    for (int i = 0; i < _splashSteps; i++) {
      final double t = (i + 1) / _splashSteps;
      final int a = (baseAlpha * t).round().clamp(0, 255);
      _splashPaints[i].color = Color.fromARGB(a, r, g, b);
    }
  }

  void _layoutLabel() {
    final String? text = _label;
    if (text == null || text.isEmpty) return;
    _labelPainter
      ..textDirection = _textDirection
      ..text = TextSpan(text: text, style: _textStyle)
      ..layout();
  }

  void _onEnabledChanged() {
    if (!isEnabled) {
      _isPressed = false;
      _pressProgress = 0.0;
      _unsubscribeScheduler();
    }
    markNeedsPaint();
  }

  void _subscribeScheduler() {
    if (_isSubscribed || !attached) return;
    _isSubscribed = true;
    _lastElapsed = null;
    ZeroFrameScheduler.instance.subscribe(this);
  }

  void _unsubscribeScheduler() {
    if (!_isSubscribed) return;
    _isSubscribed = false;
    _lastElapsed = null;
    ZeroFrameScheduler.instance.unsubscribe(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _enabledListenable?.addListener(_onEnabledChanged);
  }

  @override
  void detach() {
    _enabledListenable?.removeListener(_onEnabledChanged);
    _unsubscribeScheduler();
    super.detach();
  }

  @override
  void dispose() {
    _unsubscribeScheduler();
    _labelPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (!isEnabled) return;
    if (event is PointerDownEvent) {
      _isPressed = true;
      _tapX = event.localPosition.dx;
      _tapY = event.localPosition.dy;
      _pressProgress = math.max(_pressProgress, 0.25);
      _subscribeScheduler();
      markNeedsPaint();
    } else if (event is PointerUpEvent) {
      final bool wasInside = size.contains(event.localPosition);
      _isPressed = false;
      _subscribeScheduler();
      markNeedsPaint();
      if (wasInside) onPressed?.call();
    } else if (event is PointerCancelEvent) {
      _isPressed = false;
      _subscribeScheduler();
    }
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!attached || !hasSize) return;
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    final double dt =
        prev == null ? 0.016 : (elapsed - prev).inMicroseconds / 1000000.0;
    final double step = (dt * 7.5).clamp(0.0, 1.0);
    if (_isPressed) {
      _pressProgress = (_pressProgress + step).clamp(0.0, 1.0);
    } else {
      _pressProgress = (_pressProgress - step).clamp(0.0, 1.0);
      if (_pressProgress <= 0.0) {
        _unsubscribeScheduler();
      }
    }
    markNeedsPaint();
  }

  @override
  void performLayout() {
    final RenderBox? childBox = child;
    if (childBox != null) {
      final BoxConstraints inner = constraints.deflate(_padding);
      childBox.layout(inner, parentUsesSize: true);
      final BoxParentData childParentData =
          childBox.parentData! as BoxParentData;
      childParentData.offset = Offset(_padding.left, _padding.top);
      size = constraints.constrain(
        Size(
          childBox.size.width + _padding.horizontal,
          childBox.size.height + _padding.vertical,
        ),
      );
      return;
    }
    final double contentW =
        (_label != null && _label!.isNotEmpty) ? _labelPainter.width : 64.0;
    final double contentH =
        (_label != null && _label!.isNotEmpty) ? _labelPainter.height : 20.0;
    size = constraints.constrain(
      Size(contentW + _padding.horizontal, contentH + _padding.vertical),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.max(0.0, _borderRadius)),
    );

    canvas.drawRRect(rrect, isEnabled ? _fillPaint : _disabledPaint);
    _paintSplash(canvas, offset, rrect);

    if (_borderWidth > 0.0 && isEnabled) {
      canvas.drawRRect(rrect, _borderPaint);
    }

    _paintContent(context, offset);
  }

  void _paintSplash(Canvas canvas, Offset offset, RRect rrect) {
    if (_pressProgress <= 0.0) return;
    final int idx =
        (_pressProgress * (_splashSteps - 1)).round().clamp(0, _splashSteps - 1);
    final Paint paint = _splashPaints[idx];
    canvas.save();
    canvas.clipRRect(rrect);
    final double maxR = math.max(size.width, size.height) * 1.1;
    final double radius = maxR * (0.3 + 0.7 * _pressProgress);
    canvas.drawCircle(
      Offset(offset.dx + _tapX, offset.dy + _tapY),
      radius,
      paint,
    );
    canvas.restore();
  }

  void _paintContent(PaintingContext context, Offset offset) {
    final RenderBox? childBox = child;
    if (childBox != null) {
      final BoxParentData childParentData =
          childBox.parentData! as BoxParentData;
      context.paintChild(childBox, childParentData.offset + offset);
      return;
    }
    if (_label != null && _label!.isNotEmpty) {
      final double dx = offset.dx + (size.width - _labelPainter.width) * 0.5;
      final double dy = offset.dy + (size.height - _labelPainter.height) * 0.5;
      _labelPainter.paint(context.canvas, Offset(dx, dy));
    }
  }
}

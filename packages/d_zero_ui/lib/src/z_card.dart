import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZCard].
typedef ZSurfaceCard = ZCard;

/// Deprecated legacy alias for [ZCard].
@Deprecated('Use ZCard instead.')
typedef ZeroCard = ZCard;

/// A zero-allocation, zero-`saveLayer` card container widget.
///
/// Unlike standard Flutter `Card` (which composes `Semantics`, `Container`,
/// `Material`, `PhysicalModel`, and `_MaterialInterior`), [ZCard] renders
/// multi-band ambient elevation shadows, rounded surface fill, crisp border,
/// and interactive press highlight in a single [RenderBox] ([RenderZCard])
/// without offscreen `saveLayer` buffers or widget tree rebuilds.
class ZCard extends ZSingleChildWidget<RenderZCard> {
  /// Background fill color of the card.
  final Color color;

  /// Border stroke color of the card.
  final Color borderColor;

  /// Shadow base color when [elevation] > 0.
  final Color shadowColor;

  /// Highlight overlay color when pressed (if [onTap] is provided).
  final Color highlightColor;

  /// Corner radius of the card.
  final double borderRadius;

  /// Border stroke width (`0.0` disables border stroke).
  final double borderWidth;

  /// Elevation depth in logical pixels (`0.0` disables shadow rendering).
  final double elevation;

  /// Inner padding around [child].
  final EdgeInsets padding;

  /// Fallback size when no [child] is provided and constraints are unbounded.
  final Size fallbackSize;

  /// Optional tap callback handled directly inside [RenderZCard].
  final VoidCallback? onTap;

  /// Creates a const [ZCard].
  const ZCard({
    super.key,
    super.child,
    this.color = const Color(0xFF1E293B),
    this.borderColor = const Color(0xFF334155),
    this.shadowColor = const Color(0x66000000),
    this.highlightColor = const Color(0x2238BDF8),
    this.borderRadius = 12.0,
    this.borderWidth = 1.0,
    this.elevation = 4.0,
    this.padding = const EdgeInsets.all(16.0),
    this.fallbackSize = const Size(240.0, 120.0),
    this.onTap,
  });

  @override
  RenderZCard createRenderObject(BuildContext context) {
    return RenderZCard(
      color: color,
      borderColor: borderColor,
      shadowColor: shadowColor,
      highlightColor: highlightColor,
      borderRadius: borderRadius,
      borderWidth: borderWidth,
      elevation: elevation,
      padding: padding,
      fallbackSize: fallbackSize,
      onTap: onTap,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZCard renderObject) {
    renderObject
      ..color = color
      ..borderColor = borderColor
      ..shadowColor = shadowColor
      ..highlightColor = highlightColor
      ..borderRadius = borderRadius
      ..borderWidth = borderWidth
      ..elevation = elevation
      ..padding = padding
      ..fallbackSize = fallbackSize
      ..onTap = onTap;
  }
}

/// Custom [RenderShiftedBox] for [ZCard] that paints elevation shadows,
/// surface fill, border, and press feedback with zero `saveLayer` overhead.
class RenderZCard extends RenderShiftedBox {
  static const int _shadowBands = 3;

  Color _color;
  Color _borderColor;
  Color _shadowColor;
  Color _highlightColor;
  double _borderRadius;
  double _borderWidth;
  double _elevation;
  EdgeInsets _padding;
  Size _fallbackSize;

  /// Optional callback invoked when a tap completes inside the card bounds.
  VoidCallback? onTap;

  bool _isPressed = false;

  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _highlightPaint = Paint()..style = PaintingStyle.fill;
  final List<Paint> _shadowPaints = List<Paint>.generate(
    _shadowBands,
    (_) => Paint()..style = PaintingStyle.fill,
    growable: false,
  );

  /// Creates a [RenderZCard].
  RenderZCard({
    RenderBox? child,
    required Color color,
    required Color borderColor,
    required Color shadowColor,
    required Color highlightColor,
    required double borderRadius,
    required double borderWidth,
    required double elevation,
    required EdgeInsets padding,
    required Size fallbackSize,
    required this.onTap,
  })  : _color = color,
        _borderColor = borderColor,
        _shadowColor = shadowColor,
        _highlightColor = highlightColor,
        _borderRadius = borderRadius,
        _borderWidth = borderWidth,
        _elevation = elevation,
        _padding = padding,
        _fallbackSize = fallbackSize,
        super(child) {
    _syncPaints();
  }

  @override
  bool get isRepaintBoundary => true;

  /// Whether the card is currently pressed down.
  bool get isPressed => _isPressed;

  /// Surface background color.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    _fillPaint.color = value;
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

  /// Shadow base color.
  Color get shadowColor => _shadowColor;
  set shadowColor(Color value) {
    if (_shadowColor == value) return;
    _shadowColor = value;
    _syncShadowPaints();
    markNeedsPaint();
  }

  /// Press highlight overlay color.
  Color get highlightColor => _highlightColor;
  set highlightColor(Color value) {
    if (_highlightColor == value) return;
    _highlightColor = value;
    _highlightPaint.color = value;
    markNeedsPaint();
  }

  /// Corner radius in logical pixels.
  double get borderRadius => _borderRadius;
  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  /// Border width in logical pixels.
  double get borderWidth => _borderWidth;
  set borderWidth(double value) {
    if (_borderWidth == value) return;
    _borderWidth = value;
    _borderPaint.strokeWidth = math.max(0.0, value);
    markNeedsPaint();
  }

  /// Elevation depth in logical pixels.
  double get elevation => _elevation;
  set elevation(double value) {
    if (_elevation == value) return;
    _elevation = value;
    markNeedsPaint();
  }

  /// Inner padding around [child].
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  /// Fallback size when [child] is null.
  Size get fallbackSize => _fallbackSize;
  set fallbackSize(Size value) {
    if (_fallbackSize == value) return;
    _fallbackSize = value;
    markNeedsLayout();
  }

  void _syncPaints() {
    _fillPaint.color = _color;
    _borderPaint
      ..color = _borderColor
      ..strokeWidth = math.max(0.0, _borderWidth);
    _highlightPaint.color = _highlightColor;
    _syncShadowPaints();
  }

  void _syncShadowPaints() {
    final int baseAlpha = (_shadowColor.a * 255.0).round();
    final int r = (_shadowColor.r * 255.0).round();
    final int g = (_shadowColor.g * 255.0).round();
    final int b = (_shadowColor.b * 255.0).round();
    for (int i = 0; i < _shadowBands; i++) {
      final double factor = (_shadowBands - i) / (_shadowBands * 2.2);
      final int a = (baseAlpha * factor).round().clamp(0, 255);
      _shadowPaints[i].color = Color.fromARGB(a, r, g, b);
    }
  }

  @override
  bool hitTestSelf(Offset position) => onTap != null;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (onTap == null) return;
    if (event is PointerDownEvent) {
      _setPressed(true);
    } else if (event is PointerUpEvent) {
      final bool wasInside = size.contains(event.localPosition);
      _setPressed(false);
      if (wasInside) onTap?.call();
    } else if (event is PointerCancelEvent) {
      _setPressed(false);
    }
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    _isPressed = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    final RenderBox? childBox = child;
    if (childBox == null) {
      size = constraints.constrain(_fallbackSize);
      return;
    }
    final BoxConstraints innerConstraints = constraints.deflate(_padding);
    childBox.layout(innerConstraints, parentUsesSize: true);
    final BoxParentData childParentData = childBox.parentData! as BoxParentData;
    childParentData.offset = Offset(_padding.left, _padding.top);
    size = constraints.constrain(
      Size(
        childBox.size.width + _padding.horizontal,
        childBox.size.height + _padding.vertical,
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    final Radius radius = Radius.circular(math.max(0.0, _borderRadius));
    final RRect rrect = RRect.fromRectAndRadius(rect, radius);

    if (_elevation > 0.0) {
      _paintElevationShadow(canvas, rect);
    }

    canvas.drawRRect(rrect, _fillPaint);

    if (_isPressed) {
      canvas.drawRRect(rrect, _highlightPaint);
    }

    if (_borderWidth > 0.0) {
      canvas.drawRRect(rrect, _borderPaint);
    }

    final RenderBox? childBox = child;
    if (childBox != null) {
      final BoxParentData childParentData = childBox.parentData! as BoxParentData;
      context.paintChild(childBox, childParentData.offset + offset);
    }
  }

  void _paintElevationShadow(Canvas canvas, Rect rect) {
    final double clampedElev = _elevation.clamp(0.0, 24.0);
    for (int i = _shadowBands - 1; i >= 0; i--) {
      final double spread = clampedElev * (i + 1) * 0.45;
      final double dy = clampedElev * (i + 1) * 0.35;
      final Rect shadowRect = rect.inflate(spread).translate(0.0, dy);
      final RRect shadowRRect = RRect.fromRectAndRadius(
        shadowRect,
        Radius.circular(math.max(0.0, _borderRadius + spread)),
      );
      canvas.drawRRect(shadowRRect, _shadowPaints[i]);
    }
  }
}

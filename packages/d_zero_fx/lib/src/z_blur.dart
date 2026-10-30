import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZBlur].
typedef ZGlassContainer = ZBlur;

/// Deprecated legacy alias for [ZBlur].
@Deprecated('Use ZBlur instead.')
typedef ZeroBlur = ZBlur;

/// A zero-allocation, zero-`saveLayer` frosted glass surface widget.
///
/// Renders a multi-band specular glass surface and crisp border directly onto
/// the [Canvas] using pre-allocated [Paint] instances without allocating
/// offscreen buffers or triggering `BackdropFilter` save layers.
class ZBlur extends ZLeafWidget<RenderZBlur> {
  /// Target size of the frosted glass surface.
  final Size size;

  /// Base translucent tint color of the glass panel.
  final Color tintColor;

  /// Rim highlight border color of the glass panel.
  final Color borderColor;

  /// Corner radius of the glass panel.
  final double borderRadius;

  /// Specular sheen intensity in `0.0..1.0`.
  final double highlightIntensity;

  /// Creates a const [ZBlur] frosted glass surface.
  const ZBlur({
    super.key,
    this.size = const Size(240.0, 120.0),
    this.tintColor = const Color(0x441E293B),
    this.borderColor = const Color(0x66FFFFFF),
    this.borderRadius = 12.0,
    this.highlightIntensity = 0.18,
  });

  @override
  RenderZBlur createRenderObject(BuildContext context) {
    return RenderZBlur(
      boxSize: size,
      tintColor: tintColor,
      borderColor: borderColor,
      borderRadius: borderRadius,
      highlightIntensity: highlightIntensity,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZBlur renderObject) {
    renderObject
      ..boxSize = size
      ..tintColor = tintColor
      ..borderColor = borderColor
      ..borderRadius = borderRadius
      ..highlightIntensity = highlightIntensity;
  }
}

/// RenderBox for [ZBlur] that paints a multi-band specular glass surface with
/// zero `saveLayer` overhead and zero per-frame allocations.
class RenderZBlur extends ZeroRenderBox {
  static const int _sheenBands = 8;

  Size _boxSize;
  Color _tintColor;
  Color _borderColor;
  double _borderRadius;
  double _highlightIntensity;

  final Paint _tintPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final List<Paint> _sheenPaints = List<Paint>.generate(
    _sheenBands,
    (_) => Paint()..style = PaintingStyle.fill,
    growable: false,
  );

  /// Creates a [RenderZBlur].
  RenderZBlur({
    required Size boxSize,
    required Color tintColor,
    required Color borderColor,
    required double borderRadius,
    required double highlightIntensity,
  })  : _boxSize = boxSize,
        _tintColor = tintColor,
        _borderColor = borderColor,
        _borderRadius = borderRadius,
        _highlightIntensity = highlightIntensity,
        super(animatePerFrame: false) {
    _rebuildPaints();
  }

  /// Target size of the glass panel.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Base translucent tint color.
  Color get tintColor => _tintColor;
  set tintColor(Color value) {
    if (_tintColor == value) return;
    _tintColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Border stroke color.
  Color get borderColor => _borderColor;
  set borderColor(Color value) {
    if (_borderColor == value) return;
    _borderColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Corner radius of the glass panel.
  double get borderRadius => _borderRadius;
  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markDirty();
  }

  /// Specular highlight intensity (`0.0..1.0`).
  double get highlightIntensity => _highlightIntensity;
  set highlightIntensity(double value) {
    if (_highlightIntensity == value) return;
    _highlightIntensity = value;
    _rebuildPaints();
    markDirty();
  }

  void _rebuildPaints() {
    _tintPaint.color = _tintColor;
    _borderPaint.color = _borderColor;
    final double clamped = _highlightIntensity.clamp(0.0, 1.0);
    for (int i = 0; i < _sheenBands; i++) {
      final double t = 1.0 - (i / _sheenBands);
      final int alpha = (clamped * t * t * 255.0).round().clamp(0, 255);
      _sheenPaints[i].color = Color.fromARGB(alpha, 255, 255, 255);
    }
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect rect = offset & size;
    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(_borderRadius),
    );
    canvas.drawRRect(rrect, _tintPaint);
    _paintSheenBands(canvas, rect, rrect);
    canvas.drawRRect(rrect, _borderPaint);
  }

  void _paintSheenBands(Canvas canvas, Rect rect, RRect rrect) {
    final double sheenHeight = rect.height * 0.55;
    final double bandH = sheenHeight / _sheenBands;
    canvas.save();
    canvas.clipRRect(rrect);
    for (int i = 0; i < _sheenBands; i++) {
      final double top = rect.top + i * bandH;
      canvas.drawRect(
        Rect.fromLTWH(rect.left, top, rect.width, bandH + 0.5),
        _sheenPaints[i],
      );
    }
    canvas.restore();
  }
}

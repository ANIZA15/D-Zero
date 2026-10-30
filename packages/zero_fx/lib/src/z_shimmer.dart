import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Active Z-prefixed alias for [ZShimmer].
typedef ZSkeleton = ZShimmer;

/// Deprecated legacy alias for [ZShimmer].
@Deprecated('Use ZShimmer instead.')
typedef ZeroShimmer = ZShimmer;

/// A zero-allocation, zero-`saveLayer` shimmer placeholder box.
///
/// Renders a smooth 120fps swept highlight bar across a rounded box using a
/// pre-allocated table of band [Paint]s inside [Canvas.clipRRect] without
/// creating any `ShaderMask` or offscreen buffer.
class ZShimmer extends ZLeafWidget<RenderZShimmer> {
  /// Target size of the shimmer box.
  final Size size;

  /// Corner radius of the rounded shimmer box.
  final double borderRadius;

  /// Base background color of the skeleton placeholder.
  final Color baseColor;

  /// Highlight sweep color of the shimmer band.
  final Color highlightColor;

  /// Whether the shimmer sweep animation is active.
  final bool isAnimating;

  /// Creates a const [ZShimmer] placeholder widget.
  const ZShimmer({
    super.key,
    this.size = const Size(240.0, 24.0),
    this.borderRadius = 8.0,
    this.baseColor = const Color(0xFF1E293B),
    this.highlightColor = const Color(0xFF475569),
    this.isAnimating = true,
  });

  @override
  RenderZShimmer createRenderObject(BuildContext context) {
    return RenderZShimmer(
      boxSize: size,
      borderRadius: borderRadius,
      baseColor: baseColor,
      highlightColor: highlightColor,
      isAnimating: isAnimating,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZShimmer renderObject) {
    renderObject
      ..boxSize = size
      ..borderRadius = borderRadius
      ..baseColor = baseColor
      ..highlightColor = highlightColor
      ..isAnimating = isAnimating;
  }
}

/// RenderBox for [ZShimmer] that draws a multi-band swept shimmer highlight
/// with zero `saveLayer` overhead and zero per-frame heap allocations.
class RenderZShimmer extends ZeroRenderBox {
  static const int _bandCount = 12;

  Size _boxSize;
  double _borderRadius;
  Color _baseColor;
  Color _highlightColor;
  bool _isAnimating;

  double _phase = 0.0;
  Duration? _lastElapsed;

  final Paint _basePaint = Paint()..style = PaintingStyle.fill;
  final List<Paint> _bandPaints = List<Paint>.generate(
    _bandCount,
    (_) => Paint()..style = PaintingStyle.fill,
    growable: false,
  );

  /// Creates a [RenderZShimmer].
  RenderZShimmer({
    required Size boxSize,
    required double borderRadius,
    required Color baseColor,
    required Color highlightColor,
    required bool isAnimating,
  })  : _boxSize = boxSize,
        _borderRadius = borderRadius,
        _baseColor = baseColor,
        _highlightColor = highlightColor,
        _isAnimating = isAnimating,
        super(animatePerFrame: isAnimating) {
    _rebuildPaints();
  }

  /// Target size of the shimmer box.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Corner radius of the rounded rectangle.
  double get borderRadius => _borderRadius;
  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markDirty();
  }

  /// Base color of the placeholder box.
  Color get baseColor => _baseColor;
  set baseColor(Color value) {
    if (_baseColor == value) return;
    _baseColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Highlight color of the moving sweep band.
  Color get highlightColor => _highlightColor;
  set highlightColor(Color value) {
    if (_highlightColor == value) return;
    _highlightColor = value;
    _rebuildPaints();
    markDirty();
  }

  /// Whether the shimmer sweep animation is running.
  bool get isAnimating => _isAnimating;
  set isAnimating(bool value) {
    if (_isAnimating == value) return;
    _isAnimating = value;
    _lastElapsed = null;
    animatePerFrame = value;
    markDirty();
  }

  /// Current normalized sweep phase in `0.0..1.0`.
  double get phase => _phase;

  void _rebuildPaints() {
    _basePaint.color = _baseColor;
    const double center = (_bandCount - 1) * 0.5;
    for (int i = 0; i < _bandCount; i++) {
      final double dist = ((i - center).abs()) / center;
      final double falloff = 1.0 - (dist * dist);
      _bandPaints[i].color = Color.lerp(_baseColor, _highlightColor, falloff)!;
    }
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isAnimating) return false;
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return true;
    final int deltaUs = (elapsed - prev).inMicroseconds;
    if (deltaUs <= 0) return false;
    final double dt = deltaUs / 1000000.0;
    _phase = (_phase + dt * 0.85) % 1.0;
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
    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(_borderRadius),
    );
    canvas.drawRRect(rrect, _basePaint);
    if (!_isAnimating) return;
    _paintSweepBands(canvas, rect, rrect);
  }

  void _paintSweepBands(Canvas canvas, Rect rect, RRect rrect) {
    final double totalWidth = rect.width;
    final double sweepWidth = totalWidth * 0.55;
    final double startX =
        rect.left - sweepWidth + (_phase * (totalWidth + sweepWidth * 2.0));
    final double sliceW = sweepWidth / _bandCount;

    canvas.save();
    canvas.clipRRect(rrect);
    for (int i = 0; i < _bandCount; i++) {
      final double bandLeft = startX + i * sliceW;
      canvas.drawRect(
        Rect.fromLTWH(bandLeft, rect.top, sliceW + 1.0, rect.height),
        _bandPaints[i],
      );
    }
    canvas.restore();
  }
}

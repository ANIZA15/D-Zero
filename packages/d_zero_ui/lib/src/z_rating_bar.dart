import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZRatingBar].
typedef ZStarRating = ZRatingBar;

/// Legacy alias for [ZRatingBar].
@Deprecated('Use ZRatingBar instead.')
typedef ZeroRatingBar = ZRatingBar;

/// Active alias for [ZPullToRefresh].
typedef ZRefreshHeader = ZPullToRefresh;

/// Legacy alias for [ZPullToRefresh].
@Deprecated('Use ZPullToRefresh instead.')
typedef ZeroPullToRefresh = ZPullToRefresh;

/// A zero-allocation, zero-`saveLayer` fractional star rating widget.
///
/// Pre-caches star geometry once on layout and uses `Canvas.clipRect` +
/// [ZeroNumberPainter.paintDouble] for fractional star fills without `ShaderMask`.
class ZRatingBar extends ZLeafWidget<RenderZRatingBar> {
  /// Reactive rating value (`0.0 .. starCount`).
  final ValueListenable<double> ratingListenable;

  /// Optional mutable controller updated on pointer drag/tap.
  final ValueNotifier<double>? controller;

  /// Optional callback invoked when user changes the rating.
  final ValueChanged<double>? onRatingChanged;

  /// Number of stars.
  final int starCount;

  /// Size of each star in logical pixels.
  final double starSize;

  /// Active filled star color.
  final Color activeColor;

  /// Inactive empty star color.
  final Color inactiveColor;

  /// Whether to render the numeric rating readout via [ZeroNumberPainter].
  final bool showNumericLabel;

  /// Creates a const [ZRatingBar].
  const ZRatingBar({
    super.key,
    required this.ratingListenable,
    this.controller,
    this.onRatingChanged,
    this.starCount = 5,
    this.starSize = 22.0,
    this.activeColor = const Color(0xFFFFB300),
    this.inactiveColor = const Color(0xFF334155),
    this.showNumericLabel = true,
  }) : assert(starCount >= 1, 'starCount must be >= 1');

  @override
  RenderZRatingBar createRenderObject(BuildContext context) {
    return RenderZRatingBar(
      ratingListenable: ratingListenable,
      controller: controller,
      onRatingChanged: onRatingChanged,
      starCount: starCount,
      starSize: starSize,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      showNumericLabel: showNumericLabel,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZRatingBar renderObject) {
    renderObject
      ..ratingListenable = ratingListenable
      ..controller = controller
      ..onRatingChanged = onRatingChanged
      ..starCount = starCount
      ..starSize = starSize
      ..activeColor = activeColor
      ..inactiveColor = inactiveColor
      ..showNumericLabel = showNumericLabel;
  }
}

/// Custom [ZeroRenderBox] for [ZRatingBar].
class RenderZRatingBar extends ZeroRenderBox {
  ValueListenable<double> _ratingListenable;

  /// Optional mutable rating notifier.
  ValueNotifier<double>? controller;

  /// Optional callback when rating is dragged.
  ValueChanged<double>? onRatingChanged;

  int _starCount;
  double _starSize;
  bool _showNumericLabel;
  static const double _gap = 4.0;

  final Paint _activePaint = Paint()..style = PaintingStyle.fill;
  final Paint _inactivePaint = Paint()..style = PaintingStyle.fill;
  final ZeroNumberPainter _numberPainter = ZeroNumberPainter();
  ui.Picture? _inactiveStarsPicture;
  ui.Picture? _activeStarsPicture;

  /// Creates a [RenderZRatingBar].
  RenderZRatingBar({
    required ValueListenable<double> ratingListenable,
    required this.controller,
    required this.onRatingChanged,
    required int starCount,
    required double starSize,
    required Color activeColor,
    required Color inactiveColor,
    required bool showNumericLabel,
  })  : _ratingListenable = ratingListenable,
        _starCount = math.max(1, starCount),
        _starSize = math.max(10.0, starSize),
        _showNumericLabel = showNumericLabel {
    _activePaint.color = activeColor;
    _inactivePaint.color = inactiveColor;
  }

  /// Rating listenable.
  ValueListenable<double> get ratingListenable => _ratingListenable;
  set ratingListenable(ValueListenable<double> value) {
    if (identical(_ratingListenable, value)) return;
    if (attached) {
      _ratingListenable.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _ratingListenable = value;
    markDirty();
  }

  /// Number of stars.
  int get starCount => _starCount;
  set starCount(int value) {
    final int safe = math.max(1, value);
    if (_starCount == safe) return;
    _starCount = safe;
    _disposeCachedPictures();
    markNeedsLayout();
  }

  /// Star diameter.
  double get starSize => _starSize;
  set starSize(double value) {
    final double safe = math.max(10.0, value);
    if (_starSize == safe) return;
    _starSize = safe;
    _disposeCachedPictures();
    markNeedsLayout();
  }

  /// Active star color.
  Color get activeColor => _activePaint.color;
  set activeColor(Color value) {
    if (_activePaint.color == value) return;
    _activePaint.color = value;
    _disposeCachedPictures();
    markDirty();
  }

  /// Inactive star color.
  Color get inactiveColor => _inactivePaint.color;
  set inactiveColor(Color value) {
    if (_inactivePaint.color == value) return;
    _inactivePaint.color = value;
    _disposeCachedPictures();
    markDirty();
  }

  /// Whether numeric readout is rendered.
  bool get showNumericLabel => _showNumericLabel;
  set showNumericLabel(bool value) {
    if (_showNumericLabel == value) return;
    _showNumericLabel = value;
    markNeedsLayout();
  }

  void _disposeCachedPictures() {
    _inactiveStarsPicture?.dispose();
    _inactiveStarsPicture = null;
    _activeStarsPicture?.dispose();
    _activeStarsPicture = null;
  }

  void _ensureStarPictures() {
    if (_inactiveStarsPicture != null && _activeStarsPicture != null) return;
    _inactiveStarsPicture = _recordStars(_inactivePaint);
    _activeStarsPicture = _recordStars(_activePaint);
  }

  ui.Picture _recordStars(Paint paint) {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas c = Canvas(recorder);
    final double rOuter = _starSize * 0.5;
    final double rInner = rOuter * 0.42;

    for (int s = 0; s < _starCount; s++) {
      final double cx = s * (_starSize + _gap) + rOuter;
      final double cy = rOuter;
      final Path star = Path();
      for (int i = 0; i < 10; i++) {
        final double angle = -math.pi * 0.5 + i * (math.pi / 5.0);
        final double r = i.isEven ? rOuter : rInner;
        final double px = cx + math.cos(angle) * r;
        final double py = cy + math.sin(angle) * r;
        if (i == 0) {
          star.moveTo(px, py);
        } else {
          star.lineTo(px, py);
        }
      }
      star.close();
      c.drawPath(star, paint);
    }
    return recorder.endRecording();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ratingListenable.addListener(markDirty);
  }

  @override
  void detach() {
    _ratingListenable.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _disposeCachedPictures();
    _numberPainter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      final double starsW = _starCount * _starSize + (_starCount - 1) * _gap;
      final double ratio = (event.localPosition.dx / math.max(1.0, starsW)).clamp(0.0, 1.0);
      final double nextRating = (ratio * _starCount * 10.0).round() / 10.0;
      controller?.value = nextRating;
      onRatingChanged?.call(nextRating);
      markDirty();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final double starsW = _starCount * _starSize + (_starCount - 1) * _gap;
    final double labelW = _showNumericLabel ? (_numberPainter.maxDigitWidth * 3.5 + 8.0) : 0.0;
    return constraints.constrain(Size(starsW + labelW, math.max(_starSize, 24.0)));
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    _ensureStarPictures();
    final Canvas canvas = context.canvas;
    final double starsW = _starCount * _starSize + (_starCount - 1) * _gap;
    final double dy = offset.dy + (size.height - _starSize) * 0.5;
    final double rating = _ratingListenable.value.clamp(0.0, _starCount.toDouble());
    final double fillRatio = rating / _starCount;

    canvas.save();
    canvas.translate(offset.dx, dy);
    canvas.drawPicture(_inactiveStarsPicture!);
    canvas.clipRect(Rect.fromLTWH(0.0, 0.0, starsW * fillRatio, _starSize));
    canvas.drawPicture(_activeStarsPicture!);
    canvas.restore();

    if (_showNumericLabel) {
      final double textY = offset.dy + (size.height - _numberPainter.height) * 0.5;
      _numberPainter.paintDouble(
        canvas,
        Offset(offset.dx + starsW + 6.0, textY),
        rating,
        fractionDigits: 1,
      );
    }
  }
}

/// A zero-allocation pull-to-refresh header indicator widget.
///
/// Renders radial pull spokes, spinning refresh state, and percentage readout
/// directly via [ZeroRenderBox] + [ZeroNumberPainter] without widget rebuilds.
class ZPullToRefresh extends ZLeafWidget<RenderZPullToRefresh> {
  /// Pull progress listenable (`0.0 .. 1.0+`).
  final ValueListenable<double> pullProgressListenable;

  /// Whether the refresh spinner is actively rotating.
  final bool isRefreshing;

  /// Preferred widget size.
  final Size size;

  /// Spoke and arc accent color.
  final Color color;

  /// Creates a const [ZPullToRefresh].
  const ZPullToRefresh({
    super.key,
    required this.pullProgressListenable,
    this.isRefreshing = false,
    this.size = const Size(120.0, 44.0),
    this.color = const Color(0xFF00E5FF),
  });

  @override
  RenderZPullToRefresh createRenderObject(BuildContext context) {
    return RenderZPullToRefresh(
      pullProgressListenable: pullProgressListenable,
      isRefreshing: isRefreshing,
      preferredSize: size,
      color: color,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZPullToRefresh renderObject,
  ) {
    renderObject
      ..pullProgressListenable = pullProgressListenable
      ..isRefreshing = isRefreshing
      ..preferredSize = size
      ..color = color;
  }
}

/// Custom [ZeroRenderBox] for [ZPullToRefresh].
class RenderZPullToRefresh extends ZeroRenderBox {
  ValueListenable<double> _pullProgressListenable;
  bool _isRefreshing;
  Size _preferredSize;
  double _spinAngle = 0.0;

  final Paint _spokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;
  final ZeroNumberPainter _numberPainter = ZeroNumberPainter();

  /// Creates a [RenderZPullToRefresh].
  RenderZPullToRefresh({
    required ValueListenable<double> pullProgressListenable,
    required bool isRefreshing,
    required Size preferredSize,
    required Color color,
  })  : _pullProgressListenable = pullProgressListenable,
        _isRefreshing = isRefreshing,
        _preferredSize = preferredSize,
        super(animatePerFrame: isRefreshing) {
    _spokePaint.color = color;
  }

  /// Pull progress listenable.
  ValueListenable<double> get pullProgressListenable => _pullProgressListenable;
  set pullProgressListenable(ValueListenable<double> value) {
    if (identical(_pullProgressListenable, value)) return;
    if (attached) {
      _pullProgressListenable.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _pullProgressListenable = value;
    markDirty();
  }

  /// Whether actively refreshing.
  bool get isRefreshing => _isRefreshing;
  set isRefreshing(bool value) {
    if (_isRefreshing == value) return;
    _isRefreshing = value;
    animatePerFrame = value;
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Spoke color.
  Color get color => _spokePaint.color;
  set color(Color value) {
    if (_spokePaint.color == value) return;
    _spokePaint.color = value;
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _pullProgressListenable.addListener(markDirty);
  }

  @override
  void detach() {
    _pullProgressListenable.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _numberPainter.dispose();
    super.dispose();
  }

  @override
  void onZeroFrame(Duration elapsed) {
    _spinAngle = (elapsed.inMilliseconds / 160.0) % (math.pi * 2.0);
    markDirty();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double progress = _pullProgressListenable.value.clamp(0.0, 1.0);
    final int activeSpokes = _isRefreshing ? 8 : (progress * 8.0).ceil();
    final double cx = offset.dx + 22.0;
    final double cy = offset.dy + size.height * 0.5;
    final double baseAngle = _isRefreshing ? _spinAngle : progress * math.pi;

    for (int i = 0; i < activeSpokes; i++) {
      final double a = baseAngle + i * (math.pi * 0.25);
      final Offset p0 = Offset(cx + math.cos(a) * 5.0, cy + math.sin(a) * 5.0);
      final Offset p1 = Offset(cx + math.cos(a) * 11.0, cy + math.sin(a) * 11.0);
      canvas.drawLine(p0, p1, _spokePaint);
    }

    final double textY = cy - _numberPainter.height * 0.5;
    _numberPainter.paintPercent(
      canvas,
      Offset(cx + 18.0, textY),
      progress * 100.0,
      fractionDigits: 0,
    );
  }
}

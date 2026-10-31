import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZSegmentedControl].
typedef ZSlidingTabBar = ZSegmentedControl;

/// Legacy alias for [ZSegmentedControl].
@Deprecated('Use ZSegmentedControl instead.')
typedef ZeroSegmentedControl = ZSegmentedControl;

/// Active alias for [ZPageIndicator].
typedef ZWormIndicator = ZPageIndicator;

/// Legacy alias for [ZPageIndicator].
@Deprecated('Use ZPageIndicator instead.')
typedef ZeroPageIndicator = ZPageIndicator;

/// A zero-allocation, zero-rebuild sliding segmented tab bar widget.
///
/// Tracks either an integer index or a continuous page position (`0.0 .. N-1`)
/// and interpolates the active thumb pill directly on the Impeller `Canvas`.
class ZSegmentedControl extends ZLeafWidget<RenderZSegmentedControl> {
  /// Segment label strings pre-laid out once on configuration change.
  final List<String> segments;

  /// Continuous or discrete selected index (`0.0 .. segments.length - 1`).
  final ValueListenable<double> positionListenable;

  /// Optional callback invoked when a segment is tapped.
  final ValueChanged<int>? onSegmentTapped;

  /// Preferred widget size.
  final Size size;

  /// Active sliding thumb color.
  final Color thumbColor;

  /// Track background color.
  final Color backgroundColor;

  /// Segment label text style.
  final TextStyle textStyle;

  /// Creates a const [ZSegmentedControl].
  const ZSegmentedControl({
    super.key,
    required this.segments,
    required this.positionListenable,
    this.onSegmentTapped,
    this.size = const Size(260.0, 36.0),
    this.thumbColor = const Color(0xFF00E5FF),
    this.backgroundColor = const Color(0xFF111827),
    this.textStyle = const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFFFFF),
    ),
  }) : assert(segments.length >= 2, 'At least 2 segments are required.');

  @override
  RenderZSegmentedControl createRenderObject(BuildContext context) {
    return RenderZSegmentedControl(
      segments: segments,
      positionListenable: positionListenable,
      onSegmentTapped: onSegmentTapped,
      preferredSize: size,
      thumbColor: thumbColor,
      backgroundColor: backgroundColor,
      textStyle: textStyle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZSegmentedControl renderObject,
  ) {
    renderObject
      ..segments = segments
      ..positionListenable = positionListenable
      ..onSegmentTapped = onSegmentTapped
      ..preferredSize = size
      ..thumbColor = thumbColor
      ..backgroundColor = backgroundColor;
  }
}

/// Custom [ZeroRenderBox] for [ZSegmentedControl].
class RenderZSegmentedControl extends ZeroRenderBox {
  List<String> _segments;
  ValueListenable<double> _positionListenable;

  /// Callback when a segment slot is tapped.
  ValueChanged<int>? onSegmentTapped;

  Size _preferredSize;
  final TextStyle _textStyle;
  final List<TextPainter> _labelPainters = <TextPainter>[];

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _thumbPaint = Paint()..style = PaintingStyle.fill;

  /// Creates a [RenderZSegmentedControl].
  RenderZSegmentedControl({
    required List<String> segments,
    required ValueListenable<double> positionListenable,
    required this.onSegmentTapped,
    required Size preferredSize,
    required Color thumbColor,
    required Color backgroundColor,
    required TextStyle textStyle,
  })  : _segments = segments,
        _positionListenable = positionListenable,
        _preferredSize = preferredSize,
        _textStyle = textStyle {
    _bgPaint.color = backgroundColor;
    _thumbPaint.color = thumbColor;
    _rebuildLabelPainters();
  }

  /// Segment labels.
  List<String> get segments => _segments;
  set segments(List<String> value) {
    if (listEquals(_segments, value)) return;
    _segments = value;
    _rebuildLabelPainters();
    markDirty();
  }

  /// Position listenable.
  ValueListenable<double> get positionListenable => _positionListenable;
  set positionListenable(ValueListenable<double> value) {
    if (identical(_positionListenable, value)) return;
    if (attached) {
      _positionListenable.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _positionListenable = value;
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Sliding thumb color.
  Color get thumbColor => _thumbPaint.color;
  set thumbColor(Color value) {
    if (_thumbPaint.color == value) return;
    _thumbPaint.color = value;
    markDirty();
  }

  /// Track background color.
  Color get backgroundColor => _bgPaint.color;
  set backgroundColor(Color value) {
    if (_bgPaint.color == value) return;
    _bgPaint.color = value;
    markDirty();
  }

  void _rebuildLabelPainters() {
    for (final TextPainter tp in _labelPainters) {
      tp.dispose();
    }
    _labelPainters.clear();
    for (final String text in _segments) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: text, style: _textStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      _labelPainters.add(tp);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _positionListenable.addListener(markDirty);
  }

  @override
  void detach() {
    _positionListenable.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    for (final TextPainter tp in _labelPainters) {
      tp.dispose();
    }
    _labelPainters.clear();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent && size.width > 0) {
      final int count = _segments.length;
      final int idx =
          ((event.localPosition.dx / size.width) * count).floor().clamp(0, count - 1);
      onSegmentTapped?.call(idx);
    }
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
    final int count = _segments.length;
    final RRect track = RRect.fromRectAndRadius(
      offset & size,
      const Radius.circular(8.0),
    );
    canvas.drawRRect(track, _bgPaint);

    const double pad = 3.0;
    final double segW = math.max(1.0, (size.width - pad * 2.0) / count);
    final double pos = _positionListenable.value.clamp(0.0, (count - 1).toDouble());
    final Rect thumbRect = Rect.fromLTWH(
      offset.dx + pad + pos * segW,
      offset.dy + pad,
      segW,
      math.max(1.0, size.height - pad * 2.0),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(thumbRect, const Radius.circular(6.0)),
      _thumbPaint,
    );

    for (int i = 0; i < _labelPainters.length; i++) {
      final TextPainter tp = _labelPainters[i];
      final double cx = offset.dx + pad + (i + 0.5) * segW - tp.width * 0.5;
      final double cy = offset.dy + (size.height - tp.height) * 0.5;
      tp.paint(canvas, Offset(cx, cy));
    }
  }
}

/// A zero-allocation worm-style carousel page indicator widget.
///
/// Renders all dots and the stretching active worm pill inside a single
/// [ZeroRenderBox] without creating per-dot `AnimatedContainer` widgets.
class ZPageIndicator extends ZLeafWidget<RenderZPageIndicator> {
  /// Total number of pages.
  final int count;

  /// Continuous page offset (`0.0 .. count - 1`).
  final ValueListenable<double> pageListenable;

  /// Dot diameter in logical pixels.
  final double dotSize;

  /// Horizontal spacing between dots.
  final double spacing;

  /// Active worm indicator color.
  final Color activeColor;

  /// Inactive dot color.
  final Color inactiveColor;

  /// Creates a const [ZPageIndicator].
  const ZPageIndicator({
    super.key,
    required this.count,
    required this.pageListenable,
    this.dotSize = 8.0,
    this.spacing = 8.0,
    this.activeColor = const Color(0xFF00FF88),
    this.inactiveColor = const Color(0xFF334155),
  }) : assert(count >= 1, 'count must be >= 1');

  @override
  RenderZPageIndicator createRenderObject(BuildContext context) {
    return RenderZPageIndicator(
      count: count,
      pageListenable: pageListenable,
      dotSize: dotSize,
      spacing: spacing,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZPageIndicator renderObject,
  ) {
    renderObject
      ..count = count
      ..pageListenable = pageListenable
      ..dotSize = dotSize
      ..spacing = spacing
      ..activeColor = activeColor
      ..inactiveColor = inactiveColor;
  }
}

/// Custom [ZeroRenderBox] for [ZPageIndicator].
class RenderZPageIndicator extends ZeroRenderBox {
  int _count;
  ValueListenable<double> _pageListenable;
  double _dotSize;
  double _spacing;

  final Paint _activePaint = Paint()..style = PaintingStyle.fill;
  final Paint _inactivePaint = Paint()..style = PaintingStyle.fill;

  /// Creates a [RenderZPageIndicator].
  RenderZPageIndicator({
    required int count,
    required ValueListenable<double> pageListenable,
    required double dotSize,
    required double spacing,
    required Color activeColor,
    required Color inactiveColor,
  })  : _count = math.max(1, count),
        _pageListenable = pageListenable,
        _dotSize = dotSize,
        _spacing = spacing {
    _activePaint.color = activeColor;
    _inactivePaint.color = inactiveColor;
  }

  /// Total dot count.
  int get count => _count;
  set count(int value) {
    final int safe = math.max(1, value);
    if (_count == safe) return;
    _count = safe;
    markNeedsLayout();
  }

  /// Continuous page offset listenable.
  ValueListenable<double> get pageListenable => _pageListenable;
  set pageListenable(ValueListenable<double> value) {
    if (identical(_pageListenable, value)) return;
    if (attached) {
      _pageListenable.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _pageListenable = value;
    markDirty();
  }

  /// Dot diameter.
  double get dotSize => _dotSize;
  set dotSize(double value) {
    if (_dotSize == value) return;
    _dotSize = value;
    markNeedsLayout();
  }

  /// Gap between dots.
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  /// Active worm color.
  Color get activeColor => _activePaint.color;
  set activeColor(Color value) {
    if (_activePaint.color == value) return;
    _activePaint.color = value;
    markDirty();
  }

  /// Inactive dot color.
  Color get inactiveColor => _inactivePaint.color;
  set inactiveColor(Color value) {
    if (_inactivePaint.color == value) return;
    _inactivePaint.color = value;
    markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _pageListenable.addListener(markDirty);
  }

  @override
  void detach() {
    _pageListenable.removeListener(markDirty);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final double w = _count * _dotSize + (_count - 1) * _spacing + 8.0;
    return constraints.constrain(Size(w, _dotSize + 8.0));
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double step = _dotSize + _spacing;
    final double totalW = _count * _dotSize + (_count - 1) * _spacing;
    final double startX = offset.dx + (size.width - totalW) * 0.5;
    final double cy = offset.dy + size.height * 0.5;
    final double radius = _dotSize * 0.5;

    for (int i = 0; i < _count; i++) {
      canvas.drawCircle(
        Offset(startX + i * step + radius, cy),
        radius,
        _inactivePaint,
      );
    }

    final double page = _pageListenable.value.clamp(0.0, (_count - 1).toDouble());
    final int baseIdx = page.floor();
    final double frac = page - baseIdx;
    final double stretch = (0.5 - (frac - 0.5).abs()) * 2.0 * step;
    final double wormLeft = startX + page * step - stretch * 0.5;
    final double wormWidth = _dotSize + stretch;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(wormLeft, cy - radius, wormWidth, _dotSize),
        Radius.circular(radius),
      ),
      _activePaint,
    );
  }
}

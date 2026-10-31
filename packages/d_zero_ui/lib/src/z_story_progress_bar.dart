import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZStoryProgressBar].
typedef ZSegmentedProgress = ZStoryProgressBar;

/// Legacy alias for [ZStoryProgressBar].
@Deprecated('Use ZStoryProgressBar instead.')
typedef ZeroStoryProgressBar = ZStoryProgressBar;

/// Zero-allocation controller for [ZStoryProgressBar] managing multi-segment
/// story/reel progress in a single flat state object.
class ZeroStoryProgressController extends ChangeNotifier {
  final int _segmentCount;
  int _activeIndex = 0;
  double _segmentProgress = 0.0;
  bool _isDisposed = false;

  /// Creates a [ZeroStoryProgressController] with [segmentCount] segments.
  ZeroStoryProgressController({
    int segmentCount = 5,
    int initialIndex = 0,
    double initialProgress = 0.0,
  })  : _segmentCount = math.max(1, segmentCount),
        _activeIndex = initialIndex.clamp(0, math.max(1, segmentCount) - 1),
        _segmentProgress = initialProgress.clamp(0.0, 1.0);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Total number of story segments.
  int get segmentCount => _segmentCount;

  /// Current active segment index (`0` if disposed).
  int get activeIndex => _isDisposed ? 0 : _activeIndex;

  /// Current segment progress (`0.0 .. 1.0`, or `0.0` if disposed).
  double get segmentProgress => _isDisposed ? 0.0 : _segmentProgress;

  /// Updates the active segment and progress in place.
  void setProgress(int index, double progress) {
    if (_isDisposed) return;
    final int idx = index.clamp(0, _segmentCount - 1);
    final double p = progress.clamp(0.0, 1.0);
    if (_activeIndex == idx && _segmentProgress == p) return;
    _activeIndex = idx;
    _segmentProgress = p;
    notifyListeners();
  }

  /// Advances story progress by [delta], automatically wrapping across segments.
  void advance(double delta) {
    if (_isDisposed) return;
    double next = _segmentProgress + delta;
    while (next >= 1.0) {
      next -= 1.0;
      _activeIndex = (_activeIndex + 1) % _segmentCount;
    }
    _segmentProgress = next.clamp(0.0, 1.0);
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeIndex = 0;
    _segmentProgress = 0.0;
    super.dispose();
  }
}

/// A zero-allocation multi-segment story/reel progress bar widget
/// (Instagram Stories / TikTok / Shorts top indicator).
///
/// Draws completed, active, and upcoming segments in a single [ZeroRenderBox]
/// pass without instantiating multiple `LinearProgressIndicator` widgets.
class ZStoryProgressBar extends ZLeafWidget<RenderZStoryProgressBar> {
  /// Controller holding segment count, active index, and progress.
  final ZeroStoryProgressController controller;

  /// Preferred widget size.
  final Size size;

  /// Spacing between segments in logical pixels.
  final double spacing;

  /// Active and completed segment fill color.
  final Color activeColor;

  /// Upcoming segment track color.
  final Color inactiveColor;

  /// Creates a const [ZStoryProgressBar].
  const ZStoryProgressBar({
    super.key,
    required this.controller,
    this.size = const Size(260.0, 6.0),
    this.spacing = 4.0,
    this.activeColor = const Color(0xFF00FF88),
    this.inactiveColor = const Color(0xFF334155),
  });

  @override
  RenderZStoryProgressBar createRenderObject(BuildContext context) {
    return RenderZStoryProgressBar(
      controller: controller,
      preferredSize: size,
      spacing: spacing,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZStoryProgressBar renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..spacing = spacing
      ..activeColor = activeColor
      ..inactiveColor = inactiveColor;
  }
}

/// Custom [ZeroRenderBox] for [ZStoryProgressBar].
class RenderZStoryProgressBar extends ZeroRenderBox {
  ZeroStoryProgressController _controller;
  Size _preferredSize;
  double _spacing;

  final Paint _activePaint = Paint()..style = PaintingStyle.fill;
  final Paint _inactivePaint = Paint()..style = PaintingStyle.fill;

  /// Creates a [RenderZStoryProgressBar].
  RenderZStoryProgressBar({
    required ZeroStoryProgressController controller,
    required Size preferredSize,
    required double spacing,
    required Color activeColor,
    required Color inactiveColor,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _spacing = spacing {
    _activePaint.color = activeColor;
    _inactivePaint.color = inactiveColor;
  }

  /// Story progress controller.
  ZeroStoryProgressController get controller => _controller;
  set controller(ZeroStoryProgressController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Segment spacing.
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markDirty();
  }

  /// Active fill color.
  Color get activeColor => _activePaint.color;
  set activeColor(Color value) {
    if (_activePaint.color == value) return;
    _activePaint.color = value;
    markDirty();
  }

  /// Inactive track color.
  Color get inactiveColor => _inactivePaint.color;
  set inactiveColor(Color value) {
    if (_inactivePaint.color == value) return;
    _inactivePaint.color = value;
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
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final int count = _controller.segmentCount;
    final double totalGap = (count - 1) * _spacing;
    final double segW = math.max(2.0, (size.width - totalGap) / count);
    final Radius r = Radius.circular(size.height * 0.5);
    final int activeIdx = _controller.activeIndex;
    final double activeProg = _controller.segmentProgress;

    for (int i = 0; i < count; i++) {
      final double x = offset.dx + i * (segW + _spacing);
      final Rect trackRect = Rect.fromLTWH(x, offset.dy, segW, size.height);
      if (i < activeIdx) {
        canvas.drawRRect(RRect.fromRectAndRadius(trackRect, r), _activePaint);
      } else if (i > activeIdx) {
        canvas.drawRRect(RRect.fromRectAndRadius(trackRect, r), _inactivePaint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(trackRect, r), _inactivePaint);
        final Rect fillRect =
            Rect.fromLTWH(x, offset.dy, segW * activeProg, size.height);
        canvas.drawRRect(RRect.fromRectAndRadius(fillRect, r), _activePaint);
      }
    }
  }
}

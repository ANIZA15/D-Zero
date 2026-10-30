import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Active alias for [ZMarquee].
typedef ZRollingText = ZMarquee;

/// Legacy alias for [ZMarquee].
@Deprecated('Use ZMarquee instead.')
typedef ZeroMarquee = ZMarquee;

/// A zero-allocation, zero-rebuild marquee / scrolling text widget.
///
/// Lays out a single cached [TextPainter] only when [text] or [style] changes.
/// On each VSync tick, advances its scroll offset and paints the cached text
/// twice for seamless infinite scrolling with zero per-frame allocations.
class ZMarquee extends ZLeafWidget<RenderZMarquee> {
  /// The text string to scroll continuously.
  final String text;

  /// The text style used to render [text].
  final TextStyle style;

  /// Scrolling velocity in logical pixels per second.
  final double velocity;

  /// Horizontal gap in logical pixels between repeated text copies.
  final double gap;

  /// Whether the marquee animation is currently running.
  final bool isRunning;

  /// Creates a const [ZMarquee].
  const ZMarquee({
    super.key,
    required this.text,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 16.0,
    ),
    this.velocity = 60.0,
    this.gap = 48.0,
    this.isRunning = true,
  });

  @override
  RenderZMarquee createRenderObject(BuildContext context) {
    return RenderZMarquee(
      text: text,
      style: style,
      velocity: velocity,
      gap: gap,
      isRunning: isRunning,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZMarquee renderObject) {
    renderObject
      ..text = text
      ..style = style
      ..velocity = velocity
      ..gap = gap
      ..isRunning = isRunning;
  }
}

/// Custom [ZeroRenderBox] for [ZMarquee] that renders scrolling text directly to [Canvas].
class RenderZMarquee extends ZeroRenderBox {
  String _text;
  TextStyle _style;
  double _velocity;
  double _gap;
  bool _isRunning;

  final TextPainter _textPainter = TextPainter(textDirection: TextDirection.ltr);
  double _scrollOffset = 0.0;
  int _lastElapsedMicros = -1;
  bool _needsTextLayout = true;

  /// Creates a [RenderZMarquee].
  RenderZMarquee({
    required String text,
    required TextStyle style,
    required double velocity,
    required double gap,
    required bool isRunning,
  })  : _text = text,
        _style = style,
        _velocity = velocity,
        _gap = gap,
        _isRunning = isRunning,
        super(animatePerFrame: isRunning) {
    _layoutTextIfNeeded();
  }

  /// Current text string.
  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    _needsTextLayout = true;
    markNeedsLayout();
  }

  /// Current text style.
  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _needsTextLayout = true;
    markNeedsLayout();
  }

  /// Current velocity in pixels per second.
  double get velocity => _velocity;
  set velocity(double value) {
    if (_velocity == value) return;
    _velocity = value;
    markDirty();
  }

  /// Gap between repeated text instances.
  double get gap => _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markDirty();
  }

  /// Whether scrolling is active.
  bool get isRunning => _isRunning;
  set isRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    _lastElapsedMicros = -1;
    animatePerFrame = value;
  }

  /// Current horizontal scroll offset in logical pixels.
  double get scrollOffset => _scrollOffset;

  void _layoutTextIfNeeded() {
    if (!_needsTextLayout) return;
    _needsTextLayout = false;
    _textPainter.text = TextSpan(text: _text, style: _style);
    _textPainter.layout();
  }

  @override
  void detach() {
    _lastElapsedMicros = -1;
    super.detach();
  }

  @override
  void dispose() {
    _textPainter.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    _layoutTextIfNeeded();
    final double desiredW = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : _textPainter.width;
    final double desiredH = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : _textPainter.height;
    size = constraints.constrain(Size(desiredW, desiredH));
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isRunning) return false;
    final int micros = elapsed.inMicroseconds;
    if (_lastElapsedMicros < 0) {
      _lastElapsedMicros = micros;
      return false;
    }
    final int deltaMicros = micros - _lastElapsedMicros;
    _lastElapsedMicros = micros;
    if (deltaMicros <= 0) return false;
    return _advanceScroll(deltaMicros / 1000000.0);
  }

  bool _advanceScroll(double dtSeconds) {
    final double cycleSpan = _textPainter.width + _gap;
    if (cycleSpan <= 0.0) return false;
    _scrollOffset = (_scrollOffset + _velocity * dtSeconds) % cycleSpan;
    if (_scrollOffset < 0.0) {
      _scrollOffset += cycleSpan;
    }
    return true;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    _layoutTextIfNeeded();
    final double textW = _textPainter.width;
    if (textW <= 0.0 || size.width <= 0.0 || size.height <= 0.0) return;

    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);

    final double dy = offset.dy + (size.height - _textPainter.height) * 0.5;
    final double firstX = offset.dx - _scrollOffset;
    _textPainter.paint(canvas, Offset(firstX, dy));

    final double secondX = firstX + textW + _gap;
    if (secondX < offset.dx + size.width) {
      _textPainter.paint(canvas, Offset(secondX, dy));
    }
    canvas.restore();
  }
}

import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Legacy alias for [ZTypewriterText].
@Deprecated('Use ZTypewriterText instead.')
typedef ZeroTypewriterText = ZTypewriterText;

/// A zero-allocation, zero-rebuild typewriter text animation widget.
///
/// Uses a single pre-laid-out [TextPainter] for the full string and reveals
/// characters progressively by querying [TextPainter.getOffsetForCaret] and
/// clipping with [Canvas.clipRect], drawing a blinking cursor rect with a
/// pre-allocated [Paint]—zero `substring()` or [String] allocations per frame.
class ZTypewriterText extends ZLeafWidget<RenderZTypewriterText> {
  /// Full text string to reveal progressively.
  final String text;

  /// Text style used to render [text].
  final TextStyle style;

  /// Duration per revealed character.
  final Duration charDuration;

  /// Whether the typewriter animation is actively playing.
  final bool isPlaying;

  /// Color of the blinking caret cursor.
  final Color cursorColor;

  /// Creates a const [ZTypewriterText].
  const ZTypewriterText({
    super.key,
    required this.text,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 16.0,
    ),
    this.charDuration = const Duration(milliseconds: 40),
    this.isPlaying = true,
    this.cursorColor = const Color(0xFF00E5FF),
  });

  @override
  RenderZTypewriterText createRenderObject(BuildContext context) {
    return RenderZTypewriterText(
      text: text,
      style: style,
      charDuration: charDuration,
      isPlaying: isPlaying,
      cursorColor: cursorColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZTypewriterText renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style
      ..charDuration = charDuration
      ..isPlaying = isPlaying
      ..cursorColor = cursorColor;
  }
}

/// Custom [ZeroRenderBox] for [ZTypewriterText].
class RenderZTypewriterText extends ZeroRenderBox {
  String _text;
  TextStyle _style;
  Duration _charDuration;
  bool _isPlaying;

  final TextPainter _textPainter =
      TextPainter(textDirection: TextDirection.ltr);
  final Paint _cursorPaint = Paint()..style = PaintingStyle.fill;

  int _visibleChars = 0;
  int _elapsedMicros = 0;
  int _lastTickMicros = -1;
  bool _cursorVisible = true;
  bool _needsTextLayout = true;

  /// Creates a [RenderZTypewriterText].
  RenderZTypewriterText({
    required String text,
    required TextStyle style,
    required Duration charDuration,
    required bool isPlaying,
    required Color cursorColor,
  })  : _text = text,
        _style = style,
        _charDuration = charDuration,
        _isPlaying = isPlaying,
        super(animatePerFrame: isPlaying) {
    _cursorPaint.color = cursorColor;
    _layoutTextIfNeeded();
  }

  /// Current full text string.
  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    _visibleChars = 0;
    _elapsedMicros = 0;
    _lastTickMicros = -1;
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

  /// Duration per character.
  Duration get charDuration => _charDuration;
  set charDuration(Duration value) {
    if (_charDuration == value) return;
    _charDuration = value;
    markDirty();
  }

  /// Whether animation is playing.
  bool get isPlaying => _isPlaying;
  set isPlaying(bool value) {
    if (_isPlaying == value) return;
    _isPlaying = value;
    _lastTickMicros = -1;
    animatePerFrame = value;
  }

  /// Cursor color.
  Color get cursorColor => _cursorPaint.color;
  set cursorColor(Color value) {
    if (_cursorPaint.color == value) return;
    _cursorPaint.color = value;
    markDirty();
  }

  /// Number of currently visible characters.
  int get visibleChars => _visibleChars;

  void _layoutTextIfNeeded() {
    if (!_needsTextLayout) return;
    _needsTextLayout = false;
    _textPainter.text = TextSpan(text: _text, style: _style);
    _textPainter.layout();
  }

  @override
  void detach() {
    _lastTickMicros = -1;
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
    final double w = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : (_textPainter.width + 8.0);
    final double h = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : _textPainter.height;
    size = constraints.constrain(Size(w, h));
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isPlaying) return false;
    final int nowMicros = elapsed.inMicroseconds;
    if (_lastTickMicros < 0) {
      _lastTickMicros = nowMicros;
      return false;
    }
    final int dt = nowMicros - _lastTickMicros;
    _lastTickMicros = nowMicros;
    if (dt <= 0) return false;
    return _updateProgress(dt);
  }

  bool _updateProgress(int dtMicros) {
    _elapsedMicros += dtMicros;
    final int stepMicros = _effectiveStepMicros();
    final int totalLen = _text.length;
    final int nextChars = (_elapsedMicros ~/ stepMicros).clamp(0, totalLen);
    final bool nextCursor = ((_elapsedMicros ~/ 500000) & 1) == 0;
    if (nextChars == _visibleChars && nextCursor == _cursorVisible) {
      return false;
    }
    _visibleChars = nextChars;
    _cursorVisible = nextCursor;
    return true;
  }

  int _effectiveStepMicros() {
    final int raw = _charDuration.inMicroseconds;
    return raw > 0 ? raw : 1000;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    _layoutTextIfNeeded();
    final Canvas canvas = context.canvas;
    final double dy = offset.dy + (size.height - _textPainter.height) * 0.5;
    final int clampedChars = _visibleChars.clamp(0, _text.length);
    final Offset caretOffset = _textPainter.getOffsetForCaret(
      TextPosition(offset: clampedChars),
      Rect.zero,
    );
    final double revealWidth = caretOffset.dx;

    if (revealWidth > 0.0) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(offset.dx, offset.dy, revealWidth, size.height),
      );
      _textPainter.paint(canvas, Offset(offset.dx, dy));
      canvas.restore();
    }

    if (_cursorVisible) {
      final double cursorH =
          _textPainter.height > 0.0 ? _textPainter.height : size.height;
      canvas.drawRect(
        Rect.fromLTWH(offset.dx + revealWidth + 1.0, dy, 2.0, cursorH),
        _cursorPaint,
      );
    }
  }
}

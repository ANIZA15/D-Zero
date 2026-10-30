import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// A zero-allocation, zero-rebuild countdown timer widget that renders remaining
/// time directly onto the Canvas using a shared GPU glyph atlas.
class ZCountdown extends ZLeafWidget<RenderZCountdown> {
  /// Total countdown duration.
  final Duration duration;

  /// Whether the countdown is currently running.
  final bool isRunning;

  /// Whether to include hours (`HH:MM:SS`) in the formatted timecode.
  final bool includeHours;

  /// Text style applied to normal countdown digits.
  final TextStyle style;

  /// Optional text style applied when remaining time is at or below [warningThreshold].
  final TextStyle? warningStyle;

  /// Remaining time threshold at which [warningStyle] becomes active.
  final Duration warningThreshold;

  /// Optional callback invoked once when the countdown reaches zero.
  final VoidCallback? onFinished;

  const ZCountdown({
    super.key,
    required this.duration,
    this.isRunning = true,
    this.includeHours = false,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 20.0,
      fontFamily: 'monospace',
    ),
    this.warningStyle,
    this.warningThreshold = const Duration(seconds: 10),
    this.onFinished,
  });

  @override
  RenderZCountdown createRenderObject(BuildContext context) {
    return RenderZCountdown(
      duration: duration,
      isRunning: isRunning,
      includeHours: includeHours,
      style: style,
      warningStyle: warningStyle,
      warningThreshold: warningThreshold,
      onFinished: onFinished,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZCountdown renderObject) {
    renderObject
      ..duration = duration
      ..isRunning = isRunning
      ..includeHours = includeHours
      ..style = style
      ..warningStyle = warningStyle
      ..warningThreshold = warningThreshold
      ..onFinished = onFinished;
  }
}

/// Backward compatibility alias for [ZCountdown].
@Deprecated('Use ZCountdown instead.')
typedef ZeroCountdown = ZCountdown;

/// Internal RenderBox for [ZCountdown] performing zero-allocation countdown rendering.
class RenderZCountdown extends ZeroRenderBox {
  Duration _duration;
  bool _isRunning;
  bool _includeHours;
  TextStyle _style;
  TextStyle? _warningStyle;
  Duration _warningThreshold;
  VoidCallback? onFinished;

  late ZeroNumberPainter _painter;
  ZeroNumberPainter? _warningPainter;

  int _elapsedMs = 0;
  Duration? _lastTickElapsed;
  int _lastPaintedSecond = -1;
  bool _hasFinished = false;

  RenderZCountdown({
    required Duration duration,
    required bool isRunning,
    required bool includeHours,
    required TextStyle style,
    TextStyle? warningStyle,
    required Duration warningThreshold,
    this.onFinished,
  })  : _duration = duration,
        _isRunning = isRunning,
        _includeHours = includeHours,
        _style = style,
        _warningStyle = warningStyle,
        _warningThreshold = warningThreshold,
        super(animatePerFrame: isRunning) {
    _painter = ZeroNumberPainter(style: _style);
    _rebuildWarningPainter();
  }

  void _rebuildWarningPainter() {
    _warningPainter?.dispose();
    final TextStyle? ws = _warningStyle;
    _warningPainter = ws != null ? ZeroNumberPainter(style: ws) : null;
  }

  Duration get duration => _duration;
  set duration(Duration value) {
    if (_duration == value) return;
    _duration = value;
    reset();
  }

  bool get isRunning => _isRunning;
  set isRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    _lastTickElapsed = null;
    _syncRunningState();
    markDirty();
  }

  void _syncRunningState() {
    animatePerFrame = _isRunning && !_hasFinished;
  }

  bool get includeHours => _includeHours;
  set includeHours(bool value) {
    if (_includeHours == value) return;
    _includeHours = value;
    markNeedsLayout();
  }

  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _painter.dispose();
    _painter = ZeroNumberPainter(style: _style);
    markNeedsLayout();
  }

  TextStyle? get warningStyle => _warningStyle;
  set warningStyle(TextStyle? value) {
    if (_warningStyle == value) return;
    _warningStyle = value;
    _rebuildWarningPainter();
    markNeedsPaint();
  }

  Duration get warningThreshold => _warningThreshold;
  set warningThreshold(Duration value) {
    if (_warningThreshold == value) return;
    _warningThreshold = value;
    markNeedsPaint();
  }

  /// Resets the countdown back to full [duration].
  void reset() {
    _elapsedMs = 0;
    _lastTickElapsed = null;
    _lastPaintedSecond = -1;
    _hasFinished = false;
    _syncRunningState();
    markDirty();
  }

  int _remainingMilliseconds() {
    final int rem = _duration.inMilliseconds - _elapsedMs;
    return rem > 0 ? rem : 0;
  }

  @override
  void detach() {
    _lastTickElapsed = null;
    super.detach();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isRunning || _hasFinished) return false;
    final Duration? prev = _lastTickElapsed;
    _lastTickElapsed = elapsed;
    if (prev != null) {
      final int deltaMs = (elapsed - prev).inMilliseconds;
      if (deltaMs > 0) {
        _elapsedMs += deltaMs;
      }
    }
    final int remMs = _remainingMilliseconds();
    if (remMs == 0) {
      _handleFinished();
      return true;
    }
    final int currentSecond = (remMs + 999) ~/ 1000;
    if (currentSecond == _lastPaintedSecond) return false;
    _lastPaintedSecond = currentSecond;
    return true;
  }

  void _handleFinished() {
    _hasFinished = true;
    animatePerFrame = false;
    _lastPaintedSecond = 0;
    onFinished?.call();
  }

  @override
  void performLayout() {
    final double width = _painter.estimateTimecodeWidth(includeHours: _includeHours);
    final double height = _painter.height;
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final int remMs = _remainingMilliseconds();
    final int displayMs = remMs > 0 ? remMs + 999 : 0;
    final ZeroNumberPainter activePainter = _selectPainter(remMs);
    activePainter.paintTimecode(
      context.canvas,
      offset,
      displayMs,
      includeHours: _includeHours,
    );
  }

  ZeroNumberPainter _selectPainter(int remainingMs) {
    final ZeroNumberPainter? warn = _warningPainter;
    if (warn != null && remainingMs <= _warningThreshold.inMilliseconds) {
      return warn;
    }
    return _painter;
  }

  @override
  void dispose() {
    _painter.dispose();
    _warningPainter?.dispose();
    super.dispose();
  }
}

import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// A zero-allocation, zero-rebuild stopwatch widget that renders elapsed time
/// directly onto the Canvas using Impeller/Flutter rendering pipeline.
class ZStopwatch extends ZLeafWidget<RenderZeroStopwatch> {
  /// Whether the stopwatch is currently running.
  final bool isRunning;

  /// Text style applied to the timecode digits.
  final TextStyle style;

  /// Whether to include hours in the timecode.
  final bool includeHours;

  const ZStopwatch({
    super.key,
    this.isRunning = true,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 20.0,
      fontFamily: 'monospace',
    ),
    this.includeHours = false,
  });

  @override
  RenderZeroStopwatch createRenderObject(BuildContext context) {
    return RenderZeroStopwatch(
      isRunning: isRunning,
      style: style,
      includeHours: includeHours,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZeroStopwatch renderObject) {
    renderObject
      ..isRunning = isRunning
      ..style = style
      ..includeHours = includeHours;
  }
}

/// Backward compatibility alias for [ZStopwatch].
@Deprecated('Use ZStopwatch instead.')
typedef ZeroStopwatch = ZStopwatch;

class RenderZeroStopwatch extends ZeroRenderBox {
  bool _isRunning;
  TextStyle _style;
  bool _includeHours;
  late ZeroNumberPainter _painter;

  final Stopwatch _stopwatch = Stopwatch();
  int _lastPaintedSecond = -1;

  RenderZeroStopwatch({
    required bool isRunning,
    required TextStyle style,
    required bool includeHours,
  })  : _isRunning = isRunning,
        _style = style,
        _includeHours = includeHours,
        super(animatePerFrame: isRunning) {
    _painter = ZeroNumberPainter(style: _style);
    if (isRunning) {
      _stopwatch.start();
    }
  }

  bool get isRunning => _isRunning;
  set isRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    animatePerFrame = value;
    if (value) {
      _stopwatch.start();
    } else {
      _stopwatch.stop();
    }
    markDirty();
  }

  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _painter.dispose();
    _painter = ZeroNumberPainter(style: _style);
    markNeedsLayout();
  }

  bool get includeHours => _includeHours;
  set includeHours(bool value) {
    if (_includeHours == value) return;
    _includeHours = value;
    markNeedsLayout();
  }

  /// Resets the stopwatch to zero.
  void reset() {
    _stopwatch.reset();
    _lastPaintedSecond = -1;
    markDirty();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isRunning) return false;
    final int currentSecond = _stopwatch.elapsedMilliseconds ~/ 1000;
    if (currentSecond == _lastPaintedSecond) return false;
    _lastPaintedSecond = currentSecond;
    return true;
  }

  @override
  void performLayout() {
    final width = _painter.estimateTimecodeWidth(includeHours: _includeHours);
    final height = _painter.height;
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final int elapsedMs = _stopwatch.elapsedMilliseconds;
    _lastPaintedSecond = elapsedMs ~/ 1000;
    _painter.paintTimecode(
      context.canvas,
      offset,
      elapsedMs,
      includeHours: _includeHours,
    );
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _painter.dispose();
    super.dispose();
  }
}

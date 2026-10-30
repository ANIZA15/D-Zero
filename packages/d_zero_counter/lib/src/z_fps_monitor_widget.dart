import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// A zero-allocation live FPS and frame-time HUD monitor widget.
///
/// Subscribes to [ZeroFrameScheduler] via [ZeroRenderBox], records a rolling window
/// of 60 frame deltas in a pre-allocated [FloatRingBuffer], and draws a compact
/// frame-time bar chart alongside `FPS` and `ms` readouts with zero heap allocations.
class ZFPSMonitor extends ZLeafWidget<RenderZFPSMonitor> {
  /// Target size of the HUD card.
  final Size size;

  /// Background color of the HUD overlay card.
  final Color backgroundColor;

  /// Text style used for the FPS and frame-time numbers.
  final TextStyle style;

  const ZFPSMonitor({
    super.key,
    this.size = const Size(140.0, 44.0),
    this.backgroundColor = const Color(0xCC10141C),
    this.style = const TextStyle(
      color: Color(0xFF00E676),
      fontSize: 11.0,
      fontFamily: 'monospace',
    ),
  });

  @override
  RenderZFPSMonitor createRenderObject(BuildContext context) {
    return RenderZFPSMonitor(
      targetSize: size,
      backgroundColor: backgroundColor,
      style: style,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZFPSMonitor renderObject) {
    renderObject
      ..targetSize = size
      ..backgroundColor = backgroundColor
      ..style = style;
  }
}

/// Alias for [ZFPSMonitor] when used as a general frame overlay HUD.
typedef ZFrameOverlay = ZFPSMonitor;

/// Backward compatibility alias for [ZFPSMonitor].
@Deprecated('Use ZFPSMonitor instead.')
typedef ZeroFPSMonitor = ZFPSMonitor;

/// Internal RenderBox for [ZFPSMonitor] performing zero-allocation HUD rendering.
class RenderZFPSMonitor extends ZeroRenderBox {
  Size _targetSize;
  Color _backgroundColor;
  TextStyle _style;

  late ZeroNumberPainter _painter;
  final FloatRingBuffer _frameDeltasMs = FloatRingBuffer(60);
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _barPaint = Paint()..style = PaintingStyle.fill;

  Duration _lastElapsed = Duration.zero;
  double _currentFps = 60.0;
  double _currentMs = 16.6;

  RenderZFPSMonitor({
    required Size targetSize,
    required Color backgroundColor,
    required TextStyle style,
  })  : _targetSize = targetSize,
        _backgroundColor = backgroundColor,
        _style = style,
        super(animatePerFrame: true) {
    _bgPaint.color = _backgroundColor;
    _painter = ZeroNumberPainter(style: _style);
  }

  Size get targetSize => _targetSize;
  set targetSize(Size value) {
    if (_targetSize == value) return;
    _targetSize = value;
    markNeedsLayout();
  }

  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markNeedsPaint();
  }

  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _painter.dispose();
    _painter = ZeroNumberPainter(style: _style);
    markNeedsPaint();
  }

  @override
  void detach() {
    _lastElapsed = Duration.zero;
    super.detach();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      _frameDeltasMs.push(16.6);
      return true;
    }
    final int microDelta = (elapsed - _lastElapsed).inMicroseconds;
    _lastElapsed = elapsed;
    if (microDelta <= 0) return false;

    final double dtMs = (microDelta / 1000.0).clamp(1.0, 100.0);
    _frameDeltasMs.push(dtMs);
    final double avgMs = _frameDeltasMs.average;
    _currentMs = avgMs > 0.1 ? avgMs : dtMs;
    _currentFps = (1000.0 / _currentMs).clamp(1.0, 240.0);
    return true;
  }

  @override
  void performLayout() {
    size = constraints.constrain(_targetSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final RRect card = RRect.fromRectAndRadius(
      offset & size,
      const Radius.circular(6.0),
    );
    canvas.drawRRect(card, _bgPaint);

    _paintFrameBars(canvas, offset);

    final double textY = offset.dy + 4.0;
    final double fpsWidth = _painter.paintWithSuffix(
      canvas,
      Offset(offset.dx + 6.0, textY),
      _currentFps,
      suffixGlyph: ZeroNumberPainter.glyphFps,
      fractionDigits: 0,
    );
    _painter.paintWithSuffix(
      canvas,
      Offset(offset.dx + 12.0 + fpsWidth, textY),
      _currentMs,
      suffixGlyph: ZeroNumberPainter.glyphMs,
      fractionDigits: 1,
    );
  }

  void _paintFrameBars(Canvas canvas, Offset offset) {
    final int count = _frameDeltasMs.length;
    if (count <= 0) return;

    final double chartTop = offset.dy + _painter.height + 6.0;
    final double chartBottom = offset.dy + size.height - 4.0;
    final double maxBarH = chartBottom - chartTop;
    if (maxBarH <= 2.0) return;

    final double availW = size.width - 12.0;
    final double barStep = availW / 60.0;
    final double barW = barStep > 1.5 ? barStep - 0.5 : barStep;

    for (int i = 0; i < count; i++) {
      final double ms = _frameDeltasMs[i];
      _barPaint.color = ms > 18.0 ? const Color(0xFFFF5252) : const Color(0xFF00E676);
      final double norm = (ms / 33.3).clamp(0.1, 1.0);
      final double h = norm * maxBarH;
      final double bx = offset.dx + 6.0 + i * barStep;
      canvas.drawRect(Rect.fromLTWH(bx, chartBottom - h, barW, h), _barPaint);
    }
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}

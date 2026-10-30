import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Rendering style for [ZWaveform].
enum ZWaveformStyle {
  /// Connected polyline across audio samples (`ui.PointMode.polygon`).
  polyline,

  /// Symmetric vertical amplitude bars (`ui.PointMode.lines`).
  bars,
}

/// Zero-allocation controller that manages a fixed-capacity ring buffer of
/// normalized audio samples (`-1.0` to `1.0`).
class ZeroWaveformController implements Listenable {
  /// Maximum number of samples stored in the ring buffer.
  final int capacity;
  final FloatRingBuffer _samples;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroWaveformController] with the given [capacity].
  ZeroWaveformController({this.capacity = 256})
      : _samples = FloatRingBuffer(capacity > 1 ? capacity : 2);

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Number of samples currently stored, or `0` if disposed.
  int get length => _isDisposed ? 0 : _samples.length;

  /// Most recently pushed sample, or `0.0` if empty or disposed.
  double get latest => _isDisposed ? 0.0 : _samples.latest;

  /// Root-mean-square (RMS) level of currently stored samples (`0.0` to `1.0`).
  double get rms {
    if (_isDisposed) return 0.0;
    final int len = _samples.length;
    if (len == 0) return 0.0;
    double sumSq = 0.0;
    for (int i = 0; i < len; i++) {
      final double v = _samples[i];
      sumSq += v * v;
    }
    return math.sqrt(sumSq / len);
  }

  /// Returns the sample at [index] (oldest = `0`), or `0.0` if disposed or out of range.
  double sampleAt(int index) {
    if (_isDisposed) return 0.0;
    if (index < 0 || index >= _samples.length) return 0.0;
    return _samples[index];
  }

  /// Pushes a single audio sample (clamped to `-1.0..1.0`) and notifies listeners.
  void pushSample(double sample) {
    if (_isDisposed) return;
    _samples.push(_clampUnitSigned(sample));
    _revision.add(1);
  }

  /// Pushes a batch of audio samples and notifies listeners once.
  void pushSamples(List<double> samples) {
    if (_isDisposed || samples.isEmpty) return;
    for (int i = 0; i < samples.length; i++) {
      _samples.push(_clampUnitSigned(samples[i]));
    }
    _revision.add(1);
  }

  /// Clears all samples and notifies listeners.
  void clear() {
    if (_isDisposed) return;
    _samples.clear();
    _revision.add(1);
  }

  static double _clampUnitSigned(double value) {
    if (value.isNaN) return 0.0;
    if (value < -1.0) return -1.0;
    if (value > 1.0) return 1.0;
    return value;
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    _revision.removeListener(listener);
  }

  /// Disposes this controller and releases all listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _samples.clear();
    _revision.dispose();
  }
}

/// Active Z-prefixed alias for [ZWaveform].
typedef ZAudioVisualizer = ZWaveform;

/// Legacy deprecated alias for [ZWaveform].
@Deprecated('Use ZWaveform instead.')
typedef ZeroWaveform = ZWaveform;

/// A zero-allocation real-time audio waveform widget that renders directly to the
/// Canvas via `Canvas.drawRawPoints` without widget rebuilds or per-frame heap allocations.
class ZWaveform extends ZLeafWidget<RenderZWaveform> {
  /// Controller supplying real-time audio samples.
  final ZeroWaveformController controller;

  /// Primary stroke color for the waveform.
  final Color waveColor;

  /// Optional center baseline color.
  final Color centerLineColor;

  /// Optional background fill color.
  final Color? backgroundColor;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  /// Visual style ([ZWaveformStyle.polyline] or [ZWaveformStyle.bars]).
  final ZWaveformStyle style;

  /// Whether to render the zero-crossing center line.
  final bool showCenterLine;

  /// Fallback size when unconstrained.
  final Size preferredSize;

  /// Creates a const [ZWaveform].
  const ZWaveform({
    super.key,
    required this.controller,
    this.waveColor = const Color(0xFF00E676),
    this.centerLineColor = const Color(0x44FFFFFF),
    this.backgroundColor,
    this.strokeWidth = 2.0,
    this.style = ZWaveformStyle.polyline,
    this.showCenterLine = true,
    this.preferredSize = const Size(240.0, 80.0),
  });

  @override
  RenderZWaveform createRenderObject(BuildContext context) {
    return RenderZWaveform(
      controller: controller,
      waveColor: waveColor,
      centerLineColor: centerLineColor,
      backgroundColor: backgroundColor,
      strokeWidth: strokeWidth,
      style: style,
      showCenterLine: showCenterLine,
      preferredSize: preferredSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZWaveform renderObject) {
    renderObject
      ..controller = controller
      ..waveColor = waveColor
      ..centerLineColor = centerLineColor
      ..backgroundColor = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = style
      ..showCenterLine = showCenterLine
      ..preferredSize = preferredSize;
  }
}

/// Direct-to-Canvas [ZeroRenderBox] for [ZWaveform].
class RenderZWaveform extends ZeroRenderBox {
  ZeroWaveformController _controller;
  Color _waveColor;
  Color _centerLineColor;
  Color? _backgroundColor;
  double _strokeWidth;
  ZWaveformStyle _style;
  bool _showCenterLine;
  Size _preferredSize;

  final Paint _wavePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  final Paint _centerPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;

  late Float32List _polyPoints;
  late Float32List _barPoints;

  /// Creates a [RenderZWaveform].
  RenderZWaveform({
    required ZeroWaveformController controller,
    required Color waveColor,
    required Color centerLineColor,
    required Color? backgroundColor,
    required double strokeWidth,
    required ZWaveformStyle style,
    required bool showCenterLine,
    required Size preferredSize,
  })  : _controller = controller,
        _waveColor = waveColor,
        _centerLineColor = centerLineColor,
        _backgroundColor = backgroundColor,
        _strokeWidth = strokeWidth,
        _style = style,
        _showCenterLine = showCenterLine,
        _preferredSize = preferredSize {
    _wavePaint
      ..color = waveColor
      ..strokeWidth = strokeWidth;
    _centerPaint.color = centerLineColor;
    if (backgroundColor != null) {
      _bgPaint.color = backgroundColor;
    }
    _allocateBuffers(controller.capacity);
  }

  void _allocateBuffers(int cap) {
    final int safeCap = cap > 1 ? cap : 2;
    _polyPoints = Float32List(safeCap * 2);
    _barPoints = Float32List(safeCap * 4);
  }

  /// Active waveform controller.
  ZeroWaveformController get controller => _controller;
  set controller(ZeroWaveformController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    if (_polyPoints.length < value.capacity * 2) {
      _allocateBuffers(value.capacity);
    }
    if (attached) {
      _controller.addListener(markDirty);
    }
    markDirty();
  }

  /// Waveform stroke color.
  Color get waveColor => _waveColor;
  set waveColor(Color value) {
    if (_waveColor == value) return;
    _waveColor = value;
    _wavePaint.color = value;
    markDirty();
  }

  /// Center line color.
  Color get centerLineColor => _centerLineColor;
  set centerLineColor(Color value) {
    if (_centerLineColor == value) return;
    _centerLineColor = value;
    _centerPaint.color = value;
    markDirty();
  }

  /// Optional background color.
  Color? get backgroundColor => _backgroundColor;
  set backgroundColor(Color? value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    if (value != null) {
      _bgPaint.color = value;
    }
    markDirty();
  }

  /// Stroke width in logical pixels.
  double get strokeWidth => _strokeWidth;
  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    _wavePaint.strokeWidth = value;
    markDirty();
  }

  /// Waveform rendering style.
  ZWaveformStyle get style => _style;
  set style(ZWaveformStyle value) {
    if (_style == value) return;
    _style = value;
    markDirty();
  }

  /// Whether to render the center line.
  bool get showCenterLine => _showCenterLine;
  set showCenterLine(bool value) {
    if (_showCenterLine == value) return;
    _showCenterLine = value;
    markDirty();
  }

  /// Fallback size when unconstrained.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
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
  void performLayout() {
    size = constraints.constrain(_preferredSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double w = size.width;
    final double h = size.height;
    if (w <= 0.0 || h <= 0.0) return;

    if (_backgroundColor != null) {
      canvas.drawRect(offset & size, _bgPaint);
    }

    final double midY = offset.dy + h * 0.5;
    if (_showCenterLine) {
      canvas.drawLine(
        Offset(offset.dx, midY),
        Offset(offset.dx + w, midY),
        _centerPaint,
      );
    }

    if (_controller.isDisposed || _controller.length == 0) return;
    if (_style == ZWaveformStyle.bars) {
      _paintBars(canvas, offset.dx, midY, w, h * 0.48);
    } else {
      _paintPolyline(canvas, offset.dx, midY, w, h * 0.48);
    }
  }

  void _paintPolyline(
    Canvas canvas,
    double left,
    double midY,
    double width,
    double halfAmp,
  ) {
    final int cap = _controller.capacity;
    final int len = _controller.length;
    final double stepX = cap > 1 ? width / (cap - 1) : width;
    double lastX = left;
    double lastY = midY;

    for (int i = 0; i < cap; i++) {
      final int b = i << 1;
      if (i < len) {
        lastX = left + i * stepX;
        lastY = midY - _controller.sampleAt(i) * halfAmp;
      }
      _polyPoints[b] = lastX;
      _polyPoints[b + 1] = lastY;
    }
    canvas.drawRawPoints(ui.PointMode.polygon, _polyPoints, _wavePaint);
  }

  void _paintBars(
    Canvas canvas,
    double left,
    double midY,
    double width,
    double halfAmp,
  ) {
    final int cap = _controller.capacity;
    final int len = _controller.length;
    final double stepX = cap > 1 ? width / (cap - 1) : width;

    for (int i = 0; i < cap; i++) {
      final int b = i << 2;
      final double x = left + i * stepX;
      final double amp = i < len ? (_controller.sampleAt(i).abs() * halfAmp) : 0.0;
      _barPoints[b] = x;
      _barPoints[b + 1] = midY - amp;
      _barPoints[b + 2] = x;
      _barPoints[b + 3] = midY + amp;
    }
    canvas.drawRawPoints(ui.PointMode.lines, _barPoints, _wavePaint);
  }
}

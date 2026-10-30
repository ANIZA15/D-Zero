import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';

/// Zero-allocation controller for stereo or mono VU / peak audio meters.
class ZeroAudioMeterController implements Listenable {
  double _leftRms = 0.0;
  double _rightRms = 0.0;
  double _leftPeak = 0.0;
  double _rightPeak = 0.0;
  bool _isClipping = false;
  bool _isDisposed = false;

  final double peakDecayPerUpdate;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  /// Creates a [ZeroAudioMeterController].
  ZeroAudioMeterController({
    this.peakDecayPerUpdate = 0.02,
  });

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Left channel normalized RMS level (`0.0..1.0`), or `0.0` if disposed.
  double get leftRms => _isDisposed ? 0.0 : _leftRms;

  /// Right channel normalized RMS level (`0.0..1.0`), or `0.0` if disposed.
  double get rightRms => _isDisposed ? 0.0 : _rightRms;

  /// Left channel normalized peak-hold level (`0.0..1.0`), or `0.0` if disposed.
  double get leftPeak => _isDisposed ? 0.0 : _leftPeak;

  /// Right channel normalized peak-hold level (`0.0..1.0`), or `0.0` if disposed.
  double get rightPeak => _isDisposed ? 0.0 : _rightPeak;

  /// Whether either channel has reached or exceeded the clipping threshold (`>= 0.99`).
  bool get isClipping => !_isDisposed && _isClipping;

  /// Returns the current peak level in decibels Full Scale (`-60.0` to `0.0` dBFS).
  double get peakDb {
    if (_isDisposed) return -60.0;
    final double maxPeak = _leftPeak >= _rightPeak ? _leftPeak : _rightPeak;
    if (maxPeak <= 0.001) return -60.0;
    final double db = 20.0 * (math.log(maxPeak) / math.ln10);
    return db < -60.0 ? -60.0 : (db > 0.0 ? 0.0 : db);
  }

  /// Updates channel RMS and optional instantaneous peak levels (`0.0..1.0`).
  void updateLevels({
    required double leftRms,
    double? rightRms,
    double? leftPeak,
    double? rightPeak,
  }) {
    if (_isDisposed) return;
    final double lRms = _clampUnit(leftRms);
    final double rRms = _clampUnit(rightRms ?? leftRms);
    final double lInPeak = _clampUnit(leftPeak ?? lRms);
    final double rInPeak = _clampUnit(rightPeak ?? rRms);

    _leftRms = lRms;
    _rightRms = rRms;
    _leftPeak = _decayAndHold(_leftPeak, lInPeak);
    _rightPeak = _decayAndHold(_rightPeak, rInPeak);
    if (lInPeak >= 0.99 || rInPeak >= 0.99) {
      _isClipping = true;
    }
    _revision.add(1);
  }

  double _decayAndHold(double prevPeak, double currentPeak) {
    final double decayed = prevPeak - peakDecayPerUpdate;
    final double floorPeak = decayed > 0.0 ? decayed : 0.0;
    return currentPeak >= floorPeak ? currentPeak : floorPeak;
  }

  /// Clears the clip-hold indicator flag.
  void resetClip() {
    if (_isDisposed || !_isClipping) return;
    _isClipping = false;
    _revision.add(1);
  }

  /// Resets all RMS, peak, and clip indicators to zero.
  void clear() {
    if (_isDisposed) return;
    _leftRms = 0.0;
    _rightRms = 0.0;
    _leftPeak = 0.0;
    _rightPeak = 0.0;
    _isClipping = false;
    _revision.add(1);
  }

  static double _clampUnit(double value) {
    if (value.isNaN || value <= 0.0) return 0.0;
    if (value >= 1.0) return 1.0;
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
    _leftRms = 0.0;
    _rightRms = 0.0;
    _leftPeak = 0.0;
    _rightPeak = 0.0;
    _isClipping = false;
    _revision.dispose();
  }
}

/// Active Z-prefixed alias for [ZAudioMeter].
typedef ZVUMeter = ZAudioMeter;

/// Legacy deprecated alias for [ZAudioMeter].
@Deprecated('Use ZAudioMeter instead.')
typedef ZeroAudioMeter = ZAudioMeter;

/// A zero-allocation stereo/mono VU & peak audio meter widget with green/yellow/red
/// zone segments, peak-hold markers, clip indicator, and zero-allocation dB readout
/// via [ZeroNumberPainter].
class ZAudioMeter extends ZLeafWidget<RenderZAudioMeter> {
  /// Controller providing stereo/mono RMS, peak, and clip state.
  final ZeroAudioMeterController controller;

  /// Whether to render stereo (2 bars) or mono (1 bar).
  final bool stereo;

  /// Whether to render the numeric dBFS readout using [ZeroNumberPainter].
  final bool showDbReadout;

  /// Text style for the dBFS readout.
  final TextStyle labelStyle;

  /// Color for safe levels (`0.0..0.70`).
  final Color greenZoneColor;

  /// Color for warning levels (`0.70..0.90`).
  final Color yellowZoneColor;

  /// Color for hot/clip levels (`0.90..1.0`).
  final Color redZoneColor;

  /// Fallback size when unconstrained.
  final Size preferredSize;

  /// Creates a const [ZAudioMeter].
  const ZAudioMeter({
    super.key,
    required this.controller,
    this.stereo = true,
    this.showDbReadout = true,
    this.labelStyle = const TextStyle(
      color: Color(0xFFE0E0E0),
      fontSize: 11.0,
      fontFamily: 'monospace',
    ),
    this.greenZoneColor = const Color(0xFF00E676),
    this.yellowZoneColor = const Color(0xFFFFEA00),
    this.redZoneColor = const Color(0xFFFF1744),
    this.preferredSize = const Size(240.0, 44.0),
  });

  @override
  RenderZAudioMeter createRenderObject(BuildContext context) {
    return RenderZAudioMeter(
      controller: controller,
      stereo: stereo,
      showDbReadout: showDbReadout,
      labelStyle: labelStyle,
      greenZoneColor: greenZoneColor,
      yellowZoneColor: yellowZoneColor,
      redZoneColor: redZoneColor,
      preferredSize: preferredSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZAudioMeter renderObject) {
    renderObject
      ..controller = controller
      ..stereo = stereo
      ..showDbReadout = showDbReadout
      ..labelStyle = labelStyle
      ..greenZoneColor = greenZoneColor
      ..yellowZoneColor = yellowZoneColor
      ..redZoneColor = redZoneColor
      ..preferredSize = preferredSize;
  }
}

/// Direct-to-Canvas [ZeroRenderBox] for [ZAudioMeter].
class RenderZAudioMeter extends ZeroRenderBox {
  ZeroAudioMeterController _controller;
  bool _stereo;
  bool _showDbReadout;
  TextStyle _labelStyle;
  Color _greenZoneColor;
  Color _yellowZoneColor;
  Color _redZoneColor;
  Size _preferredSize;

  final Paint _trackPaint = Paint()
    ..color = const Color(0xFF1E1E24)
    ..style = PaintingStyle.fill;
  final Paint _greenPaint = Paint()..style = PaintingStyle.fill;
  final Paint _yellowPaint = Paint()..style = PaintingStyle.fill;
  final Paint _redPaint = Paint()..style = PaintingStyle.fill;
  final Paint _peakPaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  ZeroNumberPainter? _numberPainter;

  /// Creates a [RenderZAudioMeter].
  RenderZAudioMeter({
    required ZeroAudioMeterController controller,
    required bool stereo,
    required bool showDbReadout,
    required TextStyle labelStyle,
    required Color greenZoneColor,
    required Color yellowZoneColor,
    required Color redZoneColor,
    required Size preferredSize,
  })  : _controller = controller,
        _stereo = stereo,
        _showDbReadout = showDbReadout,
        _labelStyle = labelStyle,
        _greenZoneColor = greenZoneColor,
        _yellowZoneColor = yellowZoneColor,
        _redZoneColor = redZoneColor,
        _preferredSize = preferredSize {
    _greenPaint.color = greenZoneColor;
    _yellowPaint.color = yellowZoneColor;
    _redPaint.color = redZoneColor;
    _numberPainter = ZeroNumberPainter(style: labelStyle);
  }

  /// Active audio meter controller.
  ZeroAudioMeterController get controller => _controller;
  set controller(ZeroAudioMeterController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    if (attached) {
      _controller.addListener(markDirty);
    }
    markDirty();
  }

  /// Whether stereo mode is enabled.
  bool get stereo => _stereo;
  set stereo(bool value) {
    if (_stereo == value) return;
    _stereo = value;
    markDirty();
  }

  /// Whether numeric dB readout is rendered.
  bool get showDbReadout => _showDbReadout;
  set showDbReadout(bool value) {
    if (_showDbReadout == value) return;
    _showDbReadout = value;
    markDirty();
  }

  /// Text style for the dB readout.
  TextStyle get labelStyle => _labelStyle;
  set labelStyle(TextStyle value) {
    if (_labelStyle == value) return;
    _labelStyle = value;
    _numberPainter?.dispose();
    _numberPainter = ZeroNumberPainter(style: value);
    markDirty();
  }

  /// Green zone color.
  Color get greenZoneColor => _greenZoneColor;
  set greenZoneColor(Color value) {
    if (_greenZoneColor == value) return;
    _greenZoneColor = value;
    _greenPaint.color = value;
    markDirty();
  }

  /// Yellow zone color.
  Color get yellowZoneColor => _yellowZoneColor;
  set yellowZoneColor(Color value) {
    if (_yellowZoneColor == value) return;
    _yellowZoneColor = value;
    _yellowPaint.color = value;
    markDirty();
  }

  /// Red zone color.
  Color get redZoneColor => _redZoneColor;
  set redZoneColor(Color value) {
    if (_redZoneColor == value) return;
    _redZoneColor = value;
    _redPaint.color = value;
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
    _numberPainter ??= ZeroNumberPainter(style: _labelStyle);
  }

  @override
  void detach() {
    _controller.removeListener(markDirty);
    super.detach();
  }

  @override
  void dispose() {
    _numberPainter?.dispose();
    _numberPainter = null;
    super.dispose();
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

    final double readoutReserve = _showDbReadout ? 52.0 : 0.0;
    const double clipLedW = 10.0;
    final double meterW = (w - readoutReserve - clipLedW - 8.0).clamp(10.0, w);

    if (_stereo) {
      final double barH = (h - 4.0) * 0.5;
      _paintChannelBar(canvas, offset.dx, offset.dy, meterW, barH, _controller.leftRms, _controller.leftPeak);
      _paintChannelBar(canvas, offset.dx, offset.dy + barH + 4.0, meterW, barH, _controller.rightRms, _controller.rightPeak);
    } else {
      _paintChannelBar(canvas, offset.dx, offset.dy, meterW, h, _controller.leftRms, _controller.leftPeak);
    }

    _paintClipAndReadout(canvas, offset.dx + meterW + 4.0, offset.dy, h, clipLedW);
  }

  void _paintChannelBar(
    Canvas canvas,
    double left,
    double top,
    double width,
    double height,
    double rms,
    double peak,
  ) {
    canvas.drawRect(Rect.fromLTWH(left, top, width, height), _trackPaint);
    final double greenEnd = rms < 0.70 ? rms : 0.70;
    if (greenEnd > 0.0) {
      canvas.drawRect(Rect.fromLTWH(left, top, width * greenEnd, height), _greenPaint);
    }
    if (rms > 0.70) {
      final double yellowSpan = (rms < 0.90 ? rms : 0.90) - 0.70;
      canvas.drawRect(Rect.fromLTWH(left + width * 0.70, top, width * yellowSpan, height), _yellowPaint);
    }
    if (rms > 0.90) {
      final double redSpan = (rms < 1.0 ? rms : 1.0) - 0.90;
      canvas.drawRect(Rect.fromLTWH(left + width * 0.90, top, width * redSpan, height), _redPaint);
    }
    final double peakX = left + (width * peak).clamp(1.0, width - 1.0);
    canvas.drawLine(Offset(peakX, top), Offset(peakX, top + height), _peakPaint);
  }

  void _paintClipAndReadout(
    Canvas canvas,
    double startX,
    double top,
    double height,
    double clipW,
  ) {
    final Paint clipPaint = _controller.isClipping ? _redPaint : _trackPaint;
    canvas.drawRect(Rect.fromLTWH(startX, top, clipW, height), clipPaint);
    if (!_showDbReadout) return;
    final ZeroNumberPainter? np = _numberPainter;
    if (np == null) return;
    final double textY = top + (height - np.height) * 0.5;
    np.paintDouble(
      canvas,
      Offset(startX + clipW + 4.0, textY),
      _controller.peakDb,
      fractionDigits: 1,
    );
  }
}

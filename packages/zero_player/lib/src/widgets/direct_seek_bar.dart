import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' show PointMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';
import '../controller.dart';
import '../playback_state_ffi.dart';

/// A high-performance seek bar [ZLeafWidget] that paints directly to the
/// Canvas at 120fps by reading current playback position directly from atomic shared memory.
class ZDirectSeekBar extends ZLeafWidget<RenderDirectSeekBar> {
  /// The [ZeroPlayerController] managing the playback session.
  final ZeroPlayerController controller;

  /// The active track color representing elapsed playback time.
  final Color activeTrackColor;

  /// The background track color representing total duration.
  final Color inactiveTrackColor;

  /// The scrubber thumb color.
  final Color thumbColor;

  /// The height of the progress track.
  final double trackHeight;

  /// The radius of the scrubber thumb.
  final double thumbRadius;

  /// Optional callback invoked when the user drags or taps to seek.
  final ValueChanged<Duration>? onSeek;

  /// Creates a zero-rebuild [ZDirectSeekBar].
  const ZDirectSeekBar({
    super.key,
    required this.controller,
    this.activeTrackColor = const Color(0xFFFF0055),
    this.inactiveTrackColor = const Color(0x55FFFFFF),
    this.thumbColor = const Color(0xFFFFFFFF),
    this.trackHeight = 4.0,
    this.thumbRadius = 6.0,
    this.onSeek,
  });

  @override
  RenderDirectSeekBar createRenderObject(BuildContext context) {
    return RenderDirectSeekBar(
      statePointer: controller.statePointer,
      activeTrackColor: activeTrackColor,
      inactiveTrackColor: inactiveTrackColor,
      thumbColor: thumbColor,
      trackHeight: trackHeight,
      thumbRadius: thumbRadius,
      onSeek: onSeek,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderDirectSeekBar renderObject) {
    renderObject
      ..statePointer = controller.statePointer
      ..activeTrackColor = activeTrackColor
      ..inactiveTrackColor = inactiveTrackColor
      ..thumbColor = thumbColor
      ..trackHeight = trackHeight
      ..thumbRadius = thumbRadius
      ..onSeek = onSeek;
  }
}

/// Backward compatibility alias for [ZDirectSeekBar].
@Deprecated('Use ZDirectSeekBar instead.')
typedef DirectSeekBar = ZDirectSeekBar;

/// Shorthand alias for [ZDirectSeekBar].
typedef ZSeekBar = ZDirectSeekBar;

class RenderDirectSeekBar extends ZeroRenderBox {
  ffi.Pointer<ZeroPlaybackStateNative> _statePointer;
  ZeroPlaybackStateView _view;
  Color _activeTrackColor;
  Color _inactiveTrackColor;
  Color _thumbColor;
  double _trackHeight;
  double _thumbRadius;
  ValueChanged<Duration>? onSeek;

  // Pre-allocated Paints and raw coordinate buffers reused across every frame
  // (zero Offset / Paint allocations in paintZero)
  final Paint _bgPaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _activePaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _thumbPaint = Paint()..strokeCap = StrokeCap.round;
  final Float32List _bgLineCoords = Float32List(4);
  final Float32List _activeLineCoords = Float32List(4);
  final Float32List _thumbCoord = Float32List(2);

  late final HorizontalDragGestureRecognizer _dragRecognizer;
  late final TapGestureRecognizer _tapRecognizer;

  int _lastQuantizedStep = -1;
  int _lastDurationMs = -1;

  RenderDirectSeekBar({
    required ffi.Pointer<ZeroPlaybackStateNative> statePointer,
    required Color activeTrackColor,
    required Color inactiveTrackColor,
    required Color thumbColor,
    required double trackHeight,
    required double thumbRadius,
    this.onSeek,
  })  : _statePointer = statePointer,
        _view = ZeroPlaybackStateView(statePointer),
        _activeTrackColor = activeTrackColor,
        _inactiveTrackColor = inactiveTrackColor,
        _thumbColor = thumbColor,
        _trackHeight = trackHeight,
        _thumbRadius = thumbRadius,
        super(animatePerFrame: true) {
    _bgPaint
      ..color = _inactiveTrackColor
      ..strokeWidth = _trackHeight;
    _activePaint
      ..color = _activeTrackColor
      ..strokeWidth = _trackHeight;
    _thumbPaint
      ..color = _thumbColor
      ..strokeWidth = _thumbRadius * 2.0;

    _dragRecognizer = HorizontalDragGestureRecognizer()
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd;

    _tapRecognizer = TapGestureRecognizer()..onTapDown = _handleTapDown;
  }

  set statePointer(ffi.Pointer<ZeroPlaybackStateNative> val) {
    if (_statePointer == val) return;
    _statePointer = val;
    _view = ZeroPlaybackStateView(val);
    _lastQuantizedStep = -1;
    _lastDurationMs = -1;
    markDirty();
  }

  set activeTrackColor(Color val) {
    if (_activeTrackColor == val) return;
    _activeTrackColor = val;
    _activePaint.color = val;
    markDirty();
  }

  set inactiveTrackColor(Color val) {
    if (_inactiveTrackColor == val) return;
    _inactiveTrackColor = val;
    _bgPaint.color = val;
    markDirty();
  }

  set thumbColor(Color val) {
    if (_thumbColor == val) return;
    _thumbColor = val;
    _thumbPaint.color = val;
    markDirty();
  }

  set trackHeight(double val) {
    if (_trackHeight == val) return;
    _trackHeight = val;
    _bgPaint.strokeWidth = val;
    _activePaint.strokeWidth = val;
    markNeedsLayout();
  }

  set thumbRadius(double val) {
    if (_thumbRadius == val) return;
    _thumbRadius = val;
    _thumbPaint.strokeWidth = val * 2.0;
    markNeedsLayout();
  }

  int _quantizePositionStep(int posMs, int durMs) {
    if (!hasSize || durMs <= 0) return posMs;
    final double w = size.width;
    if (w <= 0.0) return posMs;
    return (posMs * w * 4.0) ~/ durMs;
  }

  @override
  bool onFrameTick(Duration elapsed) {
    final int posMs = _view.displayPositionMs;
    final int durMs = _view.durationMs;
    final int step = _quantizePositionStep(posMs, durMs);
    if (step == _lastQuantizedStep && durMs == _lastDurationMs) {
      return false;
    }
    _lastQuantizedStep = step;
    _lastDurationMs = durMs;
    return true;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _dragRecognizer.addPointer(event);
      _tapRecognizer.addPointer(event);
    }
  }

  void _handleTapDown(TapDownDetails details) {
    _seekByLocalOffset(details.localPosition.dx);
  }

  void _handleDragStart(DragStartDetails details) {
    _seekByLocalOffset(details.localPosition.dx);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _seekByLocalOffset(details.localPosition.dx);
  }

  void _handleDragEnd(DragEndDetails details) {}

  void _seekByLocalOffset(double dx) {
    final int dur = _view.durationMs;
    final double w = size.width;
    if (dur <= 0 || w <= 0.0) return;
    double ratio = dx / w;
    if (ratio < 0.0) ratio = 0.0;
    if (ratio > 1.0) ratio = 1.0;
    final int targetMs = (ratio * dur).toInt();
    onSeek?.call(Duration(milliseconds: targetMs));
  }

  @override
  void performLayout() {
    final double thumbDiameter = _thumbRadius * 2.0;
    double desiredHeight = thumbDiameter < _trackHeight ? _trackHeight : thumbDiameter;
    if (desiredHeight > 48.0) desiredHeight = 48.0;
    size = constraints.constrain(
      Size(constraints.maxWidth, desiredHeight),
    );
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double width = size.width;
    final double height = size.height;

    final int positionMs = _view.displayPositionMs;
    final int durationMs = _view.durationMs;
    _lastQuantizedStep = _quantizePositionStep(positionMs, durationMs);
    _lastDurationMs = durationMs;

    double progress = 0.0;
    if (durationMs > 0) {
      progress = positionMs / durationMs;
      if (progress < 0.0) progress = 0.0;
      if (progress > 1.0) progress = 1.0;
    }

    final double centerY = offset.dy + height * 0.5;
    final double trackLeft = offset.dx;
    final double trackRight = offset.dx + width;
    final double activeRight = trackLeft + width * progress;

    _bgLineCoords[0] = trackLeft;
    _bgLineCoords[1] = centerY;
    _bgLineCoords[2] = trackRight;
    _bgLineCoords[3] = centerY;
    canvas.drawRawPoints(PointMode.lines, _bgLineCoords, _bgPaint);

    if (progress > 0.0) {
      _activeLineCoords[0] = trackLeft;
      _activeLineCoords[1] = centerY;
      _activeLineCoords[2] = activeRight;
      _activeLineCoords[3] = centerY;
      canvas.drawRawPoints(PointMode.lines, _activeLineCoords, _activePaint);
    }

    _thumbCoord[0] = activeRight;
    _thumbCoord[1] = centerY;
    canvas.drawRawPoints(PointMode.points, _thumbCoord, _thumbPaint);
  }

  @override
  void dispose() {
    _dragRecognizer.dispose();
    _tapRecognizer.dispose();
    super.dispose();
  }
}

import 'dart:ffi' as ffi;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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

class RenderDirectSeekBar extends RenderBox {
  ffi.Pointer<ZeroPlaybackStateNative> _statePointer;
  Color _activeTrackColor;
  Color _inactiveTrackColor;
  Color _thumbColor;
  double _trackHeight;
  double _thumbRadius;
  ValueChanged<Duration>? onSeek;

  late final HorizontalDragGestureRecognizer _dragRecognizer;
  late final TapGestureRecognizer _tapRecognizer;
  Ticker? _ticker;

  RenderDirectSeekBar({
    required ffi.Pointer<ZeroPlaybackStateNative> statePointer,
    required Color activeTrackColor,
    required Color inactiveTrackColor,
    required Color thumbColor,
    required double trackHeight,
    required double thumbRadius,
    this.onSeek,
  })  : _statePointer = statePointer,
        _activeTrackColor = activeTrackColor,
        _inactiveTrackColor = inactiveTrackColor,
        _thumbColor = thumbColor,
        _trackHeight = trackHeight,
        _thumbRadius = thumbRadius {
    _dragRecognizer = HorizontalDragGestureRecognizer()
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd;

    _tapRecognizer = TapGestureRecognizer()..onTapDown = _handleTapDown;
  }

  set statePointer(ffi.Pointer<ZeroPlaybackStateNative> val) {
    if (_statePointer == val) return;
    _statePointer = val;
    markNeedsPaint();
  }

  set activeTrackColor(Color val) {
    if (_activeTrackColor == val) return;
    _activeTrackColor = val;
    markNeedsPaint();
  }

  set inactiveTrackColor(Color val) {
    if (_inactiveTrackColor == val) return;
    _inactiveTrackColor = val;
    markNeedsPaint();
  }

  set thumbColor(Color val) {
    if (_thumbColor == val) return;
    _thumbColor = val;
    markNeedsPaint();
  }

  set trackHeight(double val) {
    if (_trackHeight == val) return;
    _trackHeight = val;
    markNeedsLayout();
  }

  set thumbRadius(double val) {
    if (_thumbRadius == val) return;
    _thumbRadius = val;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // 描画フレームごとに markNeedsPaint() のみを直接叩く
    // 【重要】Widgetの再構築（build）や Layout は一切発生しない！
    _ticker = Ticker((_) {
      if (attached) {
        markNeedsPaint();
      }
    })
      ..start();
  }

  @override
  void detach() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true; // 独立したレイヤーとして分離し、周囲の再描画を完全に遮断

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
    final dur = _statePointer.ref.durationMs;
    if (dur <= 0 || size.width <= 0) return;
    final ratio = (dx / size.width).clamp(0.0, 1.0);
    final targetMs = (ratio * dur).toInt();
    onSeek?.call(Duration(milliseconds: targetMs));
  }

  @override
  void performLayout() {
    final desiredHeight = (_thumbRadius * 2).clamp(_trackHeight, 48.0);
    size = constraints.constrain(
      Size(constraints.maxWidth, desiredHeight),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final width = size.width;
    final height = size.height;

    // FFI 共有メモリから 0 ナノ秒で最新の再生位置を取得
    final positionMs = _statePointer.ref.positionMs;
    final durationMs = _statePointer.ref.durationMs;
    final progress =
        durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

    final centerY = offset.dy + height / 2;
    final trackLeft = offset.dx;
    final trackRight = offset.dx + width;
    final activeRight = trackLeft + width * progress;

    // 非アクティブトラック（背景）
    final bgPaint = Paint()
      ..color = _inactiveTrackColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _trackHeight;
    canvas.drawLine(
        Offset(trackLeft, centerY), Offset(trackRight, centerY), bgPaint);

    // アクティブトラック（進捗）
    if (progress > 0) {
      final activePaint = Paint()
        ..color = _activeTrackColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _trackHeight;
      canvas.drawLine(Offset(trackLeft, centerY), Offset(activeRight, centerY),
          activePaint);
    }

    // つまみ（Thumb）
    final thumbPaint = Paint()..color = _thumbColor;
    canvas.drawCircle(Offset(activeRight, centerY), _thumbRadius, thumbPaint);
  }

  @override
  void dispose() {
    _dragRecognizer.dispose();
    _tapRecognizer.dispose();
    super.dispose();
  }
}

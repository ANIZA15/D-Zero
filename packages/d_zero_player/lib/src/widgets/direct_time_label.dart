import 'dart:ffi' as ffi;
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';
import '../playback_state_ffi.dart';

/// A timecode display [LeafRenderObjectWidget] that paints elapsed/total time directly
/// on the Canvas with zero widget rebuilds and zero String allocations.
class ZDirectTimeLabel extends ZLeafWidget<RenderDirectTimeLabel> {
  /// The [ZeroPlayerController] managing the playback session.
  final ZeroPlayerController controller;

  /// The text style applied to the timecode label.
  final TextStyle style;

  /// Creates a zero-rebuild [ZDirectTimeLabel].
  const ZDirectTimeLabel({
    super.key,
    required this.controller,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 12.0,
      fontFamily: 'monospace',
    ),
  });

  @override
  RenderDirectTimeLabel createRenderObject(BuildContext context) {
    return RenderDirectTimeLabel(
      controller: controller,
      statePointer: controller.statePointer,
      style: style,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderDirectTimeLabel renderObject) {
    renderObject
      ..controller = controller
      ..statePointer = controller.statePointer
      ..style = style;
  }
}

/// Backward compatibility alias for [ZDirectTimeLabel].
@Deprecated('Use ZDirectTimeLabel instead.')
typedef DirectTimeLabel = ZDirectTimeLabel;

/// Shorthand alias for [ZDirectTimeLabel].
typedef ZTimeLabel = ZDirectTimeLabel;

class RenderDirectTimeLabel extends ZeroRenderBox {
  ZeroPlayerController? _controller;
  ffi.Pointer<ZeroPlaybackStateNative> _statePointer;
  ZeroPlaybackStateView _view;
  TextStyle _style;
  late ZeroNumberPainter _numberPainter;
  int _lastSec = -1;
  int _lastDurSec = -1;

  RenderDirectTimeLabel({
    ZeroPlayerController? controller,
    required ffi.Pointer<ZeroPlaybackStateNative> statePointer,
    required TextStyle style,
  })  : _controller = controller,
        _statePointer = statePointer,
        _view = ZeroPlaybackStateView(statePointer),
        _style = style,
        super(animatePerFrame: true) {
    _numberPainter = ZeroNumberPainter(style: _style);
  }

  set controller(ZeroPlayerController? val) {
    if (identical(_controller, val)) return;
    _controller = val;
    _lastSec = -1;
    _lastDurSec = -1;
    markDirty();
  }

  set statePointer(ffi.Pointer<ZeroPlaybackStateNative> val) {
    if (_statePointer == val) return;
    _statePointer = val;
    _view = ZeroPlaybackStateView(val);
    _lastSec = -1;
    _lastDurSec = -1;
    markDirty();
  }

  @pragma('vm:prefer-inline')
  bool get _canReadState {
    final ZeroPlayerController? ctrl = _controller;
    if (ctrl != null && ctrl.isDisposed) return false;
    return _view.isValid;
  }

  @pragma('vm:prefer-inline')
  int get _safePositionMs => _canReadState ? _view.displayPositionMs : 0;

  @pragma('vm:prefer-inline')
  int get _safeDurationMs => _canReadState ? _view.durationMs : 0;

  set style(TextStyle val) {
    if (_style == val) return;
    _style = val;
    _numberPainter.dispose();
    _numberPainter = ZeroNumberPainter(style: _style);
    markNeedsLayout();
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_canReadState) return false;
    final int posSec = _safePositionMs ~/ 1000;
    final int durSec = _safeDurationMs ~/ 1000;
    if (posSec == _lastSec && durSec == _lastDurSec) {
      return false;
    }
    _lastSec = posSec;
    _lastDurSec = durSec;
    return true;
  }

  @override
  void performLayout() {
    // 最大幅でサイズを計算・固定（レイアウトの揺れを防止）
    final double width = _numberPainter.estimateTimeProgressWidth();
    final double height = _numberPainter.height;
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final int posMs = _safePositionMs;
    final int durMs = _safeDurationMs;
    _lastSec = posMs ~/ 1000;
    _lastDurSec = durMs ~/ 1000;

    // ゼロStringアロケーション & 単一 drawRawAtlas コールで Canvas に直接描画
    _numberPainter.paintTimeProgress(
      context.canvas,
      offset,
      posMs > 0 ? posMs : 0,
      durMs > 0 ? durMs : 0,
    );
  }

  @override
  void dispose() {
    _numberPainter.dispose();
    super.dispose();
  }
}

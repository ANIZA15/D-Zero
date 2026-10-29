import 'dart:ffi' as ffi;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:zero_core/zero_core.dart';
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
      statePointer: controller.statePointer,
      style: style,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderDirectTimeLabel renderObject) {
    renderObject
      ..statePointer = controller.statePointer
      ..style = style;
  }
}

/// Backward compatibility alias for [ZDirectTimeLabel].
@Deprecated('Use ZDirectTimeLabel instead.')
typedef DirectTimeLabel = ZDirectTimeLabel;

/// Shorthand alias for [ZDirectTimeLabel].
typedef ZTimeLabel = ZDirectTimeLabel;

class RenderDirectTimeLabel extends RenderBox {
  ffi.Pointer<ZeroPlaybackStateNative> _statePointer;
  TextStyle _style;
  late ZeroNumberPainter _numberPainter;
  Ticker? _ticker;
  int _lastSec = -1;

  RenderDirectTimeLabel({
    required ffi.Pointer<ZeroPlaybackStateNative> statePointer,
    required TextStyle style,
  })  : _statePointer = statePointer,
        _style = style {
    _numberPainter = ZeroNumberPainter(style: _style);
  }

  set statePointer(ffi.Pointer<ZeroPlaybackStateNative> val) {
    if (_statePointer == val) return;
    _statePointer = val;
    markNeedsPaint();
  }

  set style(TextStyle val) {
    if (_style == val) return;
    _style = val;
    _numberPainter.dispose();
    _numberPainter = ZeroNumberPainter(style: _style);
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ticker = Ticker((_) {
      if (attached) {
        // 秒数が変わったときのみ再描画をリクエストして、さらなる省電力を実現
        final posSec = _statePointer.ref.positionMs ~/ 1000;
        if (posSec != _lastSec) {
          _lastSec = posSec;
          markNeedsPaint();
        }
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
  bool get isRepaintBoundary => true;

  @override
  void performLayout() {
    // 最大幅でサイズを計算・固定（レイアウトの揺れを防止）
    final width = _numberPainter.estimateTimeProgressWidth();
    final height = _numberPainter.height;
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final posMs = _statePointer.ref.positionMs;
    final durMs = _statePointer.ref.durationMs;

    // ゼロStringアロケーションで Canvas に直接描画
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

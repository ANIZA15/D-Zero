import 'dart:ffi' as ffi;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../controller.dart';
import '../playback_state_ffi.dart';

/// A timecode display [LeafRenderObjectWidget] that paints elapsed/total time directly
/// on the Canvas without triggering widget rebuilds.
class DirectTimeLabel extends LeafRenderObjectWidget {
  /// The [ZeroPlayerController] managing the playback session.
  final ZeroPlayerController controller;

  /// The text style applied to the timecode label.
  final TextStyle style;

  /// Creates a zero-rebuild [DirectTimeLabel].
  const DirectTimeLabel({
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

class RenderDirectTimeLabel extends RenderBox {
  ffi.Pointer<ZeroPlaybackStateNative> _statePointer;
  TextStyle _style;
  final TextPainter _textPainter =
      TextPainter(textDirection: TextDirection.ltr);
  Ticker? _ticker;
  int _lastSec = -1;

  RenderDirectTimeLabel({
    required ffi.Pointer<ZeroPlaybackStateNative> statePointer,
    required TextStyle style,
  })  : _statePointer = statePointer,
        _style = style;

  set statePointer(ffi.Pointer<ZeroPlaybackStateNative> val) {
    if (_statePointer == val) return;
    _statePointer = val;
    markNeedsPaint();
  }

  set style(TextStyle val) {
    if (_style == val) return;
    _style = val;
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

  String _formatDuration(int ms) {
    final totalSec = (ms / 1000).floor();
    final minutes = (totalSec ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSec % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void performLayout() {
    // 最大幅の文字列でサイズを固定（レイアウトの揺れを防止）
    _textPainter.text = TextSpan(text: '99:59 / 99:59', style: _style);
    _textPainter.layout();
    size = constraints.constrain(_textPainter.size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final posMs = _statePointer.ref.positionMs;
    final durMs = _statePointer.ref.durationMs;

    final text = '${_formatDuration(posMs)} / ${_formatDuration(durMs)}';
    _textPainter.text = TextSpan(text: text, style: _style);
    _textPainter.layout();

    _textPainter.paint(context.canvas, offset);
  }

  @override
  void dispose() {
    _textPainter.dispose();
    super.dispose();
  }
}

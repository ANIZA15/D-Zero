import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Base RenderBox class for zero-allocation, direct-to-Canvas rendering.
/// 
/// Enforces:
/// 1. [isRepaintBoundary] = true to isolate repaint operations from the ancestor widget tree.
/// 2. Optional frame-synchronized rendering via a ticker with dirty state tracking.
/// 3. Memory reuse: prevents recreating painters, paths, or text objects per frame.
abstract class ZeroRenderBox extends RenderBox {
  Ticker? _ticker;
  bool _isDirty = true;
  bool _animatePerFrame;

  /// Creates a [ZeroRenderBox].
  /// If [animatePerFrame] is true, a frame ticker is created when attached.
  ZeroRenderBox({bool animatePerFrame = false}) : _animatePerFrame = animatePerFrame;

  @override
  bool get isRepaintBoundary => true;

  /// Whether this render box requires re-painting every frame (e.g. video, active wave, stopwatch).
  bool get animatePerFrame => _animatePerFrame;
  set animatePerFrame(bool value) {
    if (_animatePerFrame == value) return;
    _animatePerFrame = value;
    if (attached) {
      if (_animatePerFrame) {
        _startTicker();
      } else {
        _stopTicker();
      }
    }
  }

  /// Mark that internal state has changed and a repaint is required on the next frame.
  void markDirty() {
    _isDirty = true;
    markNeedsPaint();
  }

  /// Whether internal state is dirty and needs repainting.
  bool get isDirty => _isDirty;

  void _startTicker() {
    if (_ticker != null) return;
    _ticker = Ticker(_onTick)..start();
  }

  void _stopTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  void _onTick(Duration elapsed) {
    if (!attached) return;
    if (onFrameTick(elapsed)) {
      markNeedsPaint();
    }
  }

  /// Called on each VSync tick if [animatePerFrame] is true.
  /// Return true to trigger [markNeedsPaint], or false to skip.
  bool onFrameTick(Duration elapsed) => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_animatePerFrame) {
      _startTicker();
    }
  }

  @override
  void detach() {
    _stopTicker();
    super.detach();
  }

  @override
  void performLayout() {
    // Default to filling constraints if bounded, or fallback to zero
    size = constraints.biggest.isFinite
        ? constraints.biggest
        : constraints.constrain(Size.zero);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _isDirty = false;
    paintZero(context, offset);
  }

  /// Perform direct canvas painting without allocating objects on the Dart heap.
  void paintZero(PaintingContext context, Offset offset);
}

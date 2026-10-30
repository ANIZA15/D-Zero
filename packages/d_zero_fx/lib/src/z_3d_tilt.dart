import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [Z3DTilt].
typedef ZParallaxContainer = Z3DTilt;

/// Deprecated legacy alias for [Z3DTilt].
@Deprecated('Use Z3DTilt instead.')
typedef Zero3DTilt = Z3DTilt;

/// A zero-allocation, compositor-layer 3D perspective tilt container widget.
///
/// Updates a cached [TransformLayer] 4x4 perspective matrix directly in the
/// rendering tree without rebuilding or re-laying out its [child] widget when
/// pointer coordinates or external [tiltListenable] values change.
class Z3DTilt extends ZSingleChildWidget<RenderZ3DTilt> {
  /// Optional external normalized tilt source `(dx, dy)` in `-1.0..1.0`.
  final ValueListenable<Offset>? tiltListenable;

  /// Maximum tilt angle in radians along X and Y axes.
  final double maxTiltRadians;

  /// Perspective depth factor (`0.0005..0.01`, default `0.0022`).
  final double perspectiveDepth;

  /// Whether pointer hover and drag interactions tilt the container.
  final bool enablePointerTilt;

  /// Creates a const [Z3DTilt] container widget.
  const Z3DTilt({
    super.key,
    super.child,
    this.tiltListenable,
    this.maxTiltRadians = 0.26,
    this.perspectiveDepth = 0.0022,
    this.enablePointerTilt = true,
  });

  @override
  RenderZ3DTilt createRenderObject(BuildContext context) {
    return RenderZ3DTilt(
      tiltListenable: tiltListenable,
      maxTiltRadians: maxTiltRadians,
      perspectiveDepth: perspectiveDepth,
      enablePointerTilt: enablePointerTilt,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZ3DTilt renderObject) {
    renderObject
      ..tiltListenable = tiltListenable
      ..maxTiltRadians = maxTiltRadians
      ..perspectiveDepth = perspectiveDepth
      ..enablePointerTilt = enablePointerTilt;
  }
}

/// Custom [RenderProxyBox] that drives a hardware-accelerated [TransformLayer]
/// using an in-place [Matrix4] buffer with zero child rebuilds.
class RenderZ3DTilt extends RenderProxyBox {
  ValueListenable<Offset>? _tiltListenable;
  double _maxTiltRadians;
  double _perspectiveDepth;
  bool _enablePointerTilt;

  final LayerHandle<TransformLayer> _transformLayer =
      LayerHandle<TransformLayer>();
  final Matrix4 _matrix = Matrix4.identity();

  double _normX = 0.0; // -1.0 .. 1.0
  double _normY = 0.0; // -1.0 .. 1.0
  bool _isDisposed = false;

  /// Creates a [RenderZ3DTilt] render object.
  RenderZ3DTilt({
    ValueListenable<Offset>? tiltListenable,
    double maxTiltRadians = 0.26,
    double perspectiveDepth = 0.0022,
    bool enablePointerTilt = true,
  })  : _tiltListenable = tiltListenable,
        _maxTiltRadians = _clampPositive(maxTiltRadians, 0.0, 1.2),
        _perspectiveDepth = _clampPositive(perspectiveDepth, 0.0001, 0.02),
        _enablePointerTilt = enablePointerTilt;

  static double _clampPositive(double v, double minVal, double maxVal) {
    if (v.isNaN || v < minVal) return minVal;
    if (v > maxVal) return maxVal;
    return v;
  }

  /// External normalized tilt notifier (`Offset(dx, dy)` in `-1.0..1.0`).
  ValueListenable<Offset>? get tiltListenable => _tiltListenable;
  set tiltListenable(ValueListenable<Offset>? value) {
    if (identical(_tiltListenable, value)) return;
    if (attached) {
      _tiltListenable?.removeListener(_onExternalTiltChanged);
    }
    _tiltListenable = value;
    if (attached && value != null) {
      value.addListener(_onExternalTiltChanged);
      _applyNormalizedTilt(value.value.dx, value.value.dy);
    }
  }

  /// Maximum tilt angle in radians.
  double get maxTiltRadians => _maxTiltRadians;
  set maxTiltRadians(double value) {
    final double clamped = _clampPositive(value, 0.0, 1.2);
    if (_maxTiltRadians == clamped) return;
    _maxTiltRadians = clamped;
    markNeedsPaint();
  }

  /// Perspective depth factor (`m[3,2]`).
  double get perspectiveDepth => _perspectiveDepth;
  set perspectiveDepth(double value) {
    final double clamped = _clampPositive(value, 0.0001, 0.02);
    if (_perspectiveDepth == clamped) return;
    _perspectiveDepth = clamped;
    markNeedsPaint();
  }

  /// Whether pointer hover/drag updates the tilt angle.
  bool get enablePointerTilt => _enablePointerTilt;
  set enablePointerTilt(bool value) {
    if (_enablePointerTilt == value) return;
    _enablePointerTilt = value;
    if (!value && _tiltListenable == null) {
      _applyNormalizedTilt(0.0, 0.0);
    }
  }

  /// Current normalized horizontal tilt (`-1.0..1.0`).
  double get normalizedTiltX => _normX;

  /// Current normalized vertical tilt (`-1.0..1.0`).
  double get normalizedTiltY => _normY;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  void _onExternalTiltChanged() {
    if (_isDisposed) return;
    final Offset? v = _tiltListenable?.value;
    if (v == null) return;
    _applyNormalizedTilt(v.dx, v.dy);
  }

  void _applyNormalizedTilt(double nx, double ny) {
    final double cx = nx.isNaN ? 0.0 : nx.clamp(-1.0, 1.0);
    final double cy = ny.isNaN ? 0.0 : ny.clamp(-1.0, 1.0);
    if ((cx - _normX).abs() < 0.0005 && (cy - _normY).abs() < 0.0005) {
      return;
    }
    _normX = cx;
    _normY = cy;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    final listenable = _tiltListenable;
    if (listenable != null) {
      listenable.addListener(_onExternalTiltChanged);
      _applyNormalizedTilt(listenable.value.dx, listenable.value.dy);
    }
  }

  @override
  void detach() {
    _tiltListenable?.removeListener(_onExternalTiltChanged);
    _transformLayer.layer = null;
    super.detach();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tiltListenable?.removeListener(_onExternalTiltChanged);
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => _enablePointerTilt;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (!_enablePointerTilt || !hasSize) return;
    if (_isResetPointerEvent(event)) {
      _applyNormalizedTilt(0.0, 0.0);
      return;
    }
    if (_isActivePointerEvent(event)) {
      _updateTiltFromLocalPosition(event.localPosition);
    }
  }

  static bool _isActivePointerEvent(PointerEvent event) {
    return event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerHoverEvent;
  }

  static bool _isResetPointerEvent(PointerEvent event) {
    return event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerExitEvent;
  }

  void _updateTiltFromLocalPosition(Offset localPosition) {
    final double w = size.width;
    final double h = size.height;
    if (w <= 0.0 || h <= 0.0) return;
    final double nx = (localPosition.dx / w) * 2.0 - 1.0;
    final double ny = (localPosition.dy / h) * 2.0 - 1.0;
    _applyNormalizedTilt(nx, ny);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      _transformLayer.layer = null;
      return;
    }

    _updatePerspectiveMatrix(offset);
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      Offset.zero,
      _matrix,
      (PaintingContext innerContext, Offset _) {
        innerContext.paintChild(child!, offset);
      },
      oldLayer: _transformLayer.layer,
    );
  }

  void _updatePerspectiveMatrix(Offset offset) {
    final double cx = offset.dx + size.width * 0.5;
    final double cy = offset.dy + size.height * 0.5;
    final double rotX = -_normY * _maxTiltRadians;
    final double rotY = _normX * _maxTiltRadians;

    final double cosX = math.cos(rotX);
    final double sinX = math.sin(rotX);
    final double cosY = math.cos(rotY);
    final double sinY = math.sin(rotY);

    _matrix
      ..setIdentity()
      ..translateByDouble(cx, cy, 0.0, 1.0)
      ..setEntry(3, 2, _perspectiveDepth)
      ..rotateX(sinX != 0.0 || cosX != 1.0 ? rotX : 0.0)
      ..rotateY(sinY != 0.0 || cosY != 1.0 ? rotY : 0.0)
      ..translateByDouble(-cx, -cy, 0.0, 1.0);
  }
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';
import 'z_engine_telemetry_hud.dart';

/// Active Z-prefixed alias for [ZViewport3D].
typedef ZScene3D = ZViewport3D;

/// Deprecated legacy alias for [ZViewport3D].
@Deprecated('Use ZViewport3D instead.')
typedef ZeroViewport3D = ZViewport3D;

/// A zero-allocation, zero-rebuild 3D Game Engine Viewport widget.
///
/// Combines:
/// 1. Native Metal 3 / DirectX 12 triple-buffered `IOSurface` / `DXGI` zero-copy GPU texture
///    when `controller.textureId != -1`.
/// 2. Impeller GLSL 460 Ray Tracing shader (`zero_3d_raytrace.frag`) + deterministic
///    SoA Nanite Meshlet Cluster projection (`ui.Vertices.raw`) when running in
///    cross-platform shader/software mode.
/// 3. Built-in 60Hz / 120Hz / 144Hz / 240Hz / Uncapped telemetry HUD ([ZEngineTelemetryHud]).
class ZViewport3D extends StatelessWidget implements ZWidget {
  /// Backing 3D engine controller.
  final Zero3DEngineController controller;

  /// Preferred viewport size.
  final Size size;

  /// Whether to overlay the live zero-allocation [ZEngineTelemetryHud].
  final bool showTelemetryHud;

  /// Whether to automatically orbit the scene on every VSync frame tick.
  final bool autoOrbit;

  /// Optional custom overlay widget placed above the 3D viewport.
  final Widget? overlay;

  /// Creates a const [ZViewport3D].
  const ZViewport3D({
    super.key,
    required this.controller,
    this.size = const Size(640.0, 380.0),
    this.showTelemetryHud = true,
    this.autoOrbit = true,
    this.overlay,
  });

  @override
  bool get isZeroAllocation => true;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller.textureId != -1)
            Texture(textureId: controller.textureId),
          _ZDirect3DCanvas(
            controller: controller,
            size: size,
            autoOrbit: autoOrbit,
          ),
          if (overlay != null) overlay!,
          if (showTelemetryHud)
            Positioned(
              left: 12.0,
              top: 12.0,
              child: ZEngineTelemetryHud(controller: controller),
            ),
        ],
      ),
    );
  }
}

class _ZDirect3DCanvas extends ZLeafWidget<RenderZViewport3D> {
  final Zero3DEngineController controller;
  final Size size;
  final bool autoOrbit;

  const _ZDirect3DCanvas({
    required this.controller,
    required this.size,
    required this.autoOrbit,
  });

  @override
  RenderZViewport3D createRenderObject(BuildContext context) {
    return RenderZViewport3D(
      controller: controller,
      preferredSize: size,
      autoOrbit: autoOrbit,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZViewport3D renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..autoOrbit = autoOrbit;
  }
}

/// Custom [ZeroRenderBox] driving Impeller Ray Tracing & Nanite Cluster projection.
class RenderZViewport3D extends ZeroRenderBox {
  static const int _maxClusterTris =
      Zero3DEngineController.maxDagClusters * 2;

  Zero3DEngineController _controller;
  Size _preferredSize;
  bool _autoOrbit;

  ui.FragmentShader? _rayShader;
  bool _shaderLoadAttempted = false;
  bool _isDisposed = false;

  final Paint _bgPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF060A12);
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = const Color(0x5538BDF8);
  final Paint _shaderPaint = Paint()..style = PaintingStyle.fill;
  final Paint _clusterPaint = Paint()..style = PaintingStyle.fill;

  final Float32List _clusterPositions = Float32List(_maxClusterTris * 6);
  final Int32List _clusterColors = Int32List(_maxClusterTris * 3);

  double _elapsedSec = 0.0;
  Duration? _lastTick;

  /// Creates a [RenderZViewport3D].
  RenderZViewport3D({
    required Zero3DEngineController controller,
    required Size preferredSize,
    required bool autoOrbit,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _autoOrbit = autoOrbit,
        super(animatePerFrame: autoOrbit) {
    _tryLoadRaytraceShader();
  }

  /// Backing 3D engine controller.
  Zero3DEngineController get controller => _controller;
  set controller(Zero3DEngineController value) {
    if (identical(_controller, value)) return;
    if (attached) _controller.removeListener(markDirty);
    _controller = value;
    if (attached) _controller.addListener(markDirty);
    markDirty();
  }

  /// Preferred viewport size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Whether automatic camera orbit is enabled.
  bool get autoOrbit => _autoOrbit;
  set autoOrbit(bool value) {
    if (_autoOrbit == value) return;
    _autoOrbit = value;
    _lastTick = null;
    animatePerFrame = value;
    markDirty();
  }

  void _tryLoadRaytraceShader() {
    if (_shaderLoadAttempted) return;
    _shaderLoadAttempted = true;
    ui.FragmentProgram.fromAsset(
      'packages/d_zero_3dengine/shaders/zero_3d_raytrace.frag',
    ).then((ui.FragmentProgram prog) {
      if (_isDisposed) return;
      _rayShader = prog.fragmentShader();
      if (attached) markDirty();
    }).catchError((Object _) {});
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
  void dispose() {
    _isDisposed = true;
    _controller.removeListener(markDirty);
    _shaderPaint.shader = null;
    _rayShader?.dispose();
    _rayShader = null;
    super.dispose();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.constrain(_preferredSize);
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (_controller.isDisposed) return;
    if (event is PointerMoveEvent) {
      _controller.orbitBy(event.delta.dx * 0.01, event.delta.dy * 0.008);
    } else if (event is PointerScrollEvent) {
      _controller.zoomBy(event.scrollDelta.dy * 0.005);
    }
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_autoOrbit || _controller.isDisposed) return false;
    final Duration? prev = _lastTick;
    _lastTick = elapsed;
    if (prev == null) return false;
    final int dtUs = (elapsed - prev).inMicroseconds;
    if (dtUs <= 0) return false;
    final double dtMs = (dtUs / 1000.0).clamp(0.2, 100.0);
    _elapsedSec = (_elapsedSec + dtMs * 0.001) % (math.pi * 200.0);
    _controller.orbitBy(dtMs * 0.00045, 0.0);
    if (_controller.textureId == -1) {
      _controller.stepSimulation(dtMs: dtMs);
    }
    return true;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    if (_controller.isDisposed) return;

    // Native Metal 3 / DirectX 12 Texture が有効な場合は背面の Texture を透過表示し枠線のみ描画
    if (_controller.textureId != -1) {
      canvas.drawRect(bounds.deflate(0.5), _borderPaint);
      return;
    }

    canvas.drawRect(bounds, _bgPaint);
    canvas.save();
    canvas.clipRect(bounds);

    final ui.FragmentShader? shader = _rayShader;
    if (shader != null && _bindRayUniforms(shader, size.width, size.height)) {
      _shaderPaint.shader = shader;
      canvas.translate(offset.dx, offset.dy);
      canvas.drawRect(Offset.zero & size, _shaderPaint);
      canvas.translate(-offset.dx, -offset.dy);
    }

    _paintNaniteClusterOverlay(canvas, offset);
    canvas.restore();
    canvas.drawRect(bounds.deflate(0.5), _borderPaint);
  }

  bool _bindRayUniforms(ui.FragmentShader shader, double w, double h) {
    try {
      shader.setFloat(0, w);
      shader.setFloat(1, h);
      shader.setFloat(2, _elapsedSec);
      shader.setFloat(3, _controller.cameraYaw);
      shader.setFloat(4, _controller.cameraPitch);
      shader.setFloat(5, _controller.cameraDistance);
      shader.setFloat(6, _controller.lightAzimuth);
      shader.setFloat(7, _controller.lightElevation);
      shader.setFloat(8, _controller.renderMode.index.toDouble());
      return true;
    } catch (_) {
      return false;
    }
  }

  void _paintNaniteClusterOverlay(Canvas canvas, Offset offset) {
    final double minDim =
        size.width < size.height ? size.width : size.height;
    final int visibleTris = _controller.evaluateAndProjectNaniteClusters(
      centerX: offset.dx + size.width * 0.5,
      centerY: offset.dy + size.height * 0.5,
      scale: minDim * 0.95,
      outPositions: _clusterPositions,
      outColors: _clusterColors,
    );
    if (visibleTris <= 0) return;

    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_clusterPositions, 0, visibleTris * 6),
      colors: Int32List.sublistView(_clusterColors, 0, visibleTris * 3),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _clusterPaint);
    vertices.dispose();
  }
}

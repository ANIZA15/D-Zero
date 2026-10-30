import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZShaderSurface].
typedef ZRuntimeShader = ZShaderSurface;

/// Deprecated legacy alias for [ZShaderSurface].
@Deprecated('Use ZShaderSurface instead.')
typedef ZeroShaderSurface = ZShaderSurface;

/// Fixed-capacity uniform buffer & [ui.FragmentShader] controller for [ZShaderSurface].
///
/// Stores up to [maxUniformFloats] custom float uniforms in a pre-allocated
/// [Float32List] so that updating shader parameters on every frame allocates
/// zero heap objects. Supports attaching a pre-compiled [ui.FragmentShader]
/// or loading an AOT-compiled `.frag` asset via [loadAsset].
class ZeroShaderController implements Listenable {
  /// Maximum number of custom float uniform slots (`64`).
  static const int maxAllowedUniforms = 64;

  /// Number of custom float uniform slots managed by this controller.
  final int uniformCount;

  late final Float32List _uniforms;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  ui.FragmentShader? _shader;
  bool _ownsShader = false;
  bool _isDisposed = false;

  /// Creates a [ZeroShaderController] with [uniformCount] custom float slots.
  ZeroShaderController({
    int uniformCount = 8,
    ui.FragmentShader? shader,
    bool ownsShader = false,
  })  : uniformCount = _clampSlots(uniformCount),
        _shader = shader,
        _ownsShader = ownsShader {
    _uniforms = Float32List(this.uniformCount);
  }

  static int _clampSlots(int count) {
    if (count < 1) return 1;
    if (count > maxAllowedUniforms) return maxAllowedUniforms;
    return count;
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Whether a native GPU [ui.FragmentShader] is currently bound.
  bool get hasBoundShader => !_isDisposed && _shader != null;

  /// Currently bound [ui.FragmentShader], or `null` if unbound or disposed.
  ui.FragmentShader? get shader => _isDisposed ? null : _shader;

  /// Binds an existing [ui.FragmentShader] instance to this controller.
  void bindShader(ui.FragmentShader? nextShader, {bool takeOwnership = false}) {
    if (_isDisposed) return;
    if (identical(_shader, nextShader)) return;
    if (_ownsShader) {
      _shader?.dispose();
    }
    _shader = nextShader;
    _ownsShader = takeOwnership;
    _revision.add(1);
  }

  /// Asynchronously loads an AOT-compiled [ui.FragmentProgram] from [assetKey]
  /// (e.g. `'packages/d_zero_fx/shaders/zero_holo_grid.frag'`) and binds its shader.
  Future<bool> loadAsset(String assetKey) async {
    if (_isDisposed) return false;
    try {
      final ui.FragmentProgram program =
          await ui.FragmentProgram.fromAsset(assetKey);
      if (_isDisposed) return false;
      bindShader(program.fragmentShader(), takeOwnership: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reads custom float uniform at [slot] (`0..uniformCount - 1`).
  double uniformAt(int slot) {
    if (_isDisposed || slot < 0 || slot >= _uniforms.length) return 0.0;
    return _uniforms[slot];
  }

  /// Sets custom float uniform at [slot] (`0..uniformCount - 1`) in-place.
  void setUniform(int slot, double value) {
    if (_isDisposed || slot < 0 || slot >= _uniforms.length) return;
    final double clean = value.isNaN || value.isInfinite ? 0.0 : value;
    if (_uniforms[slot] == clean) return;
    _uniforms[slot] = clean;
    _revision.add(1);
  }

  /// Sets a 3-component RGB color into uniform slots `[startSlot .. startSlot + 2]`.
  void setUniformColor(int startSlot, Color color) {
    if (_isDisposed || startSlot < 0 || startSlot + 2 >= _uniforms.length) {
      return;
    }
    _uniforms[startSlot] = color.r;
    _uniforms[startSlot + 1] = color.g;
    _uniforms[startSlot + 2] = color.b;
    _revision.add(1);
  }

  /// Flushes standard header uniforms (`uResolution`, `uTime`, `uPointer`) plus
  /// [activeCustomFloats] custom slots into the bound [ui.FragmentShader].
  bool applyToShader({
    required double width,
    required double height,
    required double timeSeconds,
    required double pointerX,
    required double pointerY,
    int activeCustomFloats = 4,
  }) {
    final ui.FragmentShader? active = _shader;
    if (_isDisposed || active == null) return false;
    try {
      // Standard D-Zero shader ABI:
      // 0: width, 1: height, 2: time, 3: pointerX, 4: pointerY, 5..: custom uniforms
      active.setFloat(0, width);
      active.setFloat(1, height);
      active.setFloat(2, timeSeconds);
      active.setFloat(3, pointerX);
      active.setFloat(4, pointerY);
      final int limit = activeCustomFloats < _uniforms.length
          ? activeCustomFloats
          : _uniforms.length;
      for (int i = 0; i < limit; i++) {
        active.setFloat(5 + i, _uniforms[i]);
      }
      return true;
    } catch (_) {
      return false;
    }
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

  /// Disposes the controller and any owned [ui.FragmentShader] (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_ownsShader) {
      _shader?.dispose();
    }
    _shader = null;
    _uniforms.fillRange(0, _uniforms.length, 0.0);
    _revision.dispose();
  }
}

/// A zero-allocation GPU fragment shader & procedural 3D holo-grid surface widget.
///
/// Drives an AOT-compiled Impeller [ui.FragmentShader] (such as `zero_holo_grid.frag`)
/// via pre-allocated uniform slots (`uResolution`, `uTime`, `uPointer`, custom floats)
/// and includes a zero-allocation 3D perspective wireframe fallback when running in
/// headless unit-test environments without compiled shader assets.
class ZShaderSurface extends ZLeafWidget<RenderZShaderSurface> {
  /// Backing uniform and shader controller.
  final ZeroShaderController controller;

  /// Preferred surface size when unconstrained.
  final Size size;

  /// Primary holographic grid / effect color.
  final Color primaryColor;

  /// Background surface color.
  final Color backgroundColor;

  /// Number of custom float uniforms forwarded after the 5 standard header floats.
  final int activeCustomFloats;

  /// Whether the time uniform (`uTime`) advances automatically every frame.
  final bool isAnimating;

  /// Creates a const [ZShaderSurface] widget.
  const ZShaderSurface({
    super.key,
    required this.controller,
    this.size = const Size(300.0, 180.0),
    this.primaryColor = const Color(0xFF00F5D4),
    this.backgroundColor = const Color(0xFF070B14),
    this.activeCustomFloats = 4,
    this.isAnimating = true,
  });

  @override
  RenderZShaderSurface createRenderObject(BuildContext context) {
    return RenderZShaderSurface(
      controller: controller,
      preferredSize: size,
      primaryColor: primaryColor,
      backgroundColor: backgroundColor,
      activeCustomFloats: activeCustomFloats,
      isAnimating: isAnimating,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZShaderSurface renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..primaryColor = primaryColor
      ..backgroundColor = backgroundColor
      ..activeCustomFloats = activeCustomFloats
      ..isAnimating = isAnimating;
  }
}

/// Custom [ZeroRenderBox] for [ZShaderSurface].
class RenderZShaderSurface extends ZeroRenderBox {
  static const int _fallbackGridLines = 24;

  ZeroShaderController _controller;
  Size _preferredSize;
  Color _primaryColor;
  Color _backgroundColor;
  int _activeCustomFloats;
  bool _isAnimating;

  final Paint _shaderPaint = Paint();
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Float32List _fallbackPoints = Float32List(_fallbackGridLines * 4);

  double _timeSeconds = 0.0;
  Duration? _lastElapsed;
  double _pointerNormX = 0.5;
  double _pointerNormY = 0.5;

  /// Creates a [RenderZShaderSurface].
  RenderZShaderSurface({
    required ZeroShaderController controller,
    required Size preferredSize,
    required Color primaryColor,
    required Color backgroundColor,
    required int activeCustomFloats,
    required bool isAnimating,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _primaryColor = primaryColor,
        _backgroundColor = backgroundColor,
        _activeCustomFloats = activeCustomFloats.clamp(0, 64),
        _isAnimating = isAnimating,
        super(animatePerFrame: isAnimating) {
    _bgPaint.color = _backgroundColor;
    _linePaint.color = _primaryColor;
  }

  /// Backing shader controller.
  ZeroShaderController get controller => _controller;
  set controller(ZeroShaderController value) {
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

  /// Preferred surface size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Primary holographic color.
  Color get primaryColor => _primaryColor;
  set primaryColor(Color value) {
    if (_primaryColor == value) return;
    _primaryColor = value;
    _linePaint.color = value;
    markDirty();
  }

  /// Background fill color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Number of custom float uniforms forwarded per frame.
  int get activeCustomFloats => _activeCustomFloats;
  set activeCustomFloats(int value) {
    final int clamped = value.clamp(0, 64);
    if (_activeCustomFloats == clamped) return;
    _activeCustomFloats = clamped;
    markDirty();
  }

  /// Whether automatic frame animation is active.
  bool get isAnimating => _isAnimating;
  set isAnimating(bool value) {
    if (_isAnimating == value) return;
    _isAnimating = value;
    _lastElapsed = null;
    animatePerFrame = value;
    markDirty();
  }

  /// Current elapsed shader time in seconds.
  double get timeSeconds => _timeSeconds;

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
    _controller.removeListener(markDirty);
    _shaderPaint.shader = null;
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
    if (!hasSize || size.width <= 0.0 || size.height <= 0.0) return;
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _pointerNormX = (event.localPosition.dx / size.width).clamp(0.0, 1.0);
      _pointerNormY = (event.localPosition.dy / size.height).clamp(0.0, 1.0);
      markDirty();
    }
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_isAnimating) return false;
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return false;
    final int dtMicros = (elapsed - prev).inMicroseconds;
    if (dtMicros <= 0) return false;
    _timeSeconds = (_timeSeconds + (dtMicros / 1000000.0).clamp(0.0, 0.1)) % 3600.0;
    return true;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    if (size.width <= 0.0 || size.height <= 0.0) return;

    final bool shaderReady = _controller.applyToShader(
      width: size.width,
      height: size.height,
      timeSeconds: _timeSeconds,
      pointerX: _pointerNormX,
      pointerY: _pointerNormY,
      activeCustomFloats: _activeCustomFloats,
    );

    if (shaderReady && _controller.shader != null) {
      _shaderPaint.shader = _controller.shader;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawRect(Offset.zero & size, _shaderPaint);
      canvas.restore();
      return;
    }

    _paintPerspectiveGridFallback(canvas, bounds);
  }

  void _paintPerspectiveGridFallback(Canvas canvas, Rect bounds) {
    canvas.drawRect(bounds, _bgPaint);
    final double w = bounds.width;
    final double h = bounds.height;
    final double horizonY =
        bounds.top + h * (0.35 + (_pointerNormY - 0.5) * 0.2);
    final double vanishX =
        bounds.left + w * (0.5 + (_pointerNormX - 0.5) * 0.3);

    int segIdx = 0;
    // Radial perspective rays from vanishing point to bottom edge
    for (int i = 0; i < 12; i++) {
      final double norm = (i / 11.0) * 2.0 - 1.0;
      final int b = segIdx << 2;
      _fallbackPoints[b] = vanishX;
      _fallbackPoints[b + 1] = horizonY;
      _fallbackPoints[b + 2] = bounds.left + (w * 0.5) + norm * w * 0.85;
      _fallbackPoints[b + 3] = bounds.bottom;
      segIdx++;
    }

    // Scrolling horizontal depth lines
    final double phase = (_timeSeconds * 1.6) % 1.0;
    for (int i = 0; i < 12; i++) {
      final double t = ((i + phase) / 12.0);
      final double y = horizonY + (bounds.bottom - horizonY) * (t * t);
      final int b = segIdx << 2;
      _fallbackPoints[b] = bounds.left;
      _fallbackPoints[b + 1] = y;
      _fallbackPoints[b + 2] = bounds.right;
      _fallbackPoints[b + 3] = y;
      segIdx++;
    }

    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRawPoints(
      ui.PointMode.lines,
      Float32List.sublistView(_fallbackPoints, 0, segIdx << 2),
      _linePaint,
    );
    canvas.restore();
  }
}

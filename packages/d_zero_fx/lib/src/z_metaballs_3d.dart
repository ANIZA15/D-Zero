import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZMetaballs3D].
typedef ZRaymarchSurface = ZMetaballs3D;

/// Deprecated legacy alias for [ZMetaballs3D].
@Deprecated('Use ZMetaballs3D instead.')
typedef ZeroMetaballs3D = ZMetaballs3D;

/// A zero-allocation 3D Signed Distance Field (SDF) metaball raymarching widget.
///
/// Evaluates smooth-union (`smin`) 3D metaballs with Blinn-Phong specular highlights
/// and Fresnel rim lighting via `shaders/zero_metaballs_3d.frag` on Impeller, with
/// a built-in zero-allocation `ui.Vertices.raw` 3D sphere-field fallback for
/// synchronous rendering before shader asset loading completes.
class ZMetaballs3D extends ZLeafWidget<RenderZMetaballs3D> {
  /// Target viewport size.
  final Size size;

  /// Primary 3D surface diffuse color.
  final Color primaryColor;

  /// Secondary Fresnel rim & accent color.
  final Color accentColor;

  /// Smooth-union (`smin`) blending factor (`0.08..0.8`).
  final double smoothness;

  /// Animation speed multiplier.
  final double speed;

  /// Whether the 3D orbital animation is active.
  final bool isAnimating;

  /// Creates a const [ZMetaballs3D] widget.
  const ZMetaballs3D({
    super.key,
    this.size = const Size(260.0, 200.0),
    this.primaryColor = const Color(0xFF06B6D4),
    this.accentColor = const Color(0xFFA855F7),
    this.smoothness = 0.35,
    this.speed = 1.0,
    this.isAnimating = true,
  });

  @override
  RenderZMetaballs3D createRenderObject(BuildContext context) {
    return RenderZMetaballs3D(
      boxSize: size,
      primaryColor: primaryColor,
      accentColor: accentColor,
      smoothness: smoothness,
      speed: speed,
      isAnimating: isAnimating,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZMetaballs3D renderObject,
  ) {
    renderObject
      ..boxSize = size
      ..primaryColor = primaryColor
      ..accentColor = accentColor
      ..smoothness = smoothness
      ..speed = speed
      ..isAnimating = isAnimating;
  }
}

/// Custom [ZeroRenderBox] for [ZMetaballs3D].
class RenderZMetaballs3D extends ZeroRenderBox {
  static const int _gridDim = 8; // 8x8 SDF field mesh fallback = 64 vertices
  static const int _vertexCount = _gridDim * _gridDim;
  static const int _indexCount = (_gridDim - 1) * (_gridDim - 1) * 6;

  Size _boxSize;
  Color _primaryColor;
  Color _accentColor;
  double _smoothness;
  double _speed;
  bool _isAnimating;

  ui.FragmentShader? _fragShader;
  bool _shaderLoadAttempted = false;
  bool _isDisposed = false;

  final Paint _paint = Paint()..style = PaintingStyle.fill;
  final Float32List _positions = Float32List(_vertexCount * 2);
  final Int32List _colors = Int32List(_vertexCount);
  final Uint16List _indices = Uint16List(_indexCount);
  final Float32List _centers = Float32List(12); // 4 balls * (x, y, z)

  double _time = 0.0;
  Duration? _lastElapsed;
  double _pointerNormX = 0.5;
  double _pointerNormY = 0.5;

  /// Creates a [RenderZMetaballs3D].
  RenderZMetaballs3D({
    required Size boxSize,
    required Color primaryColor,
    required Color accentColor,
    required double smoothness,
    required double speed,
    required bool isAnimating,
  })  : _boxSize = boxSize,
        _primaryColor = primaryColor,
        _accentColor = accentColor,
        _smoothness = smoothness.clamp(0.08, 0.8),
        _speed = speed >= 0.0 ? speed : 1.0,
        _isAnimating = isAnimating,
        super(animatePerFrame: isAnimating) {
    _buildGridIndices();
    _tryLoadCompiledShader();
  }

  /// Target size of the viewport.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Primary diffuse color.
  Color get primaryColor => _primaryColor;
  set primaryColor(Color value) {
    if (_primaryColor == value) return;
    _primaryColor = value;
    markDirty();
  }

  /// Secondary Fresnel & accent color.
  Color get accentColor => _accentColor;
  set accentColor(Color value) {
    if (_accentColor == value) return;
    _accentColor = value;
    markDirty();
  }

  /// Smooth-union blending factor (`0.08..0.8`).
  double get smoothness => _smoothness;
  set smoothness(double value) {
    final double clamped = value.clamp(0.08, 0.8);
    if (_smoothness == clamped) return;
    _smoothness = clamped;
    markDirty();
  }

  /// Animation speed multiplier.
  double get speed => _speed;
  set speed(double value) {
    final double clean = value >= 0.0 ? value : 1.0;
    if (_speed == clean) return;
    _speed = clean;
    markDirty();
  }

  /// Whether orbital animation is running.
  bool get isAnimating => _isAnimating;
  set isAnimating(bool value) {
    if (_isAnimating == value) return;
    _isAnimating = value;
    _lastElapsed = null;
    animatePerFrame = value;
    markDirty();
  }

  void _tryLoadCompiledShader() {
    if (_shaderLoadAttempted) return;
    _shaderLoadAttempted = true;
    ui.FragmentProgram.fromAsset(
      'packages/d_zero_fx/shaders/zero_metaballs_3d.frag',
    ).then((ui.FragmentProgram program) {
      if (_isDisposed) return;
      _fragShader = program.fragmentShader();
      if (attached) markDirty();
    }).catchError((Object _) {
      // Uses deterministic Vertices.raw 3D SDF field when asset is unavailable.
    });
  }

  void _buildGridIndices() {
    int k = 0;
    for (int r = 0; r < _gridDim - 1; r++) {
      for (int c = 0; c < _gridDim - 1; c++) {
        final int tl = r * _gridDim + c;
        final int tr = tl + 1;
        final int bl = tl + _gridDim;
        final int br = bl + 1;
        _indices[k++] = tl;
        _indices[k++] = tr;
        _indices[k++] = bl;
        _indices[k++] = tr;
        _indices[k++] = br;
        _indices[k++] = bl;
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _paint.shader = null;
    _fragShader?.dispose();
    _fragShader = null;
    super.dispose();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.constrain(_boxSize);
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
    final double dt = (dtMicros / 1000000.0).clamp(0.0, 0.1);
    _time = (_time + dt * _speed) % (math.pi * 200.0);
    return true;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double w = size.width;
    final double h = size.height;
    if (w <= 0.0 || h <= 0.0) return;

    final ui.FragmentShader? shader = _fragShader;
    if (shader != null && _applyShaderUniforms(shader, w, h)) {
      _paint.shader = shader;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawRect(Offset.zero & size, _paint);
      canvas.restore();
      return;
    }

    _paint.shader = null;
    _paintSdfMeshFallback(canvas, offset.dx, offset.dy, w, h);
  }

  bool _applyShaderUniforms(ui.FragmentShader shader, double w, double h) {
    try {
      shader.setFloat(0, w);
      shader.setFloat(1, h);
      shader.setFloat(2, _time);
      shader.setFloat(3, _pointerNormX);
      shader.setFloat(4, _pointerNormY);
      shader.setFloat(5, _smoothness);
      shader.setFloat(6, _primaryColor.r);
      shader.setFloat(7, _primaryColor.g);
      shader.setFloat(8, _primaryColor.b);
      shader.setFloat(9, _accentColor.r);
      shader.setFloat(10, _accentColor.g);
      shader.setFloat(11, _accentColor.b);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _paintSdfMeshFallback(
    Canvas canvas,
    double ox,
    double oy,
    double w,
    double h,
  ) {
    _updateMetaballCenters();
    const double invMax = 1.0 / (_gridDim - 1);

    for (int r = 0; r < _gridDim; r++) {
      final double v = r * invMax;
      final double ny = (0.5 - v) * 2.0;
      for (int c = 0; c < _gridDim; c++) {
        final double u = c * invMax;
        final double nx = (u - 0.5) * 2.0;
        final int idx = r * _gridDim + c;
        final int pIdx = idx << 1;
        _positions[pIdx] = ox + u * w;
        _positions[pIdx + 1] = oy + v * h;
        _colors[idx] = _evaluateSdfColor(nx, ny);
      }
    }

    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _positions,
      colors: _colors,
      indices: _indices,
    );
    canvas.drawVertices(vertices, BlendMode.dst, _paint);
    vertices.dispose();
  }

  void _updateMetaballCenters() {
    _centers[0] = math.sin(_time * 1.1) * 0.65;
    _centers[1] = math.cos(_time * 0.9) * 0.45;
    _centers[2] = math.sin(_time * 0.7) * 0.3;

    _centers[3] = math.cos(_time * 0.8) * -0.65;
    _centers[4] = math.sin(_time * 1.3) * 0.5;
    _centers[5] = math.cos(_time * 1.1) * 0.25;

    _centers[6] = (_pointerNormX - 0.5) * 1.5;
    _centers[7] = (0.5 - _pointerNormY) * 1.1;
    _centers[8] = 0.15;

    _centers[9] = math.sin(_time * 1.5 + 2.0) * 0.5;
    _centers[10] = math.cos(_time * 1.2 + 1.0) * -0.5;
    _centers[11] = -0.2;
  }

  int _evaluateSdfColor(double nx, double ny) {
    double field = 0.0;
    for (int i = 0; i < 12; i += 3) {
      final double dx = nx - _centers[i];
      final double dy = ny - _centers[i + 1];
      final double dz = _centers[i + 2];
      final double distSq = dx * dx + dy * dy + dz * dz + 0.08;
      field += (0.14 * _smoothness) / distSq;
    }
    final double intensity = field.clamp(0.0, 1.4);
    final double spec = intensity > 0.85 ? (intensity - 0.85) * 1.5 : 0.0;
    final double mixT = (intensity * 0.75).clamp(0.0, 1.0);

    final int r = (((0.05 + (_primaryColor.r * (1.0 - mixT) + _accentColor.r * mixT) * intensity + spec) * 255.0))
        .round()
        .clamp(0, 255);
    final int g = (((0.07 + (_primaryColor.g * (1.0 - mixT) + _accentColor.g * mixT) * intensity + spec) * 255.0))
        .round()
        .clamp(0, 255);
    final int b = (((0.14 + (_primaryColor.b * (1.0 - mixT) + _accentColor.b * mixT) * intensity + spec) * 255.0))
        .round()
        .clamp(0, 255);
    return ((0xFF << 24) | (r << 16) | (g << 8) | b).toSigned(32);
  }
}

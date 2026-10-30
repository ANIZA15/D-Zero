import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [ZMeshGradient].
typedef ZFluidGradient = ZMeshGradient;

/// Deprecated legacy alias for [ZMeshGradient].
@Deprecated('Use ZMeshGradient instead.')
typedef ZeroMeshGradient = ZMeshGradient;

/// A zero-allocation, zero-tessellation animated 2D mesh gradient widget.
///
/// Subdivides a 2D grid into triangle vertices ([Float32List]), vertex colors ([Int32List]),
/// and triangle indices ([Uint16List]), feeding them directly to the GPU rasterizer via
/// [ui.Vertices.raw] and [Canvas.drawVertices] in a single draw call—bypassing `Path`
/// tessellation and offscreen `saveLayer` buffers completely.
class ZMeshGradient extends ZLeafWidget<RenderZMeshGradient> {
  /// Target viewport size of the mesh gradient.
  final Size size;

  /// Top-left anchor color of the mesh.
  final Color topLeftColor;

  /// Top-right anchor color of the mesh.
  final Color topRightColor;

  /// Bottom-left anchor color of the mesh.
  final Color bottomLeftColor;

  /// Bottom-right anchor color of the mesh.
  final Color bottomRightColor;

  /// Animation speed multiplier (`1.0` = normal speed).
  final double speed;

  /// Vertex wave distortion amplitude (`0.0..1.0`).
  final double warpIntensity;

  /// Corner radius when clipping the mesh (0 for unclipped).
  final double borderRadius;

  /// Whether the harmonic mesh animation is active.
  final bool isAnimating;

  /// Creates a const [ZMeshGradient] widget.
  const ZMeshGradient({
    super.key,
    this.size = const Size(280.0, 160.0),
    this.topLeftColor = const Color(0xFF0EA5E9),
    this.topRightColor = const Color(0xFF8B5CF6),
    this.bottomLeftColor = const Color(0xFF10B981),
    this.bottomRightColor = const Color(0xFFF43F5E),
    this.speed = 1.0,
    this.warpIntensity = 0.28,
    this.borderRadius = 12.0,
    this.isAnimating = true,
  });

  @override
  RenderZMeshGradient createRenderObject(BuildContext context) {
    return RenderZMeshGradient(
      boxSize: size,
      topLeftColor: topLeftColor,
      topRightColor: topRightColor,
      bottomLeftColor: bottomLeftColor,
      bottomRightColor: bottomRightColor,
      speed: speed,
      warpIntensity: warpIntensity,
      borderRadius: borderRadius,
      isAnimating: isAnimating,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZMeshGradient renderObject,
  ) {
    renderObject
      ..boxSize = size
      ..topLeftColor = topLeftColor
      ..topRightColor = topRightColor
      ..bottomLeftColor = bottomLeftColor
      ..bottomRightColor = bottomRightColor
      ..speed = speed
      ..warpIntensity = warpIntensity
      ..borderRadius = borderRadius
      ..isAnimating = isAnimating;
  }
}

/// Custom [ZeroRenderBox] that computes a harmonic 2D vertex mesh in pre-allocated
/// [Float32List] / [Int32List] buffers and renders it via [ui.Vertices.raw].
class RenderZMeshGradient extends ZeroRenderBox {
  static const int _gridSize = 6; // 6x6 vertices = 36 vertices, 25 quads = 50 triangles
  static const int _vertexCount = _gridSize * _gridSize;
  static const int _indexCount = (_gridSize - 1) * (_gridSize - 1) * 6;

  Size _boxSize;
  Color _topLeftColor;
  Color _topRightColor;
  Color _bottomLeftColor;
  Color _bottomRightColor;
  double _speed;
  double _warpIntensity;
  double _borderRadius;
  bool _isAnimating;

  final Float32List _positions = Float32List(_vertexCount * 2);
  final Int32List _colors = Int32List(_vertexCount);
  final Uint16List _indices = Uint16List(_indexCount);
  final Int32List _cornerRgba = Int32List(16); // 4 corners * (R, G, B, A)
  final Paint _meshPaint = Paint()..style = PaintingStyle.fill;

  double _phase = 0.0;
  Duration? _lastElapsed;
  double _pointerNormX = 0.5;
  double _pointerNormY = 0.5;
  bool _pointerActive = false;

  /// Creates a [RenderZMeshGradient].
  RenderZMeshGradient({
    required Size boxSize,
    required Color topLeftColor,
    required Color topRightColor,
    required Color bottomLeftColor,
    required Color bottomRightColor,
    required double speed,
    required double warpIntensity,
    required double borderRadius,
    required bool isAnimating,
  })  : _boxSize = boxSize,
        _topLeftColor = topLeftColor,
        _topRightColor = topRightColor,
        _bottomLeftColor = bottomLeftColor,
        _bottomRightColor = bottomRightColor,
        _speed = _sanitizeNonNegative(speed, 1.0),
        _warpIntensity = _clampUnit(warpIntensity),
        _borderRadius = _sanitizeNonNegative(borderRadius, 0.0),
        _isAnimating = isAnimating,
        super(animatePerFrame: isAnimating) {
    _buildIndices();
    _unpackCornerColors();
  }

  static double _clampUnit(double v) {
    if (v.isNaN || v <= 0.0) return 0.0;
    if (v >= 1.0) return 1.0;
    return v;
  }

  static double _sanitizeNonNegative(double v, double fallback) {
    if (v.isNaN || v.isInfinite || v < 0.0) return fallback;
    return v;
  }

  /// Target size of the mesh box.
  Size get boxSize => _boxSize;
  set boxSize(Size value) {
    if (_boxSize == value) return;
    _boxSize = value;
    markNeedsLayout();
  }

  /// Top-left anchor color.
  Color get topLeftColor => _topLeftColor;
  set topLeftColor(Color value) {
    if (_topLeftColor == value) return;
    _topLeftColor = value;
    _unpackCornerColors();
    markDirty();
  }

  /// Top-right anchor color.
  Color get topRightColor => _topRightColor;
  set topRightColor(Color value) {
    if (_topRightColor == value) return;
    _topRightColor = value;
    _unpackCornerColors();
    markDirty();
  }

  /// Bottom-left anchor color.
  Color get bottomLeftColor => _bottomLeftColor;
  set bottomLeftColor(Color value) {
    if (_bottomLeftColor == value) return;
    _bottomLeftColor = value;
    _unpackCornerColors();
    markDirty();
  }

  /// Bottom-right anchor color.
  Color get bottomRightColor => _bottomRightColor;
  set bottomRightColor(Color value) {
    if (_bottomRightColor == value) return;
    _bottomRightColor = value;
    _unpackCornerColors();
    markDirty();
  }

  /// Animation speed multiplier.
  double get speed => _speed;
  set speed(double value) {
    final double clean = _sanitizeNonNegative(value, 1.0);
    if (_speed == clean) return;
    _speed = clean;
    markDirty();
  }

  /// Vertex wave distortion intensity (`0.0..1.0`).
  double get warpIntensity => _warpIntensity;
  set warpIntensity(double value) {
    final double clamped = _clampUnit(value);
    if (_warpIntensity == clamped) return;
    _warpIntensity = clamped;
    markDirty();
  }

  /// Corner radius for optional rounded clipping.
  double get borderRadius => _borderRadius;
  set borderRadius(double value) {
    final double clean = _sanitizeNonNegative(value, 0.0);
    if (_borderRadius == clean) return;
    _borderRadius = clean;
    markDirty();
  }

  /// Whether the harmonic animation is running.
  bool get isAnimating => _isAnimating;
  set isAnimating(bool value) {
    if (_isAnimating == value) return;
    _isAnimating = value;
    _lastElapsed = null;
    animatePerFrame = value;
    markDirty();
  }

  void _buildIndices() {
    int k = 0;
    for (int r = 0; r < _gridSize - 1; r++) {
      for (int c = 0; c < _gridSize - 1; c++) {
        final int tl = r * _gridSize + c;
        final int tr = tl + 1;
        final int bl = tl + _gridSize;
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

  void _unpackCornerColors() {
    _writeCorner(0, _topLeftColor);
    _writeCorner(4, _topRightColor);
    _writeCorner(8, _bottomLeftColor);
    _writeCorner(12, _bottomRightColor);
  }

  void _writeCorner(int offset, Color c) {
    _cornerRgba[offset] = (c.r * 255.0).round() & 0xFF;
    _cornerRgba[offset + 1] = (c.g * 255.0).round() & 0xFF;
    _cornerRgba[offset + 2] = (c.b * 255.0).round() & 0xFF;
    _cornerRgba[offset + 3] = (c.a * 255.0).round() & 0xFF;
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
      _pointerActive = true;
      _pointerNormX = (event.localPosition.dx / size.width).clamp(0.0, 1.0);
      _pointerNormY = (event.localPosition.dy / size.height).clamp(0.0, 1.0);
      markDirty();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointerActive = false;
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
    final double dtSec = (dtMicros / 1000000.0).clamp(0.0, 0.1);
    _phase = (_phase + dtSec * _speed * 2.2) % (math.pi * 200.0);
    return true;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double w = size.width;
    final double h = size.height;
    if (w <= 0.0 || h <= 0.0) return;

    _updateMeshBuffers(offset.dx, offset.dy, w, h);

    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _positions,
      colors: _colors,
      indices: _indices,
    );

    if (_borderRadius > 0.0) {
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(offset & size, Radius.circular(_borderRadius)),
      );
      canvas.drawVertices(vertices, BlendMode.dst, _meshPaint);
      canvas.restore();
    } else {
      canvas.drawVertices(vertices, BlendMode.dst, _meshPaint);
    }
    vertices.dispose();
  }

  void _updateMeshBuffers(double ox, double oy, double w, double h) {
    const double invMax = 1.0 / (_gridSize - 1);
    final double cellW = w * invMax;
    final double cellH = h * invMax;
    final double ampX = cellW * _warpIntensity * 0.85;
    final double ampY = cellH * _warpIntensity * 0.85;

    for (int r = 0; r < _gridSize; r++) {
      final double v = r * invMax;
      final bool isBoundaryRow = r == 0 || r == _gridSize - 1;
      for (int c = 0; c < _gridSize; c++) {
        final double u = c * invMax;
        final bool isBoundary =
            isBoundaryRow || c == 0 || c == _gridSize - 1;
        final int idx = r * _gridSize + c;
        _writeVertexPosition(
          idx: idx,
          u: u,
          v: v,
          ox: ox,
          oy: oy,
          w: w,
          h: h,
          ampX: isBoundary ? 0.0 : ampX,
          ampY: isBoundary ? 0.0 : ampY,
        );
        _colors[idx] = _interpolateBilinearColor(u, v, idx);
      }
    }
  }

  void _writeVertexPosition({
    required int idx,
    required double u,
    required double v,
    required double ox,
    required double oy,
    required double w,
    required double h,
    required double ampX,
    required double ampY,
  }) {
    double px = ox + u * w;
    double py = oy + v * h;
    if (ampX > 0.0 || ampY > 0.0) {
      final double angle = _phase + (u * 4.1) + (v * 3.7);
      px += math.sin(angle) * ampX;
      py += math.cos(angle * 0.9 + u * 2.3) * ampY;
      if (_pointerActive) {
        final double dx = _pointerNormX - u;
        final double dy = _pointerNormY - v;
        final double pull = math.exp(-(dx * dx + dy * dy) * 6.0) * 0.22;
        px += dx * w * pull;
        py += dy * h * pull;
      }
    }
    final int pIdx = idx << 1;
    _positions[pIdx] = px;
    _positions[pIdx + 1] = py;
  }

  int _interpolateBilinearColor(double u, double v, int idx) {
    final double wave =
        0.5 + 0.5 * math.sin(_phase * 0.7 + idx * 0.45);
    final double su = (u + (wave - 0.5) * _warpIntensity * 0.45).clamp(0.0, 1.0);
    final double sv = (v + (0.5 - wave) * _warpIntensity * 0.45).clamp(0.0, 1.0);

    final double wTL = (1.0 - su) * (1.0 - sv);
    final double wTR = su * (1.0 - sv);
    final double wBL = (1.0 - su) * sv;
    final double wBR = su * sv;

    final int r = (_cornerRgba[0] * wTL +
            _cornerRgba[4] * wTR +
            _cornerRgba[8] * wBL +
            _cornerRgba[12] * wBR)
        .round()
        .clamp(0, 255);
    final int g = (_cornerRgba[1] * wTL +
            _cornerRgba[5] * wTR +
            _cornerRgba[9] * wBL +
            _cornerRgba[13] * wBR)
        .round()
        .clamp(0, 255);
    final int b = (_cornerRgba[2] * wTL +
            _cornerRgba[6] * wTR +
            _cornerRgba[10] * wBL +
            _cornerRgba[14] * wBR)
        .round()
        .clamp(0, 255);
    final int a = (_cornerRgba[3] * wTL +
            _cornerRgba[7] * wTR +
            _cornerRgba[11] * wBL +
            _cornerRgba[15] * wBR)
        .round()
        .clamp(0, 255);

    return ((a << 24) | (r << 16) | (g << 8) | b).toSigned(32);
  }
}

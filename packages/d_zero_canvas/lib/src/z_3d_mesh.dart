import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [Z3DMesh].
typedef Z3DGlobe = Z3DMesh;

/// Deprecated legacy alias for [Z3DMesh].
@Deprecated('Use Z3DMesh instead.')
typedef Zero3DMesh = Z3DMesh;

/// Zero-allocation Structure-of-Arrays (SoA) 3D mesh controller for [Z3DMesh].
///
/// Stores 3D model vertices (`_vx`, `_vy`, `_vz`) and triangle indices (`_triangles`),
/// and executes 3D rotation, perspective projection, screen-space back-face culling,
/// in-place depth sorting (Painter's Algorithm), and Lambertian + specular lighting
/// entirely inside pre-allocated [Float32List], [Uint16List], and [Int32List] buffers.
class Zero3DMeshController implements Listenable {
  /// Maximum allowed vertices (`4,096`).
  static const int maxAllowedVertices = 4096;

  /// Maximum allowed triangles (`8,192`).
  static const int maxAllowedTriangles = 8192;

  /// Maximum vertex capacity of this controller.
  final int maxVertices;

  /// Maximum triangle capacity of this controller.
  final int maxTriangles;

  late final Float32List _vx;
  late final Float32List _vy;
  late final Float32List _vz;
  late final Uint16List _triangles; // 3 vertex indices per triangle

  // Scratch buffers for transformed & projected coordinates and depth sorting
  late final Float32List _tx;
  late final Float32List _ty;
  late final Float32List _tz;
  late final Float32List _px;
  late final Float32List _py;
  late final Float32List _faceDepth;
  late final Int32List _faceColor;
  late final Uint16List _visibleFaces;

  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _vertexCount = 0;
  int _triangleCount = 0;
  double _rotX = 0.35;
  double _rotY = 0.55;
  double _rotZ = 0.0;
  bool _isDisposed = false;

  /// Creates an empty [Zero3DMeshController] with fixed capacities.
  Zero3DMeshController({
    int maxVertices = 512,
    int maxTriangles = 1024,
  })  : maxVertices = maxVertices.clamp(3, maxAllowedVertices),
        maxTriangles = maxTriangles.clamp(1, maxAllowedTriangles) {
    _vx = Float32List(this.maxVertices);
    _vy = Float32List(this.maxVertices);
    _vz = Float32List(this.maxVertices);
    _triangles = Uint16List(this.maxTriangles * 3);

    _tx = Float32List(this.maxVertices);
    _ty = Float32List(this.maxVertices);
    _tz = Float32List(this.maxVertices);
    _px = Float32List(this.maxVertices);
    _py = Float32List(this.maxVertices);
    _faceDepth = Float32List(this.maxTriangles);
    _faceColor = Int32List(this.maxTriangles);
    _visibleFaces = Uint16List(this.maxTriangles);
  }

  /// Creates a [Zero3DMeshController] pre-populated with a UV sphere / 3D globe mesh.
  factory Zero3DMeshController.sphere({
    int latSegments = 12,
    int lonSegments = 18,
    double radius = 1.0,
  }) {
    final int lat = latSegments.clamp(4, 32);
    final int lon = lonSegments.clamp(6, 48);
    final int vCount = (lat + 1) * (lon + 1);
    final int tCount = lat * lon * 2;
    final ctrl = Zero3DMeshController(
      maxVertices: vCount,
      maxTriangles: tCount,
    );
    ctrl._buildSphere(lat, lon, radius > 0.05 ? radius : 1.0);
    return ctrl;
  }

  /// Creates a [Zero3DMeshController] pre-populated with a 3D torus mesh.
  factory Zero3DMeshController.torus({
    int majorSegments = 18,
    int minorSegments = 10,
    double majorRadius = 0.72,
    double minorRadius = 0.28,
  }) {
    final int maj = majorSegments.clamp(6, 36);
    final int min = minorSegments.clamp(4, 24);
    final int vCount = maj * min;
    final int tCount = maj * min * 2;
    final ctrl = Zero3DMeshController(
      maxVertices: vCount,
      maxTriangles: tCount,
    );
    ctrl._buildTorus(maj, min, majorRadius, minorRadius);
    return ctrl;
  }

  /// Creates a [Zero3DMeshController] pre-populated with a 3D cube mesh.
  factory Zero3DMeshController.cube({double halfExtent = 0.72}) {
    final ctrl = Zero3DMeshController(maxVertices: 8, maxTriangles: 12);
    ctrl._buildCube(halfExtent > 0.05 ? halfExtent : 0.72);
    return ctrl;
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Number of active 3D vertices.
  int get vertexCount => _isDisposed ? 0 : _vertexCount;

  /// Number of active 3D triangles.
  int get triangleCount => _isDisposed ? 0 : _triangleCount;

  /// Current rotation around the X axis in radians.
  double get rotationX => _isDisposed ? 0.0 : _rotX;

  /// Current rotation around the Y axis in radians.
  double get rotationY => _isDisposed ? 0.0 : _rotY;

  /// Current rotation around the Z axis in radians.
  double get rotationZ => _isDisposed ? 0.0 : _rotZ;

  /// Sets the Euler rotation angles in radians and notifies listeners.
  void setRotation(double rx, double ry, [double rz = 0.0]) {
    if (_isDisposed) return;
    if (!rx.isNaN) _rotX = rx;
    if (!ry.isNaN) _rotY = ry;
    if (!rz.isNaN) _rotZ = rz;
    _revision.add(1);
  }

  /// Increments rotation angles by `([drx], [dry], [drz])` in radians.
  void rotateBy(double drx, double dry, [double drz = 0.0]) {
    if (_isDisposed) return;
    if (!drx.isNaN) _rotX = (_rotX + drx) % (math.pi * 200.0);
    if (!dry.isNaN) _rotY = (_rotY + dry) % (math.pi * 200.0);
    if (!drz.isNaN) _rotZ = (_rotZ + drz) % (math.pi * 200.0);
    _revision.add(1);
  }

  void _buildSphere(int lat, int lon, double r) {
    int vIdx = 0;
    for (int i = 0; i <= lat; i++) {
      final double theta = (i * math.pi) / lat;
      final double sinT = math.sin(theta);
      final double cosT = math.cos(theta);
      for (int j = 0; j <= lon; j++) {
        final double phi = (j * 2.0 * math.pi) / lon;
        _vx[vIdx] = r * sinT * math.cos(phi);
        _vy[vIdx] = r * cosT;
        _vz[vIdx] = r * sinT * math.sin(phi);
        vIdx++;
      }
    }
    _vertexCount = vIdx;

    int tIdx = 0;
    final int stride = lon + 1;
    for (int i = 0; i < lat; i++) {
      for (int j = 0; j < lon; j++) {
        final int a = i * stride + j;
        final int b = a + 1;
        final int c = a + stride;
        final int d = c + 1;
        _setTri(tIdx++, a, c, b);
        _setTri(tIdx++, b, c, d);
      }
    }
    _triangleCount = tIdx;
  }

  void _buildTorus(int maj, int min, double rMaj, double rMin) {
    int vIdx = 0;
    for (int i = 0; i < maj; i++) {
      final double u = (i * 2.0 * math.pi) / maj;
      final double cosU = math.cos(u);
      final double sinU = math.sin(u);
      for (int j = 0; j < min; j++) {
        final double v = (j * 2.0 * math.pi) / min;
        final double tube = rMaj + rMin * math.cos(v);
        _vx[vIdx] = tube * cosU;
        _vy[vIdx] = rMin * math.sin(v);
        _vz[vIdx] = tube * sinU;
        vIdx++;
      }
    }
    _vertexCount = vIdx;

    int tIdx = 0;
    for (int i = 0; i < maj; i++) {
      final int nextI = (i + 1) % maj;
      for (int j = 0; j < min; j++) {
        final int nextJ = (j + 1) % min;
        final int a = i * min + j;
        final int b = nextI * min + j;
        final int c = i * min + nextJ;
        final int d = nextI * min + nextJ;
        _setTri(tIdx++, a, c, b);
        _setTri(tIdx++, b, c, d);
      }
    }
    _triangleCount = tIdx;
  }

  void _buildCube(double s) {
    const List<double> coords = <double>[
      -1, -1, -1,  1, -1, -1,  1,  1, -1, -1,  1, -1,
      -1, -1,  1,  1, -1,  1,  1,  1,  1, -1,  1,  1,
    ];
    for (int i = 0; i < 8; i++) {
      _vx[i] = coords[i * 3] * s;
      _vy[i] = coords[i * 3 + 1] * s;
      _vz[i] = coords[i * 3 + 2] * s;
    }
    _vertexCount = 8;

    const List<int> tris = <int>[
      4, 5, 6,  4, 6, 7, // Front (+Z)
      1, 0, 3,  1, 3, 2, // Back (-Z)
      0, 4, 7,  0, 7, 3, // Left (-X)
      5, 1, 2,  5, 2, 6, // Right (+X)
      7, 6, 2,  7, 2, 3, // Top (+Y)
      0, 1, 5,  0, 5, 4, // Bottom (-Y)
    ];
    for (int i = 0; i < tris.length; i++) {
      _triangles[i] = tris[i];
    }
    _triangleCount = 12;
  }

  void _setTri(int triIdx, int i0, int i1, int i2) {
    final int base = triIdx * 3;
    _triangles[base] = i0;
    _triangles[base + 1] = i1;
    _triangles[base + 2] = i2;
  }

  /// Transforms, back-face culls, depth-sorts, and shades triangles into
  /// [outPositions] (`visibleTris * 6` floats) and [outColors] (`visibleTris * 3` ints).
  /// Returns the number of visible triangles emitted.
  int projectAndSort({
    required double centerX,
    required double centerY,
    required double scale,
    required double cameraDistance,
    required Color baseColor,
    required Color specularColor,
    required bool cullBackfaces,
    required Float32List outPositions,
    required Int32List outColors,
  }) {
    if (_isDisposed || _vertexCount == 0 || _triangleCount == 0) return 0;

    _transformAndProjectVertices(centerX, centerY, scale, cameraDistance);
    final int visibleCount = _cullAndShadeFaces(
      baseColor: baseColor,
      specularColor: specularColor,
      cullBackfaces: cullBackfaces,
    );
    _insertionSortFacesByDepth(visibleCount);
    return _emitSortedTriangleBuffers(visibleCount, outPositions, outColors);
  }

  void _transformAndProjectVertices(
    double centerX,
    double centerY,
    double scale,
    double cameraDist,
  ) {
    final double cx = math.cos(_rotX), sx = math.sin(_rotX);
    final double cy = math.cos(_rotY), sy = math.sin(_rotY);
    final double cz = math.cos(_rotZ), sz = math.sin(_rotZ);

    final double m00 = cy * cz;
    final double m01 = sx * sy * cz - cx * sz;
    final double m02 = cx * sy * cz + sx * sz;
    final double m10 = cy * sz;
    final double m11 = sx * sy * sz + cx * cz;
    final double m12 = cx * sy * sz - sx * cz;
    final double m20 = -sy;
    final double m21 = sx * cy;
    final double m22 = cx * cy;

    for (int i = 0; i < _vertexCount; i++) {
      final double x = _vx[i], y = _vy[i], z = _vz[i];
      final double rx = m00 * x + m01 * y + m02 * z;
      final double ry = m10 * x + m11 * y + m12 * z;
      final double rz = m20 * x + m21 * y + m22 * z;
      _tx[i] = rx;
      _ty[i] = ry;
      _tz[i] = rz;

      final double denom = (cameraDist - rz) > 0.25 ? (cameraDist - rz) : 0.25;
      final double persp = scale / denom;
      _px[i] = centerX + rx * persp;
      _py[i] = centerY - ry * persp;
    }
  }

  int _cullAndShadeFaces({
    required Color baseColor,
    required Color specularColor,
    required bool cullBackfaces,
  }) {
    final int br = (baseColor.r * 255.0).round() & 0xFF;
    final int bg = (baseColor.g * 255.0).round() & 0xFF;
    final int bb = (baseColor.b * 255.0).round() & 0xFF;
    final int sr = (specularColor.r * 255.0).round() & 0xFF;
    final int sg = (specularColor.g * 255.0).round() & 0xFF;
    final int sb = (specularColor.b * 255.0).round() & 0xFF;

    int count = 0;
    for (int t = 0; t < _triangleCount; t++) {
      final int b = t * 3;
      final int i0 = _triangles[b];
      final int i1 = _triangles[b + 1];
      final int i2 = _triangles[b + 2];

      final double sx0 = _px[i0], sy0 = _py[i0];
      final double sx1 = _px[i1], sy1 = _py[i1];
      final double sx2 = _px[i2], sy2 = _py[i2];

      // 2D screen-space signed area for back-face culling
      final double cross2D = (sx1 - sx0) * (sy2 - sy0) - (sy1 - sy0) * (sx2 - sx0);
      if (cullBackfaces && cross2D <= 0.0) continue;

      _visibleFaces[count] = t;
      _faceDepth[t] = (_tz[i0] + _tz[i1] + _tz[i2]) * 0.333333;
      _faceColor[t] = _computeFaceLitArgb(i0, i1, i2, br, bg, bb, sr, sg, sb);
      count++;
    }
    return count;
  }

  int _computeFaceLitArgb(
    int i0,
    int i1,
    int i2,
    int br,
    int bg,
    int bb,
    int sr,
    int sg,
    int sb,
  ) {
    final double ax = _tx[i1] - _tx[i0];
    final double ay = _ty[i1] - _ty[i0];
    final double az = _tz[i1] - _tz[i0];
    final double bx = _tx[i2] - _tx[i0];
    final double by = _ty[i2] - _ty[i0];
    final double bz = _tz[i2] - _tz[i0];

    double nx = ay * bz - az * by;
    double ny = az * bx - ax * bz;
    double nz = ax * by - ay * bx;
    final double len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len > 1e-6) {
      nx /= len;
      ny /= len;
      nz /= len;
    }

    // Normalized directional light (0.45, 0.65, 0.61)
    final double dotL = (nx * 0.45 + ny * 0.65 + nz * 0.61).abs();
    final double diffuse = 0.24 + 0.76 * dotL;
    final double spec = dotL > 0.78 ? ((dotL - 0.78) * 3.5).clamp(0.0, 0.75) : 0.0;

    final int r = (br * diffuse + sr * spec).round().clamp(0, 255);
    final int g = (bg * diffuse + sg * spec).round().clamp(0, 255);
    final int b = (bb * diffuse + sb * spec).round().clamp(0, 255);
    return ((0xFF << 24) | (r << 16) | (g << 8) | b).toSigned(32);
  }

  void _insertionSortFacesByDepth(int count) {
    // Sort back-to-front (ascending Z)
    for (int i = 1; i < count; i++) {
      final int keyFace = _visibleFaces[i];
      final double keyDepth = _faceDepth[keyFace];
      int j = i - 1;
      while (j >= 0 && _faceDepth[_visibleFaces[j]] > keyDepth) {
        _visibleFaces[j + 1] = _visibleFaces[j];
        j--;
      }
      _visibleFaces[j + 1] = keyFace;
    }
  }

  int _emitSortedTriangleBuffers(
    int visibleCount,
    Float32List outPositions,
    Int32List outColors,
  ) {
    final int maxTrisByPos = outPositions.length ~/ 6;
    final int maxTrisByCol = outColors.length ~/ 3;
    final int limit = visibleCount < maxTrisByPos
        ? (visibleCount < maxTrisByCol ? visibleCount : maxTrisByCol)
        : (maxTrisByPos < maxTrisByCol ? maxTrisByPos : maxTrisByCol);

    for (int k = 0; k < limit; k++) {
      final int face = _visibleFaces[k];
      final int triBase = face * 3;
      final int i0 = _triangles[triBase];
      final int i1 = _triangles[triBase + 1];
      final int i2 = _triangles[triBase + 2];
      final int col = _faceColor[face];

      final int pBase = k * 6;
      outPositions[pBase] = _px[i0];
      outPositions[pBase + 1] = _py[i0];
      outPositions[pBase + 2] = _px[i1];
      outPositions[pBase + 3] = _py[i1];
      outPositions[pBase + 4] = _px[i2];
      outPositions[pBase + 5] = _py[i2];

      final int cBase = k * 3;
      outColors[cBase] = col;
      outColors[cBase + 1] = col;
      outColors[cBase + 2] = col;
    }
    return limit;
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

  /// Disposes the controller and zeros all geometry buffers (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _vertexCount = 0;
    _triangleCount = 0;
    _vx.fillRange(0, _vx.length, 0.0);
    _vy.fillRange(0, _vy.length, 0.0);
    _vz.fillRange(0, _vz.length, 0.0);
    _revision.dispose();
  }
}

/// A zero-allocation 3D perspective mesh & globe renderer widget.
///
/// Executes 3D matrix transformation, perspective division, screen-space back-face
/// culling, in-place Painter's Algorithm depth sorting, and Lambertian + specular
/// lighting inside pre-allocated [Float32List] / [Int32List] buffers, flushing the
/// entire 3D model in a single [ui.Vertices.raw] (`VertexMode.triangles`) GPU call.
class Z3DMesh extends ZLeafWidget<RenderZ3DMesh> {
  /// Backing 3D mesh controller.
  final Zero3DMeshController controller;

  /// Preferred viewport size when unconstrained.
  final Size size;

  /// Base diffuse surface color of the 3D mesh.
  final Color baseColor;

  /// Specular highlight color of the 3D mesh.
  final Color specularColor;

  /// Background fill color.
  final Color backgroundColor;

  /// Camera distance along the +Z axis (`> 1.5`).
  final double cameraDistance;

  /// Whether to cull back-facing triangles.
  final bool cullBackfaces;

  /// Whether the mesh rotates automatically on each frame tick.
  final bool autoRotate;

  /// Auto-rotation speed in radians per second.
  final double rotationSpeed;

  /// Creates a const [Z3DMesh] widget.
  const Z3DMesh({
    super.key,
    required this.controller,
    this.size = const Size(260.0, 260.0),
    this.baseColor = const Color(0xFF0EA5E9),
    this.specularColor = const Color(0xFFE0F2FE),
    this.backgroundColor = const Color(0xFF090D16),
    this.cameraDistance = 3.2,
    this.cullBackfaces = true,
    this.autoRotate = true,
    this.rotationSpeed = 0.85,
  });

  @override
  RenderZ3DMesh createRenderObject(BuildContext context) {
    return RenderZ3DMesh(
      controller: controller,
      preferredSize: size,
      baseColor: baseColor,
      specularColor: specularColor,
      backgroundColor: backgroundColor,
      cameraDistance: cameraDistance,
      cullBackfaces: cullBackfaces,
      autoRotate: autoRotate,
      rotationSpeed: rotationSpeed,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZ3DMesh renderObject) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..baseColor = baseColor
      ..specularColor = specularColor
      ..backgroundColor = backgroundColor
      ..cameraDistance = cameraDistance
      ..cullBackfaces = cullBackfaces
      ..autoRotate = autoRotate
      ..rotationSpeed = rotationSpeed;
  }
}

/// Custom [ZeroRenderBox] for [Z3DMesh].
class RenderZ3DMesh extends ZeroRenderBox {
  Zero3DMeshController _controller;
  Size _preferredSize;
  Color _baseColor;
  Color _specularColor;
  Color _backgroundColor;
  double _cameraDistance;
  bool _cullBackfaces;
  bool _autoRotate;
  double _rotationSpeed;

  late Float32List _drawPositions;
  late Int32List _drawColors;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _meshPaint = Paint()..style = PaintingStyle.fill;

  Duration? _lastElapsed;
  int _lastVisibleTriangles = 0;

  /// Creates a [RenderZ3DMesh].
  RenderZ3DMesh({
    required Zero3DMeshController controller,
    required Size preferredSize,
    required Color baseColor,
    required Color specularColor,
    required Color backgroundColor,
    required double cameraDistance,
    required bool cullBackfaces,
    required bool autoRotate,
    required double rotationSpeed,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _baseColor = baseColor,
        _specularColor = specularColor,
        _backgroundColor = backgroundColor,
        _cameraDistance = cameraDistance > 1.5 ? cameraDistance : 1.5,
        _cullBackfaces = cullBackfaces,
        _autoRotate = autoRotate,
        _rotationSpeed = rotationSpeed,
        super(animatePerFrame: autoRotate) {
    _bgPaint.color = _backgroundColor;
    _allocateDrawBuffers(_controller.maxTriangles);
  }

  void _allocateDrawBuffers(int maxTris) {
    _drawPositions = Float32List(maxTris * 6);
    _drawColors = Int32List(maxTris * 3);
  }

  /// Backing 3D mesh controller.
  Zero3DMeshController get controller => _controller;
  set controller(Zero3DMeshController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    if (_drawColors.length < _controller.maxTriangles * 3) {
      _allocateDrawBuffers(_controller.maxTriangles);
    }
    if (attached) {
      _controller.addListener(markDirty);
    }
    markDirty();
  }

  /// Preferred viewport size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Base diffuse surface color.
  Color get baseColor => _baseColor;
  set baseColor(Color value) {
    if (_baseColor == value) return;
    _baseColor = value;
    markDirty();
  }

  /// Specular highlight color.
  Color get specularColor => _specularColor;
  set specularColor(Color value) {
    if (_specularColor == value) return;
    _specularColor = value;
    markDirty();
  }

  /// Viewport background color.
  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    _bgPaint.color = value;
    markDirty();
  }

  /// Camera Z distance (`> 1.5`).
  double get cameraDistance => _cameraDistance;
  set cameraDistance(double value) {
    final double clamped = value > 1.5 ? value : 1.5;
    if (_cameraDistance == clamped) return;
    _cameraDistance = clamped;
    markDirty();
  }

  /// Whether back-face culling is enabled.
  bool get cullBackfaces => _cullBackfaces;
  set cullBackfaces(bool value) {
    if (_cullBackfaces == value) return;
    _cullBackfaces = value;
    markDirty();
  }

  /// Whether automatic rotation is enabled.
  bool get autoRotate => _autoRotate;
  set autoRotate(bool value) {
    if (_autoRotate == value) return;
    _autoRotate = value;
    _lastElapsed = null;
    animatePerFrame = value;
    markDirty();
  }

  /// Auto-rotation speed in radians/second.
  double get rotationSpeed => _rotationSpeed;
  set rotationSpeed(double value) {
    if (_rotationSpeed == value) return;
    _rotationSpeed = value;
    markDirty();
  }

  /// Number of visible triangles rendered on the last frame.
  int get lastVisibleTriangles => _lastVisibleTriangles;

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
    if (event is PointerMoveEvent && !_controller.isDisposed) {
      final double dry = event.delta.dx * 0.012;
      final double drx = event.delta.dy * 0.012;
      _controller.rotateBy(drx, dry);
    }
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (!_autoRotate || _controller.isDisposed) return false;
    final Duration? prev = _lastElapsed;
    _lastElapsed = elapsed;
    if (prev == null) return false;
    final int dtMicros = (elapsed - prev).inMicroseconds;
    if (dtMicros <= 0) return false;
    final double dt = (dtMicros / 1000000.0).clamp(0.0, 0.1);
    _controller.rotateBy(dt * _rotationSpeed * 0.45, dt * _rotationSpeed);
    return true;
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    canvas.drawRect(bounds, _bgPaint);
    if (_controller.isDisposed || _controller.triangleCount == 0) return;

    final double minDim =
        size.width < size.height ? size.width : size.height;
    final double scale = minDim * 1.15;
    final int visibleTris = _controller.projectAndSort(
      centerX: offset.dx + size.width * 0.5,
      centerY: offset.dy + size.height * 0.5,
      scale: scale,
      cameraDistance: _cameraDistance,
      baseColor: _baseColor,
      specularColor: _specularColor,
      cullBackfaces: _cullBackfaces,
      outPositions: _drawPositions,
      outColors: _drawColors,
    );
    _lastVisibleTriangles = visibleTris;
    if (visibleTris <= 0) return;

    canvas.save();
    canvas.clipRect(bounds);
    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_drawPositions, 0, visibleTris * 6),
      colors: Int32List.sublistView(_drawColors, 0, visibleTris * 3),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _meshPaint);
    vertices.dispose();
    canvas.restore();
  }
}

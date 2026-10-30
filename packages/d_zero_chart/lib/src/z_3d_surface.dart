import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active Z-prefixed alias for [Z3DSurface].
typedef ZWaterfallChart = Z3DSurface;

/// Deprecated legacy alias for [Z3DSurface].
@Deprecated('Use Z3DSurface instead.')
typedef Zero3DSurface = Z3DSurface;

/// Zero-allocation 2D heightfield & streaming waterfall buffer for [Z3DSurface].
///
/// Stores a `[rows] x [cols]` grid of normalized `[0.0..1.0]` height values in a
/// contiguous [Float32List]. Supports both random-access height updates ([setHeight])
/// and circular row streaming ([pushRow]) for 3D FFT waterfall spectrograms.
class Zero3DSurfaceController implements Listenable {
  /// Maximum allowed grid dimension (`128`).
  static const int maxAllowedDim = 128;

  /// Number of depth rows (`Z` axis).
  final int rows;

  /// Number of horizontal columns (`X` axis).
  final int cols;

  late final Float32List _heights;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);

  int _writeRow = 0;
  bool _isDisposed = false;

  /// Creates a [Zero3DSurfaceController] with dimensions `[rows] x [cols]`.
  Zero3DSurfaceController({
    int rows = 24,
    int cols = 24,
  })  : rows = rows.clamp(2, maxAllowedDim),
        cols = cols.clamp(2, maxAllowedDim) {
    _heights = Float32List(this.rows * this.cols);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Reads the normalized height (`0.0..1.0`) at logical `([row], [col])`.
  double heightAt(int row, int col) {
    if (_isDisposed ||
        row < 0 ||
        row >= rows ||
        col < 0 ||
        col >= cols) {
      return 0.0;
    }
    final int physRow = (_writeRow + row) % rows;
    return _heights[physRow * cols + col];
  }

  /// Sets the height (`0.0..1.0`) at logical `([row], [col])` and notifies listeners.
  void setHeight(int row, int col, double value) {
    if (_isDisposed ||
        row < 0 ||
        row >= rows ||
        col < 0 ||
        col >= cols) {
      return;
    }
    final int physRow = (_writeRow + row) % rows;
    _heights[physRow * cols + col] = _clampUnit(value);
    _revision.add(1);
  }

  /// Pushes a new waterfall slice [rowValues] into the circular height buffer in $O(\text{cols})$.
  void pushRow(List<double> rowValues) {
    if (_isDisposed) return;
    final int slot = _writeRow;
    _writeRow = (slot + 1) % rows;
    final int base = slot * cols;
    final int srcLen = rowValues.length;
    for (int c = 0; c < cols; c++) {
      _heights[base + c] = c < srcLen ? _clampUnit(rowValues[c]) : 0.0;
    }
    _revision.add(1);
  }

  /// Clears all height values to `0.0`.
  void clear() {
    if (_isDisposed) return;
    _writeRow = 0;
    _heights.fillRange(0, _heights.length, 0.0);
    _revision.add(1);
  }

  static double _clampUnit(double v) {
    if (v.isNaN || v <= 0.0) return 0.0;
    if (v >= 1.0) return 1.0;
    return v;
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

  /// Disposes this controller and zeros all heights (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _writeRow = 0;
    _heights.fillRange(0, _heights.length, 0.0);
    _revision.dispose();
  }
}

/// A zero-allocation 3D perspective surface plot & waterfall spectrogram widget.
///
/// Projects a 2D heightfield matrix `(X, Y=height, Z)` through 3D yaw/pitch rotation
/// and perspective division, orders grid quads back-to-front based on camera quadrant,
/// and renders the shaded 3D terrain in a single [ui.Vertices.raw] (`VertexMode.triangles`)
/// GPU draw call.
class Z3DSurface extends ZLeafWidget<RenderZ3DSurface> {
  /// Backing 3D heightfield controller.
  final Zero3DSurfaceController controller;

  /// Preferred viewport size when unconstrained.
  final Size size;

  /// Color for minimum elevation (`0.0`).
  final Color lowColor;

  /// Color for mid elevation (`0.5`).
  final Color midColor;

  /// Color for peak elevation (`1.0`).
  final Color highColor;

  /// Viewport background color.
  final Color backgroundColor;

  /// Horizontal yaw angle in radians.
  final double yaw;

  /// Vertical pitch angle in radians.
  final double pitch;

  /// Vertical height extrusion scale (`0.1..1.5`).
  final double heightScale;

  /// Creates a const [Z3DSurface] widget.
  const Z3DSurface({
    super.key,
    required this.controller,
    this.size = const Size(320.0, 220.0),
    this.lowColor = const Color(0xFF1E3A8A),
    this.midColor = const Color(0xFF06B6D4),
    this.highColor = const Color(0xFFF43F5E),
    this.backgroundColor = const Color(0xFF090D16),
    this.yaw = 0.62,
    this.pitch = 0.55,
    this.heightScale = 0.55,
  });

  @override
  RenderZ3DSurface createRenderObject(BuildContext context) {
    return RenderZ3DSurface(
      controller: controller,
      preferredSize: size,
      lowColor: lowColor,
      midColor: midColor,
      highColor: highColor,
      backgroundColor: backgroundColor,
      yaw: yaw,
      pitch: pitch,
      heightScale: heightScale,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZ3DSurface renderObject) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..lowColor = lowColor
      ..midColor = midColor
      ..highColor = highColor
      ..backgroundColor = backgroundColor
      ..yaw = yaw
      ..pitch = pitch
      ..heightScale = heightScale;
  }
}

/// Custom [ZeroRenderBox] for [Z3DSurface].
class RenderZ3DSurface extends ZeroRenderBox {
  Zero3DSurfaceController _controller;
  Size _preferredSize;
  Color _lowColor;
  Color _midColor;
  Color _highColor;
  Color _backgroundColor;
  double _yaw;
  double _pitch;
  double _heightScale;

  late Float32List _positions;
  late Int32List _colors;
  late Uint16List _indices;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _surfacePaint = Paint()..style = PaintingStyle.fill;

  /// Creates a [RenderZ3DSurface].
  RenderZ3DSurface({
    required Zero3DSurfaceController controller,
    required Size preferredSize,
    required Color lowColor,
    required Color midColor,
    required Color highColor,
    required Color backgroundColor,
    required double yaw,
    required double pitch,
    required double heightScale,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _lowColor = lowColor,
        _midColor = midColor,
        _highColor = highColor,
        _backgroundColor = backgroundColor,
        _yaw = yaw,
        _pitch = pitch.clamp(0.15, 1.35),
        _heightScale = heightScale.clamp(0.1, 1.5) {
    _bgPaint.color = _backgroundColor;
    _allocateMeshBuffers();
  }

  void _allocateMeshBuffers() {
    final int vCount = _controller.rows * _controller.cols;
    final int iCount = (_controller.rows - 1) * (_controller.cols - 1) * 6;
    _positions = Float32List(vCount * 2);
    _colors = Int32List(vCount);
    _indices = Uint16List(iCount);
  }

  /// Backing heightfield controller.
  Zero3DSurfaceController get controller => _controller;
  set controller(Zero3DSurfaceController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    _allocateMeshBuffers();
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

  /// Minimum elevation color.
  Color get lowColor => _lowColor;
  set lowColor(Color value) {
    if (_lowColor == value) return;
    _lowColor = value;
    markDirty();
  }

  /// Mid elevation color.
  Color get midColor => _midColor;
  set midColor(Color value) {
    if (_midColor == value) return;
    _midColor = value;
    markDirty();
  }

  /// Peak elevation color.
  Color get highColor => _highColor;
  set highColor(Color value) {
    if (_highColor == value) return;
    _highColor = value;
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

  /// Horizontal yaw angle in radians.
  double get yaw => _yaw;
  set yaw(double value) {
    if (_yaw == value || value.isNaN) return;
    _yaw = value;
    markDirty();
  }

  /// Vertical pitch angle in radians.
  double get pitch => _pitch;
  set pitch(double value) {
    if (value.isNaN) return;
    final double clamped = value.clamp(0.15, 1.35);
    if (_pitch == clamped) return;
    _pitch = clamped;
    markDirty();
  }

  /// Vertical height extrusion scale.
  double get heightScale => _heightScale;
  set heightScale(double value) {
    if (value.isNaN) return;
    final double clamped = value.clamp(0.1, 1.5);
    if (_heightScale == clamped) return;
    _heightScale = clamped;
    markDirty();
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
    if (event is PointerMoveEvent) {
      _yaw = (_yaw + event.delta.dx * 0.01) % (math.pi * 2.0);
      _pitch = (_pitch + event.delta.dy * 0.008).clamp(0.15, 1.35);
      markDirty();
    }
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Rect bounds = offset & size;
    canvas.drawRect(bounds, _bgPaint);
    if (_controller.isDisposed) return;

    _projectSurfaceGrid(offset);
    _buildBackToFrontIndices();

    canvas.save();
    canvas.clipRect(bounds);
    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _positions,
      colors: _colors,
      indices: _indices,
    );
    canvas.drawVertices(vertices, BlendMode.dst, _surfacePaint);
    vertices.dispose();
    canvas.restore();
  }

  void _projectSurfaceGrid(Offset offset) {
    final int rows = _controller.rows;
    final int cols = _controller.cols;
    final double cx = offset.dx + size.width * 0.5;
    final double cy = offset.dy + size.height * 0.58;
    final double scale =
        (size.width < size.height ? size.width : size.height) * 1.15;

    final double cosY = math.cos(_yaw), sinY = math.sin(_yaw);
    final double cosP = math.cos(_pitch), sinP = math.sin(_pitch);

    for (int r = 0; r < rows; r++) {
      final double wz = (r / (rows - 1)) * 2.0 - 1.0;
      for (int c = 0; c < cols; c++) {
        final double wx = (c / (cols - 1)) * 2.0 - 1.0;
        final double hVal = _controller.heightAt(r, c);
        final double wy = hVal * _heightScale;

        final double rx = wx * cosY - wz * sinY;
        final double rz0 = wx * sinY + wz * cosY;
        final double ry = wy * cosP - rz0 * sinP;
        final double rz = wy * sinP + rz0 * cosP;

        final double denom = (3.1 - rz) > 0.4 ? (3.1 - rz) : 0.4;
        final double persp = scale / denom;

        final int vIdx = r * cols + c;
        final int pIdx = vIdx << 1;
        _positions[pIdx] = cx + rx * persp;
        _positions[pIdx + 1] = cy - ry * persp;
        _colors[vIdx] = _shadeElevationColor(r, c, hVal);
      }
    }
  }

  int _shadeElevationColor(int r, int c, double hVal) {
    final double nextH =
        c + 1 < _controller.cols ? _controller.heightAt(r, c + 1) : hVal;
    final double slopeLight = (0.85 + (hVal - nextH) * 1.4).clamp(0.55, 1.25);

    final Color c0 = hVal < 0.5 ? _lowColor : _midColor;
    final Color c1 = hVal < 0.5 ? _midColor : _highColor;
    final double t = hVal < 0.5 ? (hVal * 2.0) : ((hVal - 0.5) * 2.0);

    final int red =
        (((c0.r + (c1.r - c0.r) * t) * slopeLight) * 255.0).round().clamp(0, 255);
    final int green =
        (((c0.g + (c1.g - c0.g) * t) * slopeLight) * 255.0).round().clamp(0, 255);
    final int blue =
        (((c0.b + (c1.b - c0.b) * t) * slopeLight) * 255.0).round().clamp(0, 255);
    return ((0xFF << 24) | (red << 16) | (green << 8) | blue).toSigned(32);
  }

  void _buildBackToFrontIndices() {
    final int rows = _controller.rows;
    final int cols = _controller.cols;
    final bool reverseR = math.cos(_yaw) < 0.0;
    final bool reverseC = math.sin(_yaw) >= 0.0;

    int k = 0;
    for (int ri = 0; ri < rows - 1; ri++) {
      final int r = reverseR ? (rows - 2 - ri) : ri;
      for (int ci = 0; ci < cols - 1; ci++) {
        final int c = reverseC ? (cols - 2 - ci) : ci;
        final int tl = r * cols + c;
        final int tr = tl + 1;
        final int bl = tl + cols;
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
}

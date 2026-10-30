import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Zero-allocation flat 2D matrix buffer (`rows * cols`) of normalized `[0.0..1.0]` values.
class ZeroHeatmapBuffer implements Listenable {
  /// Number of rows in the heatmap grid.
  final int rows;

  /// Number of columns in the heatmap grid.
  final int cols;

  final Float32List _cells;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroHeatmapBuffer] with dimensions `[rows] x [cols]`.
  ZeroHeatmapBuffer({
    this.rows = 8,
    this.cols = 16,
  }) : _cells = Float32List((rows > 0 ? rows : 1) * (cols > 0 ? cols : 1));

  /// Whether this buffer has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Total number of cells (`rows * cols`), or `0` if disposed.
  int get length => _isDisposed ? 0 : _cells.length;

  /// Returns the normalized value (`0.0..1.0`) at `(row, col)`, or `0.0` if disposed/out of bounds.
  double cellAt(int row, int col) {
    if (_isDisposed) return 0.0;
    if (row < 0 || row >= rows || col < 0 || col >= cols) return 0.0;
    return _cells[row * cols + col];
  }

  /// Sets the cell at `(row, col)` to [value] (clamped to `0.0..1.0`) and notifies listeners.
  void setCell(int row, int col, double value) {
    if (_isDisposed) return;
    if (row < 0 || row >= rows || col < 0 || col >= cols) return;
    _cells[row * cols + col] = _clampUnit(value);
    _revision.add(1);
  }

  /// Bulk-updates the heatmap matrix from [values] and notifies listeners once.
  void updateAll(List<double> values) {
    if (_isDisposed) return;
    final int total = _cells.length;
    final int srcLen = values.length;
    for (int i = 0; i < total; i++) {
      final double v = i < srcLen ? values[i] : 0.0;
      _cells[i] = _clampUnit(v);
    }
    _revision.add(1);
  }

  /// Resets all cells to `0.0`.
  void clear() {
    if (_isDisposed) return;
    _cells.fillRange(0, _cells.length, 0.0);
    _revision.add(1);
  }

  static double _clampUnit(double value) {
    if (value.isNaN || value <= 0.0) return 0.0;
    if (value >= 1.0) return 1.0;
    return value;
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

  /// Disposes this buffer and releases all listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _cells.fillRange(0, _cells.length, 0.0);
    _revision.dispose();
  }
}

/// Legacy deprecated alias for [ZHeatmap].
@Deprecated('Use ZHeatmap instead.')
typedef ZeroHeatmap = ZHeatmap;

/// A zero-allocation 2D density/intensity heatmap widget that pre-bakes a quantized
/// palette of [Paint] buckets at initialization so `paintZero` allocates zero [Color]
/// or [Paint] objects per frame.
class ZHeatmap extends ZLeafWidget<RenderZHeatmap> {
  /// Backing 2D cell buffer.
  final ZeroHeatmapBuffer buffer;

  /// Color for minimum intensity (`0.0`).
  final Color lowColor;

  /// Color for maximum intensity (`1.0`).
  final Color highColor;

  /// Gap between adjacent cells in logical pixels.
  final double cellSpacing;

  /// Fallback size when unconstrained.
  final Size preferredSize;

  /// Creates a const [ZHeatmap].
  const ZHeatmap({
    super.key,
    required this.buffer,
    this.lowColor = const Color(0xFF0D1B2A),
    this.highColor = const Color(0xFF00F5D4),
    this.cellSpacing = 1.0,
    this.preferredSize = const Size(240.0, 120.0),
  });

  @override
  RenderZHeatmap createRenderObject(BuildContext context) {
    return RenderZHeatmap(
      buffer: buffer,
      lowColor: lowColor,
      highColor: highColor,
      cellSpacing: cellSpacing,
      preferredSize: preferredSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZHeatmap renderObject) {
    renderObject
      ..buffer = buffer
      ..lowColor = lowColor
      ..highColor = highColor
      ..cellSpacing = cellSpacing
      ..preferredSize = preferredSize;
  }
}

/// Direct-to-Canvas [ZeroRenderBox] for [ZHeatmap].
class RenderZHeatmap extends ZeroRenderBox {
  static const int _paletteSize = 32;

  ZeroHeatmapBuffer _buffer;
  Color _lowColor;
  Color _highColor;
  double _cellSpacing;
  Size _preferredSize;

  final List<Paint> _palette = List<Paint>.generate(
    _paletteSize,
    (_) => Paint()..style = PaintingStyle.fill,
    growable: false,
  );

  /// Creates a [RenderZHeatmap].
  RenderZHeatmap({
    required ZeroHeatmapBuffer buffer,
    required Color lowColor,
    required Color highColor,
    required double cellSpacing,
    required Size preferredSize,
  })  : _buffer = buffer,
        _lowColor = lowColor,
        _highColor = highColor,
        _cellSpacing = cellSpacing,
        _preferredSize = preferredSize {
    _rebuildPalette();
  }

  void _rebuildPalette() {
    for (int i = 0; i < _paletteSize; i++) {
      final double t = i / (_paletteSize - 1);
      _palette[i].color = Color.lerp(_lowColor, _highColor, t) ?? _lowColor;
    }
  }

  /// Active heatmap buffer.
  ZeroHeatmapBuffer get buffer => _buffer;
  set buffer(ZeroHeatmapBuffer value) {
    if (identical(_buffer, value)) return;
    if (attached) {
      _buffer.removeListener(markDirty);
    }
    _buffer = value;
    if (attached) {
      _buffer.addListener(markDirty);
    }
    markDirty();
  }

  /// Color for minimum intensity (`0.0`).
  Color get lowColor => _lowColor;
  set lowColor(Color value) {
    if (_lowColor == value) return;
    _lowColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Color for maximum intensity (`1.0`).
  Color get highColor => _highColor;
  set highColor(Color value) {
    if (_highColor == value) return;
    _highColor = value;
    _rebuildPalette();
    markDirty();
  }

  /// Spacing between cells in logical pixels.
  double get cellSpacing => _cellSpacing;
  set cellSpacing(double value) {
    if (_cellSpacing == value) return;
    _cellSpacing = value;
    markDirty();
  }

  /// Fallback size when unconstrained.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _buffer.addListener(markDirty);
  }

  @override
  void detach() {
    _buffer.removeListener(markDirty);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.constrain(_preferredSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    if (_buffer.isDisposed) return;
    final int rCount = _buffer.rows;
    final int cCount = _buffer.cols;
    final double w = size.width;
    final double h = size.height;
    if (rCount <= 0 || cCount <= 0 || w <= 0.0 || h <= 0.0) return;

    final double slotW = w / cCount;
    final double slotH = h / rCount;
    final double cellW = (slotW - _cellSpacing).clamp(1.0, slotW);
    final double cellH = (slotH - _cellSpacing).clamp(1.0, slotH);

    for (int r = 0; r < rCount; r++) {
      final double y = offset.dy + r * slotH;
      _paintRow(context.canvas, offset.dx, y, r, cCount, slotW, cellW, cellH);
    }
  }

  void _paintRow(
    Canvas canvas,
    double startX,
    double y,
    int row,
    int colCount,
    double slotW,
    double cellW,
    double cellH,
  ) {
    for (int c = 0; c < colCount; c++) {
      final double val = _buffer.cellAt(row, c);
      final int bucket = (val * (_paletteSize - 1)).round().clamp(0, _paletteSize - 1);
      final double x = startX + c * slotW;
      canvas.drawRect(Rect.fromLTWH(x, y, cellW, cellH), _palette[bucket]);
    }
  }
}

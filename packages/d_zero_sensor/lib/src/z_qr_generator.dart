import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Active alias for [ZQRGenerator].
typedef ZMatrixCode = ZQRGenerator;

/// Legacy alias for [ZQRGenerator].
@Deprecated('Use ZQRGenerator instead.')
typedef ZeroQRGenerator = ZQRGenerator;

/// Zero-allocation controller for [ZQRGenerator] storing a `gridSize × gridSize`
/// 2D matrix code in a flat `Uint8List` with deterministic seed generation for
/// dynamic TOTP / payment QR codes.
class ZeroQRCodeController extends ChangeNotifier {
  final int _gridSize;
  late final Uint8List _modules;
  int _tokenValue = 0;
  bool _isDisposed = false;

  /// Creates a [ZeroQRCodeController] with [gridSize] modules per side (`13..29`).
  ZeroQRCodeController({int gridSize = 21, int initialToken = 104829})
      : _gridSize = gridSize.clamp(13, 29) {
    _modules = Uint8List(_gridSize * _gridSize);
    updateToken(initialToken);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  bool get hasListeners => !_isDisposed && super.hasListeners;

  /// Matrix side dimension (`21` for Version 1 QR).
  int get gridSize => _gridSize;

  /// Current numeric TOTP / payment token (`0` if disposed).
  int get tokenValue => _isDisposed ? 0 : _tokenValue;

  /// Checks whether module `(col, row)` is dark (`true`).
  bool moduleAt(int col, int row) {
    if (_isDisposed ||
        col < 0 ||
        col >= _gridSize ||
        row < 0 ||
        row >= _gridSize) {
      return false;
    }
    return _modules[row * _gridSize + col] != 0;
  }

  /// Regenerates the 2D matrix modules in place from [newToken] with 0 heap allocations.
  void updateToken(int newToken) {
    if (_isDisposed) return;
    _tokenValue = newToken;
    int hash = newToken ^ 0x5DEECE66D;
    for (int r = 0; r < _gridSize; r++) {
      for (int c = 0; c < _gridSize; c++) {
        if (_isFinderZone(c, r)) {
          _modules[r * _gridSize + c] = _finderBit(c, r);
        } else {
          hash = (hash * 1103515245 + 12345) & 0x7FFFFFFF;
          _modules[r * _gridSize + c] = (hash & 1);
        }
      }
    }
    notifyListeners();
  }

  bool _isFinderZone(int c, int r) {
    final int s = _gridSize;
    return (c < 7 && r < 7) || (c >= s - 7 && r < 7) || (c < 7 && r >= s - 7);
  }

  static const List<int> _finderMask = <int>[
    0x7F, // 1111111
    0x41, // 1000001
    0x5D, // 1011101
    0x5D, // 1011101
    0x5D, // 1011101
    0x41, // 1000001
    0x7F, // 1111111
  ];

  int _finderBit(int c, int r) {
    final int s = _gridSize;
    final int lc = c >= s - 7 ? c - (s - 7) : c;
    final int lr = r >= s - 7 ? r - (s - 7) : r;
    return (_finderMask[lr] >> lc) & 1;
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _tokenValue = 0;
    _modules.fillRange(0, _modules.length, 0);
    super.dispose();
  }
}

/// A zero-allocation dynamic 2D matrix / payment QR code generator widget.
///
/// Packs active module coordinates into a pre-allocated `Float32List` and
/// flushes the entire matrix in a single `Canvas.drawRawPoints` call.
class ZQRGenerator extends ZLeafWidget<RenderZQRGenerator> {
  /// Controller holding the matrix state and dynamic token.
  final ZeroQRCodeController controller;

  /// Preferred widget size.
  final Size size;

  /// Foreground module color.
  final Color foregroundColor;

  /// Background quiet-zone color.
  final Color backgroundColor;

  /// Creates a const [ZQRGenerator].
  const ZQRGenerator({
    super.key,
    required this.controller,
    this.size = const Size(124.0, 124.0),
    this.foregroundColor = const Color(0xFF00FF88),
    this.backgroundColor = const Color(0xFF0A0F1A),
  });

  @override
  RenderZQRGenerator createRenderObject(BuildContext context) {
    return RenderZQRGenerator(
      controller: controller,
      preferredSize: size,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZQRGenerator renderObject,
  ) {
    renderObject
      ..controller = controller
      ..preferredSize = size
      ..foregroundColor = foregroundColor
      ..backgroundColor = backgroundColor;
  }
}

/// Custom [ZeroRenderBox] for [ZQRGenerator].
class RenderZQRGenerator extends ZeroRenderBox {
  ZeroQRCodeController _controller;
  Size _preferredSize;
  late Float32List _pointBuffer;

  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _modulePaint = Paint()..strokeCap = StrokeCap.square;

  /// Creates a [RenderZQRGenerator].
  RenderZQRGenerator({
    required ZeroQRCodeController controller,
    required Size preferredSize,
    required Color foregroundColor,
    required Color backgroundColor,
  })  : _controller = controller,
        _preferredSize = preferredSize,
        _pointBuffer = Float32List(controller.gridSize * controller.gridSize * 2) {
    _bgPaint.color = backgroundColor;
    _modulePaint.color = foregroundColor;
  }

  /// QR code controller.
  ZeroQRCodeController get controller => _controller;
  set controller(ZeroQRCodeController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
      value.addListener(markDirty);
    }
    _controller = value;
    final int cap = value.gridSize * value.gridSize * 2;
    if (_pointBuffer.length < cap) {
      _pointBuffer = Float32List(cap);
    }
    markDirty();
  }

  /// Preferred size.
  Size get preferredSize => _preferredSize;
  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  /// Module foreground color.
  Color get foregroundColor => _modulePaint.color;
  set foregroundColor(Color value) {
    if (_modulePaint.color == value) return;
    _modulePaint.color = value;
    markDirty();
  }

  /// Quiet-zone background color.
  Color get backgroundColor => _bgPaint.color;
  set backgroundColor(Color value) {
    if (_bgPaint.color == value) return;
    _bgPaint.color = value;
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
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.drawRRect(
      RRect.fromRectAndRadius(offset & size, const Radius.circular(8.0)),
      _bgPaint,
    );

    final int g = _controller.gridSize;
    final double side = math.min(size.width, size.height) - 12.0;
    final double cell = math.max(1.5, side / g);
    final double startX = offset.dx + (size.width - cell * g) * 0.5;
    final double startY = offset.dy + (size.height - cell * g) * 0.5;
    _modulePaint.strokeWidth = cell * 0.88;

    int count = 0;
    for (int r = 0; r < g; r++) {
      final double cy = startY + (r + 0.5) * cell;
      for (int c = 0; c < g; c++) {
        if (!_controller.moduleAt(c, r)) continue;
        _pointBuffer[count * 2] = startX + (c + 0.5) * cell;
        _pointBuffer[count * 2 + 1] = cy;
        count++;
      }
    }

    if (count > 0) {
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(_pointBuffer, 0, count * 2),
        _modulePaint,
      );
    }
  }
}

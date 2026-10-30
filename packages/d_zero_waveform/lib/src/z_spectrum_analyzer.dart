import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';

/// Zero-allocation controller for FFT spectrum analyzer frequency bins (`0.0` to `1.0`)
/// and gravity-decayed peak-hold indicators.
class ZeroSpectrumController implements Listenable {
  /// Maximum allowed frequency bins to prevent uncontrolled allocation (CWE-789).
  static const int maxBinCount = 4096;

  /// Number of frequency bins managed by this controller.
  final int binCount;

  /// Gravity decay rate subtracted from peak-hold indicators on each update.
  final double peakDecayPerStep;

  final Float32List _bins;
  final Float32List _peakHolds;
  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  /// Creates a [ZeroSpectrumController] with [binCount] frequency bands.
  ZeroSpectrumController({
    int binCount = 32,
    this.peakDecayPerStep = 0.015,
  })  : binCount = binCount.clamp(1, maxBinCount),
        _bins = Float32List(binCount.clamp(1, maxBinCount)),
        _peakHolds = Float32List(binCount.clamp(1, maxBinCount));

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Direct read view of current frequency bin magnitudes (`0.0..1.0`).
  Float32List get bins => _bins;

  /// Direct read view of current peak-hold magnitudes (`0.0..1.0`).
  Float32List get peakHolds => _peakHolds;

  /// Returns the normalized magnitude for bin [index], or `0.0` if disposed/out of range.
  double binAt(int index) {
    if (_isDisposed) return 0.0;
    if (index < 0 || index >= _bins.length) return 0.0;
    return _bins[index];
  }

  /// Returns the peak-hold magnitude for bin [index], or `0.0` if disposed/out of range.
  double peakAt(int index) {
    if (_isDisposed) return 0.0;
    if (index < 0 || index >= _peakHolds.length) return 0.0;
    return _peakHolds[index];
  }

  /// Updates the frequency bins from [newBins], applies gravity decay to peak-holds,
  /// and notifies listeners without allocating any heap memory.
  void updateBins(List<double> newBins) {
    if (_isDisposed) return;
    final int total = _bins.length;
    final int srcLen = newBins.length;
    for (int i = 0; i < total; i++) {
      final double raw = i < srcLen ? newBins[i] : 0.0;
      final double val = _clampUnit(raw);
      _bins[i] = val;
      _updatePeakAt(i, val);
    }
    _revision.add(1);
  }

  void _updatePeakAt(int index, double currentVal) {
    final double decayed = _peakHolds[index] - peakDecayPerStep;
    final double nextPeak = decayed > 0.0 ? decayed : 0.0;
    _peakHolds[index] = currentVal >= nextPeak ? currentVal : nextPeak;
  }

  /// Applies one step of gravity decay across all bins and peak-holds.
  void decayStep([double? customDecay]) {
    if (_isDisposed) return;
    final double rawStep = customDecay ?? peakDecayPerStep;
    final double step = (!rawStep.isFinite || rawStep < 0.0) ? 0.0 : rawStep;
    for (int i = 0; i < _bins.length; i++) {
      final double b = _bins[i] - step;
      final double p = _peakHolds[i] - step * 0.5;
      _bins[i] = b > 0.0 ? b : 0.0;
      _peakHolds[i] = p > 0.0 ? p : 0.0;
    }
    _revision.add(1);
  }

  /// Resets all frequency bins and peak-holds to zero.
  void clear() {
    if (_isDisposed) return;
    _bins.fillRange(0, _bins.length, 0.0);
    _peakHolds.fillRange(0, _peakHolds.length, 0.0);
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

  /// Disposes this controller and releases all listeners (idempotent).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _bins.fillRange(0, _bins.length, 0.0);
    _peakHolds.fillRange(0, _peakHolds.length, 0.0);
    _revision.dispose();
  }
}

/// Legacy deprecated alias for [ZSpectrumAnalyzer].
@Deprecated('Use ZSpectrumAnalyzer instead.')
typedef ZeroSpectrumAnalyzer = ZSpectrumAnalyzer;

/// A zero-allocation FFT spectrum analyzer widget that renders frequency bars
/// and peak-hold indicators directly onto the Canvas inside a [ZeroRenderBox].
class ZSpectrumAnalyzer extends ZLeafWidget<RenderZSpectrumAnalyzer> {
  /// Controller supplying FFT bin magnitudes and peak-holds.
  final ZeroSpectrumController controller;

  /// Color of the main frequency bars.
  final Color barColor;

  /// Color of the floating peak-hold caps.
  final Color peakColor;

  /// Optional background color.
  final Color? backgroundColor;

  /// Horizontal gap between adjacent bars in logical pixels.
  final double barSpacing;

  /// Whether to render peak-hold cap lines above each bar.
  final bool showPeaks;

  /// Fallback size when unconstrained.
  final Size preferredSize;

  /// Creates a const [ZSpectrumAnalyzer].
  const ZSpectrumAnalyzer({
    super.key,
    required this.controller,
    this.barColor = const Color(0xFF00B0FF),
    this.peakColor = const Color(0xFFFFD740),
    this.backgroundColor,
    this.barSpacing = 2.0,
    this.showPeaks = true,
    this.preferredSize = const Size(240.0, 96.0),
  });

  @override
  RenderZSpectrumAnalyzer createRenderObject(BuildContext context) {
    return RenderZSpectrumAnalyzer(
      controller: controller,
      barColor: barColor,
      peakColor: peakColor,
      backgroundColor: backgroundColor,
      barSpacing: barSpacing,
      showPeaks: showPeaks,
      preferredSize: preferredSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderZSpectrumAnalyzer renderObject) {
    renderObject
      ..controller = controller
      ..barColor = barColor
      ..peakColor = peakColor
      ..backgroundColor = backgroundColor
      ..barSpacing = barSpacing
      ..showPeaks = showPeaks
      ..preferredSize = preferredSize;
  }
}

/// Direct-to-Canvas [ZeroRenderBox] for [ZSpectrumAnalyzer].
class RenderZSpectrumAnalyzer extends ZeroRenderBox {
  ZeroSpectrumController _controller;
  Color _barColor;
  Color _peakColor;
  Color? _backgroundColor;
  double _barSpacing;
  bool _showPeaks;
  Size _preferredSize;

  final Paint _barPaint = Paint()..style = PaintingStyle.fill;
  final Paint _peakPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  late Float32List _peakSegments;

  /// Creates a [RenderZSpectrumAnalyzer].
  RenderZSpectrumAnalyzer({
    required ZeroSpectrumController controller,
    required Color barColor,
    required Color peakColor,
    required Color? backgroundColor,
    required double barSpacing,
    required bool showPeaks,
    required Size preferredSize,
  })  : _controller = controller,
        _barColor = barColor,
        _peakColor = peakColor,
        _backgroundColor = backgroundColor,
        _barSpacing = barSpacing,
        _showPeaks = showPeaks,
        _preferredSize = preferredSize {
    _barPaint.color = barColor;
    _peakPaint.color = peakColor;
    if (backgroundColor != null) {
      _bgPaint.color = backgroundColor;
    }
    _peakSegments = Float32List(controller.binCount * 4);
  }

  /// Active spectrum controller.
  ZeroSpectrumController get controller => _controller;
  set controller(ZeroSpectrumController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _controller.removeListener(markDirty);
    }
    _controller = value;
    if (_peakSegments.length != value.binCount * 4) {
      _peakSegments = Float32List(value.binCount * 4);
    }
    if (attached) {
      _controller.addListener(markDirty);
    }
    markDirty();
  }

  /// Frequency bar fill color.
  Color get barColor => _barColor;
  set barColor(Color value) {
    if (_barColor == value) return;
    _barColor = value;
    _barPaint.color = value;
    markDirty();
  }

  /// Peak-hold indicator color.
  Color get peakColor => _peakColor;
  set peakColor(Color value) {
    if (_peakColor == value) return;
    _peakColor = value;
    _peakPaint.color = value;
    markDirty();
  }

  /// Optional background color.
  Color? get backgroundColor => _backgroundColor;
  set backgroundColor(Color? value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    if (value != null) {
      _bgPaint.color = value;
    }
    markDirty();
  }

  /// Horizontal spacing between bars.
  double get barSpacing => _barSpacing;
  set barSpacing(double value) {
    if (_barSpacing == value) return;
    _barSpacing = value;
    markDirty();
  }

  /// Whether to render peak-hold cap lines.
  bool get showPeaks => _showPeaks;
  set showPeaks(bool value) {
    if (_showPeaks == value) return;
    _showPeaks = value;
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
    _controller.addListener(markDirty);
  }

  @override
  void detach() {
    _controller.removeListener(markDirty);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.constrain(_preferredSize);
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final double w = size.width;
    final double h = size.height;
    if (w <= 0.0 || h <= 0.0) return;

    if (_backgroundColor != null) {
      canvas.drawRect(offset & size, _bgPaint);
    }
    if (_controller.isDisposed) return;

    final int count = _controller.binCount;
    if (count <= 0) return;

    final double totalSlotW = w / count;
    final double barW = (totalSlotW - _barSpacing).clamp(1.0, totalSlotW);
    final double bottomY = offset.dy + h;

    _paintBarsAndStagePeaks(canvas, offset.dx, bottomY, h, count, totalSlotW, barW);
    if (_showPeaks) {
      canvas.drawRawPoints(ui.PointMode.lines, _peakSegments, _peakPaint);
    }
  }

  void _paintBarsAndStagePeaks(
    Canvas canvas,
    double startX,
    double bottomY,
    double maxHeight,
    int count,
    double slotW,
    double barW,
  ) {
    for (int i = 0; i < count; i++) {
      final double x = startX + i * slotW;
      final double mag = _controller.binAt(i);
      final double barH = mag * maxHeight;
      if (barH > 0.5) {
        canvas.drawRect(Rect.fromLTWH(x, bottomY - barH, barW, barH), _barPaint);
      }
      final int pIdx = i << 2;
      final double peakY = (bottomY - _controller.peakAt(i) * maxHeight).clamp(
        bottomY - maxHeight + 1.0,
        bottomY - 1.0,
      );
      _peakSegments[pIdx] = x;
      _peakSegments[pIdx + 1] = peakY;
      _peakSegments[pIdx + 2] = x + barW;
      _peakSegments[pIdx + 3] = peakY;
    }
  }
}

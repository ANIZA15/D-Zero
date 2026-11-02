import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_sensor/d_zero_sensor.dart';

/// UI & Native pipeline mode for the live camera QR scanner.
enum QrCameraEngineMode {
  /// D-Zero C++17 Seqlock Shared Memory (`ZeroCameraController` + `ZCameraScanner` + `ZCounter`).
  dZero,

  /// Traditional Flutter pipeline (`setState` + `Stack`/`Positioned` + `Text`).
  traditional,
}

/// Simple ToDo-style scanned QR record.
class ScannedQrItem {
  final int index;
  final String text;
  final bool isDZero;
  bool done;

  ScannedQrItem({
    required this.index,
    required this.text,
    required this.isDZero,
    this.done = true,
  });
}

/// Clean, ToDo-app style live camera QR scanner with a one-tap toggle
/// between **D-Zero** and **Traditional (`従来`)**.
class LiveCameraQrView extends StatefulWidget {
  /// Whether to mount the native platform [MobileScanner] preview.
  final bool enablePlatformCamera;

  const LiveCameraQrView({
    super.key,
    this.enablePlatformCamera = true,
  });

  @override
  State<LiveCameraQrView> createState() => LiveCameraQrViewState();
}

class LiveCameraQrViewState extends State<LiveCameraQrView>
    implements ZeroSlottedFrameListener {
  static const int targetQrCount = 1000;
  static const Size viewportSize = Size(320.0, 220.0);

  QrCameraEngineMode _engineMode = QrCameraEngineMode.dZero;
  bool _isScanning = true;
  int _schedulerSlot = -1;

  MobileScannerController? _cameraController;
  final Stopwatch _sessionTimer = Stopwatch();

  late final ZeroCameraController _zeroCamCtrl;
  late final Uint8List _syntheticLumaFrame;
  final ZeroIntNotifier _scanCount = ZeroIntNotifier(0);
  final ZeroDoubleNotifier _elapsedSec = ZeroDoubleNotifier(0.0);

  final List<Rect> _tradBoxes = <Rect>[];
  final List<ScannedQrItem> _recentItems = <ScannedQrItem>[];
  int _dZeroRebuilds = 0;
  int _tradRebuilds = 0;
  bool _resettingMode = true;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _zeroCamCtrl = ZeroCameraController();
    _syntheticLumaFrame = _buildHighContrastLumaFrame(320, 240);
    if (widget.enablePlatformCamera) {
      _cameraController = MobileScannerController(
        detectionSpeed: DetectionSpeed.unrestricted,
        facing: CameraFacing.back,
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
        returnImage: false,
      );
    }
    ZeroFrameScheduler.instance.subscribe(this);
  }

  static Uint8List _buildHighContrastLumaFrame(int w, int h) {
    final Uint8List buf = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      final int row = y * w;
      for (int x = 0; x < w; x++) {
        buf[row + x] = ((x ~/ 8 + y ~/ 8) & 1) == 0 ? 16 : 240;
      }
    }
    return buf;
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _cameraController?.dispose();
    _zeroCamCtrl.dispose();
    _scanCount.dispose();
    _elapsedSec.dispose();
    super.dispose();
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    if (_sessionTimer.isRunning && _scanCount.value < targetQrCount) {
      _elapsedSec.value = _sessionTimer.elapsedMicroseconds / 1000000.0;
      if (_engineMode == QrCameraEngineMode.traditional) {
        setState(() {});
      }
    }
  }

  /// Processes a live camera [BarcodeCapture] frame.
  void handleBarcodeCapture(BarcodeCapture capture) {
    if (!_isScanning || capture.barcodes.isEmpty) return;
    if (_scanCount.value >= targetQrCount) return;

    final List<Barcode> codes = capture.barcodes;
    final Barcode primary = codes.first;
    final String raw = primary.rawValue ?? primary.displayValue ?? 'QR_CODE';

    if (!_sessionTimer.isRunning) {
      _sessionTimer.start();
    }

    if (_engineMode == QrCameraEngineMode.dZero) {
      _processDZeroDetection(codes, capture.size, raw);
    } else {
      _processTraditionalDetection(codes, capture.size, raw);
    }
  }

  void _processDZeroDetection(
    List<Barcode> codes,
    Size sourceSize,
    String raw,
  ) {
    _zeroCamCtrl.beginDetectionBatch();
    final int limit = math.min(codes.length, ZeroCameraStateView.maxDetections);
    for (int i = 0; i < limit; i++) {
      final Rect box = _mapBarcodeRect(codes[i], sourceSize);
      _zeroCamCtrl.setBatchDetectionBox(
        i,
        box.left,
        box.top,
        box.right,
        box.bottom,
        99.0,
      );
    }
    _zeroCamCtrl.commitDetectionBatch(payload: raw, decodeMicros: 8);

    final int next = math.min(targetQrCount, _scanCount.value + 1);
    _scanCount.value = next;
    _elapsedSec.value = _sessionTimer.elapsedMicroseconds / 1000000.0;

    if (next >= targetQrCount) {
      _sessionTimer.stop();
    }
  }

  void _processTraditionalDetection(
    List<Barcode> codes,
    Size sourceSize,
    String raw,
  ) {
    _tradBoxes.clear();
    for (int i = 0; i < codes.length; i++) {
      _tradBoxes.add(_mapBarcodeRect(codes[i], sourceSize));
    }
    final int next = math.min(targetQrCount, _scanCount.value + 1);
    _scanCount.value = next;
    _elapsedSec.value = _sessionTimer.elapsedMicroseconds / 1000000.0;
    _pushHistoryItem(next, raw, isDZero: false);

    if (next >= targetQrCount) {
      _sessionTimer.stop();
    }
    setState(() {});
  }

  void _pushHistoryItem(int index, String raw, {required bool isDZero}) {
    if (_recentItems.isEmpty || _recentItems.first.text != raw) {
      _recentItems.insert(
        0,
        ScannedQrItem(index: index, text: raw, isDZero: isDZero),
      );
      if (_recentItems.length > 6) {
        _recentItems.removeLast();
      }
    }
  }

  Rect _mapBarcodeRect(Barcode code, Size sourceSize) {
    final List<Offset> corners = code.corners;
    if (corners.length < 4 ||
        sourceSize.width <= 0.0 ||
        sourceSize.height <= 0.0) {
      return const Rect.fromLTWH(80.0, 40.0, 160.0, 140.0);
    }
    double minX = corners.first.dx;
    double maxX = corners.first.dx;
    double minY = corners.first.dy;
    double maxY = corners.first.dy;
    for (int i = 1; i < corners.length; i++) {
      final Offset p = corners[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final double sx = viewportSize.width / sourceSize.width;
    final double sy = viewportSize.height / sourceSize.height;
    return Rect.fromLTRB(
      (minX * sx).clamp(8.0, viewportSize.width - 24.0),
      (minY * sy).clamp(8.0, viewportSize.height - 24.0),
      (maxX * sx).clamp(24.0, viewportSize.width - 8.0),
      (maxY * sy).clamp(24.0, viewportSize.height - 8.0),
    );
  }

  /// Simulates a single QR scan frame for desktop / widget testing.
  void simulateQrFrame() {
    final int idx = _scanCount.value + 1;
    _syntheticLumaFrame[idx % _syntheticLumaFrame.length] = (idx * 73) & 0xFF;
    if (_engineMode == QrCameraEngineMode.dZero) {
      if (!_sessionTimer.isRunning && _scanCount.value < targetQrCount) {
        _sessionTimer.start();
      }
      _zeroCamCtrl.scanLumaPlaneZeroCopy(
        _syntheticLumaFrame,
        width: 320,
        height: 240,
      );
      final int next = math.min(targetQrCount, _scanCount.value + 1);
      _scanCount.value = next;
      _elapsedSec.value = _sessionTimer.elapsedMicroseconds / 1000000.0;
      if (next >= targetQrCount) {
        _sessionTimer.stop();
      }
      return;
    }

    final Barcode synthetic = Barcode(
      rawValue: 'https://d-zero.dev/todo/$idx',
      format: BarcodeFormat.qrCode,
      corners: const <Offset>[
        Offset(180.0, 110.0),
        Offset(460.0, 110.0),
        Offset(460.0, 370.0),
        Offset(180.0, 370.0),
      ],
    );
    handleBarcodeCapture(
      BarcodeCapture(
        barcodes: <Barcode>[synthetic],
        size: const Size(640.0, 480.0),
      ),
    );
  }

  void _toggleStartStop() {
    setState(() {
      _resettingMode = true;
      _isScanning = !_isScanning;
      if (_isScanning) {
        _cameraController?.start();
      } else {
        _sessionTimer.stop();
        _cameraController?.stop();
      }
    });
  }

  void _resetSession() {
    _sessionTimer
      ..stop()
      ..reset();
    _zeroCamCtrl.resetCounters();
    _tradBoxes.clear();
    _scanCount.value = 0;
    _elapsedSec.value = 0.0;
    setState(() {
      _resettingMode = true;
      _recentItems.clear();
      _dZeroRebuilds = 0;
      _tradRebuilds = 0;
      _isScanning = true;
    });
  }

  void _recordRebuild(bool isDZero) {
    if (_resettingMode) {
      _resettingMode = false;
      return;
    }
    if (isDZero) {
      _dZeroRebuilds++;
    } else {
      _tradRebuilds++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _engineMode == QrCameraEngineMode.dZero;
    _recordRebuild(isDZero);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildModeSwitchBar(),
        const SizedBox(height: 16),
        _buildSimpleScannerCard(isDZero),
        const SizedBox(height: 12),
        _buildActionButtonsRow(),
        const SizedBox(height: 20),
        _buildTodoStyleHistorySection(),
      ],
    );
  }

  Widget _buildModeSwitchBar() {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<QrCameraEngineMode>(
            segments: const [
              ButtonSegment(
                value: QrCameraEngineMode.dZero,
                label: Text('D-Zero'),
                icon: Icon(Icons.bolt, size: 18),
              ),
              ButtonSegment(
                value: QrCameraEngineMode.traditional,
                label: Text('従来'),
                icon: Icon(Icons.smartphone, size: 18),
              ),
            ],
            selected: {_engineMode},
            onSelectionChanged: (s) => setState(() {
              _engineMode = s.first;
              _resettingMode = true;
            }),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'カメラ切替',
          onPressed: () => _cameraController?.switchCamera(),
          icon: const Icon(Icons.cameraswitch_outlined),
        ),
      ],
    );
  }

  Widget _buildSimpleScannerCard(bool isDZero) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    isDZero
                        ? 'D-Zero Live Scanner'
                        : 'Traditional Flutter Scanner',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDZero
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Rebuild: ${isDZero ? _dZeroRebuilds : _tradRebuilds}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDZero
                          ? const Color(0xFF15803D)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCameraViewport(isDZero),
            const SizedBox(height: 16),
            _buildCounterSummaryRow(isDZero),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraViewport(bool isDZero) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: viewportSize.width,
        height: viewportSize.height,
        child: isDZero
            ? ZCameraScanner(
                controller: _zeroCamCtrl,
                size: viewportSize,
                backgroundColor: const Color(0x00000000),
                reticleColor: const Color(0xFF2563EB),
                detectionColor: const Color(0xFF16A34A),
                isScanning: _isScanning,
                showTelemetryHud: false,
                child: _buildCameraFeedLayer(),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  _buildCameraFeedLayer(),
                  _buildTraditionalOverlayLayer(),
                ],
              ),
      ),
    );
  }

  Widget _buildCameraFeedLayer() {
    final MobileScannerController? ctrl = _cameraController;
    if (!widget.enablePlatformCamera || ctrl == null) {
      return Container(
        color: const Color(0xFFF1F5F9),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_scanner,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
            SizedBox(height: 8),
            Text(
              'カメラプレビュー',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }
    return MobileScanner(
      controller: ctrl,
      fit: BoxFit.cover,
      onDetect: handleBarcodeCapture,
      errorBuilder: (context, error) {
        return Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: const Text(
            'カメラの権限を許可するか、「+1 テスト読取」を押してください',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        );
      },
    );
  }

  Widget _buildTraditionalOverlayLayer() {
    return Stack(
      children: [
        for (int i = 0; i < _tradBoxes.length; i++)
          Positioned(
            left: _tradBoxes[i].left,
            top: _tradBoxes[i].top,
            width: (_tradBoxes[i].width).clamp(24.0, 280.0),
            height: (_tradBoxes[i].height).clamp(24.0, 200.0),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF2563EB), width: 2.0),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCounterSummaryRow(bool isDZero) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Column(
          children: [
            const Text(
              '読み取り数',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 36,
              child: Center(
                child: isDZero
                    ? ZCounter(
                        valueListenable: _scanCount,
                        minDigits: 1,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      )
                    : Text(
                        '${_scanCount.value}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
              ),
            ),
          ],
        ),
        Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
        Column(
          children: [
            const Text(
              '経過時間 (秒)',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 84,
              height: 36,
              child: Center(
                child: isDZero
                    ? ZPriceTicker(
                        valueListenable: _elapsedSec,
                        currencyGlyph: ZeroNumberPainter.glyphPlus,
                        fractionDigits: 2,
                        thousandsSeparator: false,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      )
                    : Text(
                        '+${_elapsedSec.value.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtonsRow() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('live_camera_sim_btn'),
            onPressed: simulateQrFrame,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('テスト読取'),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _toggleStartStop,
          child: Text(_isScanning ? '一時停止' : '再開'),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _resetSession,
          child: const Text('クリア'),
        ),
      ],
    );
  }

  Widget _buildTodoStyleHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '読み取り履歴',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_recentItems.isEmpty)
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'まだ読み取られたQRコードはありません',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
              ),
            ),
          )
        else
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < _recentItems.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  _buildTodoListTile(_recentItems[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTodoListTile(ScannedQrItem item) {
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: item.done,
        onChanged: (v) => setState(() => item.done = v ?? true),
      ),
      title: Text(
        item.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          color: const Color(0xFF1E293B),
          decoration: item.done ? null : TextDecoration.lineThrough,
        ),
      ),
      trailing: Text(
        item.isDZero ? 'D-Zero #${item.index}' : '従来 #${item.index}',
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
      ),
    );
  }
}

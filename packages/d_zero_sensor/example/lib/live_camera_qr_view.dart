import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_counter/d_zero_counter.dart';
import 'package:d_zero_sensor/d_zero_sensor.dart';

/// UI & Native pipeline mode for the live camera QR scanner.
enum QrCameraEngineMode {
  /// D-Zero Native `AVCaptureVideoDataOutput` YUV420 Plane 0 pointer -> C++17 Seqlock Shared Memory.
  dZero,

  /// Traditional Flutter pipeline (`MobileScanner` MethodChannel + `setState`).
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
/// between **D-Zero (YUV420 Pointer -> C++ Seqlock)** and **Traditional (`従来`)**.
class LiveCameraQrView extends StatefulWidget {
  /// Whether to mount the native platform camera preview.
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
  int _lastObservedNativeSeq = 0;
  int _lastObservedPayloadHash = 0;

  MobileScannerController? _cameraController;
  final Stopwatch _sessionTimer = Stopwatch();

  late final ZeroCameraController _zeroCamCtrl;
  final ZeroIntNotifier _scanCount = ZeroIntNotifier(0);
  final ZeroDoubleNotifier _elapsedSec = ZeroDoubleNotifier(0.0);
  final ZeroIntNotifier _decodeUs = ZeroIntNotifier(0);

  final List<Rect> _tradBoxes = <Rect>[];
  final List<ScannedQrItem> _recentItems = <ScannedQrItem>[];
  int _dZeroRebuilds = 0;
  int _tradRebuilds = 0;

  @override
  int get zeroSchedulerSlot => _schedulerSlot;

  @override
  set zeroSchedulerSlot(int slot) => _schedulerSlot = slot;

  @override
  void initState() {
    super.initState();
    _zeroCamCtrl = ZeroCameraController();
    _zeroCamCtrl.acquireNativeYuvBuffer(320, 240);
    if (widget.enablePlatformCamera) {
      _initCameraPipelines();
    }
    ZeroFrameScheduler.instance.subscribe(this);
  }

  Future<void> _initCameraPipelines() async {
    final bool ok = await _zeroCamCtrl.startNativeCamera(preferredFps: 120);
    if (!mounted) return;
    if (ok) {
      setState(() {});
      return;
    }
    _ensureTraditionalController();
  }

  void _ensureTraditionalController() {
    if (_cameraController != null || !widget.enablePlatformCamera) return;
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      facing: CameraFacing.back,
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      returnImage: false,
    );
  }

  @override
  void dispose() {
    ZeroFrameScheduler.instance.unsubscribe(this);
    _cameraController?.dispose();
    _zeroCamCtrl.dispose();
    _scanCount.dispose();
    _elapsedSec.dispose();
    _decodeUs.dispose();
    super.dispose();
  }

  @override
  void onZeroFrame(Duration elapsed) {
    if (!mounted) return;
    if (_engineMode == QrCameraEngineMode.dZero) {
      _pollNativeSharedMemory();
    }
    if (_sessionTimer.isRunning && _scanCount.value < targetQrCount) {
      _elapsedSec.value = _sessionTimer.elapsedMicroseconds / 1000000.0;
      if (_engineMode == QrCameraEngineMode.traditional) {
        setState(() {});
      }
    }
  }

  void _pollNativeSharedMemory() {
    final int seq = _zeroCamCtrl.seq;
    if (seq == _lastObservedNativeSeq || (seq & 1) != 0) return;
    _lastObservedNativeSeq = seq;

    final int nativeScans = _zeroCamCtrl.scanCount;
    if (nativeScans <= 0) return;
    if (!_sessionTimer.isRunning && _scanCount.value < targetQrCount) {
      _sessionTimer.start();
    }
    final int clamped = math.min(targetQrCount, nativeScans);
    _scanCount.value = clamped;
    _decodeUs.value = _zeroCamCtrl.lastDecodeUs;
    _elapsedSec.value = _sessionTimer.elapsedMicroseconds / 1000000.0;

    final int hash = _zeroCamCtrl.lastPayloadHash;
    if (hash != 0 && hash != _lastObservedPayloadHash) {
      _lastObservedPayloadHash = hash;
    }
    if (clamped >= targetQrCount) {
      _sessionTimer.stop();
    }
  }

  /// Processes a live camera [BarcodeCapture] frame when running in Traditional mode
  /// or when falling back to [MobileScanner].
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
      _processDZeroFallbackDetection(codes, capture.size, raw);
    } else {
      _processTraditionalDetection(codes, capture.size, raw);
    }
  }

  void _processDZeroFallbackDetection(
    List<Barcode> codes,
    Size sourceSize,
    String raw,
  ) {
    final Stopwatch decodeWatch = Stopwatch()..start();
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
    decodeWatch.stop();
    final int realUs = math.max(1, decodeWatch.elapsedMicroseconds);
    _zeroCamCtrl.commitDetectionBatch(payload: raw, decodeMicros: realUs);
    _pollNativeSharedMemory();
  }

  void _processTraditionalDetection(
    List<Barcode> codes,
    Size sourceSize,
    String raw,
  ) {
    final Stopwatch decodeWatch = Stopwatch()..start();
    _tradBoxes.clear();
    for (int i = 0; i < codes.length; i++) {
      _tradBoxes.add(_mapBarcodeRect(codes[i], sourceSize));
    }
    final int next = math.min(targetQrCount, _scanCount.value + 1);
    _scanCount.value = next;
    _elapsedSec.value = _sessionTimer.elapsedMicroseconds / 1000000.0;
    _pushHistoryItem(next, raw, isDZero: false);
    decodeWatch.stop();
    _decodeUs.value = math.max(1, decodeWatch.elapsedMicroseconds);

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

  /// Feeds a single 320×240 YUV420 frame directly into the active pipeline.
  void simulateQrFrame() {
    final int idx = _scanCount.value + 1;
    if (_engineMode == QrCameraEngineMode.dZero) {
      if (!_sessionTimer.isRunning && _scanCount.value < targetQrCount) {
        _sessionTimer.start();
      }
      _zeroCamCtrl.stampAndScanNativeYuv(
        qrToken: 100000 + idx * 97,
        width: 320,
        height: 240,
      );
      _pollNativeSharedMemory();
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

  Future<void> _switchEngineMode(QrCameraEngineMode nextMode) async {
    if (_engineMode == nextMode) return;
    setState(() {
      _engineMode = nextMode;
    });
    if (!widget.enablePlatformCamera) return;
    if (nextMode == QrCameraEngineMode.dZero) {
      await _cameraController?.stop();
      await _zeroCamCtrl.startNativeCamera(preferredFps: 120);
    } else {
      await _zeroCamCtrl.stopNativeCamera();
      _ensureTraditionalController();
      await _cameraController?.start();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleStartStop() {
    setState(() {
      _isScanning = !_isScanning;
      if (_isScanning) {
        if (_engineMode == QrCameraEngineMode.dZero) {
          _zeroCamCtrl.startNativeCamera(preferredFps: 120);
        } else {
          _cameraController?.start();
        }
      } else {
        _sessionTimer.stop();
        _zeroCamCtrl.stopNativeCamera();
        _cameraController?.stop();
      }
    });
  }

  void _resetSession() {
    _sessionTimer
      ..stop()
      ..reset();
    _zeroCamCtrl.resetCounters();
    _lastObservedNativeSeq = _zeroCamCtrl.seq;
    _lastObservedPayloadHash = 0;
    _tradBoxes.clear();
    _scanCount.value = 0;
    _elapsedSec.value = 0.0;
    _decodeUs.value = 0;
    setState(() {
      _recentItems.clear();
      _dZeroRebuilds = 0;
      _tradRebuilds = 0;
      _isScanning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDZero = _engineMode == QrCameraEngineMode.dZero;
    if (isDZero) {
      _dZeroRebuilds++;
    } else {
      _tradRebuilds++;
    }
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
            onSelectionChanged: (s) => _switchEngineMode(s.first),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'カメラ切替',
          onPressed: () {
            if (_engineMode == QrCameraEngineMode.dZero &&
                _zeroCamCtrl.hasNativeTexture) {
              _zeroCamCtrl.switchNativeCamera();
            } else {
              _cameraController?.switchCamera();
            }
          },
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
                        ? 'D-Zero YUV420 Direct Scanner'
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
                child: _buildCameraFeedLayer(isDZero: true),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  _buildCameraFeedLayer(isDZero: false),
                  _buildTraditionalOverlayLayer(),
                ],
              ),
      ),
    );
  }

  Widget _buildCameraFeedLayer({required bool isDZero}) {
    if (!widget.enablePlatformCamera) {
      return _buildPlaceholderPreview();
    }
    if (isDZero && _zeroCamCtrl.hasNativeTexture) {
      return Texture(textureId: _zeroCamCtrl.textureId!);
    }
    _ensureTraditionalController();
    final MobileScannerController? ctrl = _cameraController;
    if (ctrl == null) {
      return _buildPlaceholderPreview();
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
            'カメラの権限を許可するか、「テスト読取」を押してください',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderPreview() {
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
            'カメラプレビュー (YUV420 Direct)',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      ),
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
        Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
        Column(
          children: [
            const Text(
              '解析時間 (µs)',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 36,
              child: Center(
                child: isDZero
                    ? ZCounter(
                        valueListenable: _decodeUs,
                        minDigits: 1,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A34A),
                        ),
                      )
                    : Text(
                        '${_decodeUs.value}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
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

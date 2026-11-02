import 'package:flutter/material.dart';
import 'live_camera_qr_view.dart';
import 'qr_battle_view.dart';

void main() {
  runApp(const DZeroSensorBenchmarkApp());
}

enum SensorDemoTab { liveCameraQr, qrBattle1000 }

class DZeroSensorBenchmarkApp extends StatelessWidget {
  final bool enablePlatformCamera;

  const DZeroSensorBenchmarkApp({
    super.key,
    this.enablePlatformCamera = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR スキャナー',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
        ),
      ),
      home: SensorBenchmarkScreen(enablePlatformCamera: enablePlatformCamera),
    );
  }
}

class SensorBenchmarkScreen extends StatefulWidget {
  final bool enablePlatformCamera;

  const SensorBenchmarkScreen({
    super.key,
    this.enablePlatformCamera = true,
  });

  @override
  State<SensorBenchmarkScreen> createState() => _SensorBenchmarkScreenState();
}

class _SensorBenchmarkScreenState extends State<SensorBenchmarkScreen> {
  SensorDemoTab _activeTab = SensorDemoTab.liveCameraQr;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'QR スキャナー',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<SensorDemoTab>(
                    segments: const [
                      ButtonSegment(
                        value: SensorDemoTab.liveCameraQr,
                        label: Text('📷 カメラ読取'),
                      ),
                      ButtonSegment(
                        value: SensorDemoTab.qrBattle1000,
                        label: Text('⚡ 1000 QR対決'),
                      ),
                    ],
                    selected: {_activeTab},
                    onSelectionChanged: (s) =>
                        setState(() => _activeTab = s.first),
                  ),
                  const SizedBox(height: 16),
                  _activeTab == SensorDemoTab.liveCameraQr
                      ? LiveCameraQrView(
                          enablePlatformCamera: widget.enablePlatformCamera,
                        )
                      : const QrBattleView(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

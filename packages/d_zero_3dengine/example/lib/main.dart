import 'package:flutter/material.dart';
import 'package:d_zero_3dengine/d_zero_3dengine.dart';

void main() {
  runApp(const DZero3DEngineExampleApp());
}

class DZero3DEngineExampleApp extends StatelessWidget {
  const DZero3DEngineExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3D ビューア',
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
      home: const EngineEditorScreen(),
    );
  }
}

class EngineEditorScreen extends StatefulWidget {
  const EngineEditorScreen({super.key});

  @override
  State<EngineEditorScreen> createState() => _EngineEditorScreenState();
}

class _EngineEditorScreenState extends State<EngineEditorScreen> {
  Zero3DEngineController _controller = Zero3DEngineController.simulated(
    renderMode: Zero3DRenderMode.hybridNaniteRt,
    fpsMode: Zero3DFpsMode.cap144,
  );

  @override
  void initState() {
    super.initState();
    _initNativeMetalEngine();
  }

  Future<void> _initNativeMetalEngine() async {
    final nativeCtrl = await Zero3DEngineController.create(
      width: 1280,
      height: 720,
      renderMode: Zero3DRenderMode.hybridNaniteRt,
      fpsMode: Zero3DFpsMode.cap144,
    );
    if (!mounted) {
      await nativeCtrl.dispose();
      return;
    }
    final prev = _controller;
    setState(() {
      _controller = nativeCtrl;
    });
    await prev.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '3D ビューア',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return ZViewport3D(
                            controller: _controller,
                            size: Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                            overlay: Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: ZSceneInspector3D(
                                  controller: _controller,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          onPressed: () => _controller.setPipelineConfig(
            renderMode: Zero3DRenderMode.hybridNaniteRt,
          ),
          child: const Text('標準表示'),
        ),
        OutlinedButton(
          onPressed: () => _controller.setPipelineConfig(
            renderMode: Zero3DRenderMode.raytracingGi,
            maxRayBounces: 3,
          ),
          child: const Text('レイトレーシング'),
        ),
        OutlinedButton(
          onPressed: () {
            final next = !_controller.isPhysicsEnabled;
            _controller.setPhysicsEnabled(next);
            if (next) _controller.applyEntityImpulse(vy: 5.8);
          },
          child: const Text('物理ジャンプ'),
        ),
      ],
    );
  }
}

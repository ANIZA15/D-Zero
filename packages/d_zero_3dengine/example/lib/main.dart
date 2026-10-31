import 'package:flutter/material.dart';
import 'package:d_zero_3dengine/d_zero_3dengine.dart';
import 'package:d_zero_counter/d_zero_counter.dart';

void main() {
  runApp(const DZero3DEngineExampleApp());
}

class DZero3DEngineExampleApp extends StatelessWidget {
  const DZero3DEngineExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'd_zero_3dengine Editor & Benchmark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B12),
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
        title: const Text('⚡️ d_zero_3dengine (Nanite + Ray Tracing)'),
        backgroundColor: const Color(0xFF101726),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12.0),
            child: Center(child: ZFPSMonitor(size: Size(140.0, 38.0))),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: ZViewport3D(
                  controller: _controller,
                  size: const Size(760.0, 420.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton(
          onPressed: () => _controller.setPipelineConfig(
            renderMode: Zero3DRenderMode.hybridNaniteRt,
          ),
          child: const Text('Hybrid Nanite + RT'),
        ),
        ElevatedButton(
          onPressed: () => _controller.setPipelineConfig(
            renderMode: Zero3DRenderMode.naniteClusters,
          ),
          child: const Text('Nanite Cluster View'),
        ),
        ElevatedButton(
          onPressed: () => _controller.setPipelineConfig(
            fpsMode: Zero3DFpsMode.cap144,
          ),
          child: const Text('144Hz Target'),
        ),
        ElevatedButton(
          onPressed: () => _controller.setPipelineConfig(
            fpsMode: Zero3DFpsMode.cap240,
          ),
          child: const Text('240Hz Target'),
        ),
        ElevatedButton(
          onPressed: () => _controller.setPipelineConfig(
            fpsMode: Zero3DFpsMode.uncapped,
          ),
          child: const Text('Uncapped FPS'),
        ),
      ],
    );
  }
}

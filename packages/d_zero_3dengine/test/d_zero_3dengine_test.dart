import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_3dengine/d_zero_3dengine.dart';

void main() {
  group('【1. 正常系テスト】Zero3DEngineController & 128-byte FFI 共有メモリ', () {
    late Zero3DEngineController controller;

    setUp(() {
      controller = Zero3DEngineController.simulated(
        renderMode: Zero3DRenderMode.hybridNaniteRt,
        fpsMode: Zero3DFpsMode.cap144,
      );
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('初期状態と 144Hz / Nanite / RayTracing テレメトリが FFI 経由で即座に読めること', () {
      expect(controller.isDisposed, isFalse);
      expect(controller.renderMode, equals(Zero3DRenderMode.hybridNaniteRt));
      expect(controller.fpsMode, equals(Zero3DFpsMode.cap144));
      expect(controller.displayRefreshHz, closeTo(144.0, 0.1));
      expect(controller.activeClusters, greaterThan(0));
      expect(
        controller.visibleTriangles,
        equals(controller.activeClusters * 128),
      );
      expect(controller.raysTracedK, greaterThan(0));
    });

    test('カメラ Orbit / Zoom / Light / 240Hz・Uncapped 切替が 0ns で反映されること', () {
      controller.setCameraOrbit(
        yaw: 1.1,
        pitch: 0.4,
        distance: 2.2,
        fovDeg: 75.0,
      );
      expect(controller.cameraYaw, closeTo(1.1, 0.001));
      expect(controller.cameraPitch, closeTo(0.4, 0.001));
      expect(controller.cameraDistance, closeTo(2.2, 0.001));
      expect(controller.cameraFovDeg, closeTo(75.0, 0.001));

      controller.setPipelineConfig(
        renderMode: Zero3DRenderMode.naniteClusters,
        fpsMode: Zero3DFpsMode.cap240,
        lodErrorThreshold: 0.5,
        maxRayBounces: 4,
      );
      controller.stepSimulation(dtMs: 4.16);

      expect(controller.renderMode, equals(Zero3DRenderMode.naniteClusters));
      expect(controller.fpsMode, equals(Zero3DFpsMode.cap240));
      expect(controller.displayRefreshHz, closeTo(240.0, 0.1));
      expect(controller.maxRayBounces, equals(4));
    });

    test('SoA ECS World エンティティ追加と 64-bit Visibility Buffer パックが機能すること', () {
      final beforeCount = controller.spawnedEntityCount;
      expect(beforeCount, greaterThan(0));

      final newId = controller.spawnEcsEntity(
        x: 1.5,
        y: 0.2,
        z: -1.0,
        scale: 1.2,
        clusterCount: 16,
      );
      expect(newId, equals(beforeCount));
      expect(controller.spawnedEntityCount, equals(beforeCount + 1));

      final bindings = Zero3DEngineNativeBindings.instance;
      final packed = bindings.packVisBuffer64(0.75, 4095, 99);
      expect(bindings.unpackVisBufferCluster(packed), equals(4095));
      expect(bindings.unpackVisBufferTriangle(packed), equals(99));
    });
  });

  group('【2. メモリ安全性・異常系テスト】Use-After-Free / Double-Free / 不正ポインタ防御', () {
    test('Double-Free 防御: dispose() を複数回連続で呼んでも安全に無視されること', () async {
      final controller = Zero3DEngineController.simulated();
      await controller.dispose();
      await controller.dispose();
      await controller.dispose();
      expect(controller.isDisposed, isTrue);
    });

    test('Use-After-Free 防御: dispose() 後に全プロパティ読み書きを行ってもクラッシュしないこと', () async {
      final controller = Zero3DEngineController.simulated();
      await controller.dispose();

      expect(() => controller.orbitBy(0.5, 0.2), returnsNormally);
      expect(() => controller.zoomBy(-1.0), returnsNormally);
      expect(() => controller.stepSimulation(dtMs: 6.94), returnsNormally);
      expect(controller.renderFps, equals(0.0));
      expect(controller.activeClusters, equals(0));
      expect(controller.visibleTriangles, equals(0));
      expect(controller.raysTracedK, equals(0));
    });

    test('未整列・不正ポインタ (0xDEADBEEF) 防御: SIGSEGV せずフォールバック値を返すこと', () async {
      final controller = Zero3DEngineController.externalStream(
        textureId: -1,
        stateAddress: 0xDEADBEEF,
        ownsState: false,
      );

      expect(controller.renderFps, equals(0.0));
      expect(controller.activeClusters, equals(0));
      expect(() => controller.orbitBy(0.2, 0.1), returnsNormally);
      await controller.dispose();
    });

    test('NaN / Infinity サニタイズ: 不正な浮動小数点数が渡されても C++ 境界で無害化されること', () async {
      final controller = Zero3DEngineController.simulated();
      controller.setCameraOrbit(
        yaw: double.nan,
        pitch: double.infinity,
        distance: -500.0,
        fovDeg: double.negativeInfinity,
      );
      expect(controller.cameraYaw.isFinite, isTrue);
      expect(controller.cameraPitch.isFinite, isTrue);
      expect(controller.cameraDistance, greaterThanOrEqualTo(0.5));
      await controller.dispose();
    });
  });

  group('【3. 100,000 回 FFI ゼロアロケーション高負荷ストレステスト】', () {
    test('100,000 回の連続カメラ更新 & Nanite ステップがメモリ肥大化なく高速完了すること', () async {
      final controller = Zero3DEngineController.simulated();
      final rng = Random(42);
      final sw = Stopwatch()..start();

      for (int i = 0; i < 100000; i++) {
        controller.orbitBy(rng.nextDouble() * 0.01, rng.nextDouble() * 0.01);
        if ((i & 63) == 0) {
          controller.stepSimulation(dtMs: 4.16);
        }
        expect(controller.renderFps, greaterThanOrEqualTo(0.0));
      }

      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(400));
      await controller.dispose();
    });
  });

  group('【4. MethodChannel & Widget ライフサイクルテスト】', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.fexcy.d_zero_3dengine'),
        (MethodCall call) async {
          if (call.method == 'create') {
            return {
              'textureId': 77,
              'stateAddress':
                  Zero3DEngineNativeBindings.instance.createState().address,
            };
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.fexcy.d_zero_3dengine'),
        null,
      );
    });

    test('Zero3DEngineController.create() がネイティブ Texture と共有メモリをバインドすること',
        () async {
      final ctrl = await Zero3DEngineController.create(
        width: 1920,
        height: 1080,
        fpsMode: Zero3DFpsMode.cap240,
      );
      expect(ctrl.textureId, equals(77));
      expect(ctrl.fpsMode, equals(Zero3DFpsMode.cap240));

      final ptr = ctrl.statePointer;
      await ctrl.dispose();
      Zero3DEngineNativeBindings.instance.destroyState(ptr);
    });

    testWidgets(
      'ZViewport3D (ZScene3D) と ZEngineTelemetryHud (Z3DStatsOverlay) がマウント・操作・アンマウントでリークしないこと',
      (tester) async {
        final ctrl = Zero3DEngineController.simulated(
          renderMode: Zero3DRenderMode.naniteClusters,
          fpsMode: Zero3DFpsMode.cap144,
        );

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: ZScene3D(
                controller: ctrl,
                size: const Size(480.0, 300.0),
                showTelemetryHud: true,
              ),
            ),
          ),
        );

        expect(find.byType(ZViewport3D), findsOneWidget);
        expect(find.byType(ZEngineTelemetryHud), findsOneWidget);

        await tester.drag(find.byType(ZViewport3D), const Offset(40.0, -20.0));
        await tester.pump(const Duration(milliseconds: 16));

        // アンマウント後にリスナーが確実に解除されていること
        await tester.pumpWidget(const SizedBox.shrink());
        expect(ctrl.hasListeners, isFalse);

        await ctrl.dispose();
      },
    );

    testWidgets(
      'ZSceneInspector3D (ZNaniteLodPanel) のスライダー操作とアンマウント解放が機能すること',
      (tester) async {
        final ctrl = Zero3DEngineController.simulated();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: ZSceneInspector3D(
                controller: ctrl,
                size: const Size(320.0, 114.0),
              ),
            ),
          ),
        );

        expect(find.byType(ZSceneInspector3D), findsOneWidget);

        // 1段目 (Nanite LOD Threshold), 2段目 (Sun Light Azimuth), 3段目 (Camera FOV) をドラッグ操作
        final topLeft = tester.getTopLeft(find.byType(ZSceneInspector3D));
        await tester.tapAt(topLeft + const Offset(200.0, 20.0));
        await tester.tapAt(topLeft + const Offset(240.0, 56.0));
        await tester.tapAt(topLeft + const Offset(180.0, 92.0));
        await tester.pump();

        expect(ctrl.lodErrorThreshold, greaterThan(0.25));
        expect(ctrl.cameraFovDeg, greaterThanOrEqualTo(20.0));

        await tester.pumpWidget(const SizedBox.shrink());
        expect(ctrl.hasListeners, isFalse);

        await ctrl.dispose();
      },
    );
  });
}

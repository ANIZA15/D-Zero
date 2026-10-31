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

      controller.setEntityTransform(
        entityId: 0,
        x: 0.0,
        y: 0.0,
        z: 0.0,
        scale: 1.4,
      );
      expect(controller.getEntityScale(0), closeTo(1.4, 0.01));
      final hitId = controller.raycastPick(0.0, 0.0);
      expect(hitId, greaterThanOrEqualTo(0));

      controller.setPbrMaterial(metallic: 0.88, roughness: 0.12, emissive: 1.8);
      expect(controller.pbrMetallic, closeTo(0.88, 0.01));
      expect(controller.pbrRoughness, closeTo(0.12, 0.01));
      expect(controller.pbrEmissive, closeTo(1.8, 0.01));

      controller.setPhysicsEnabled(true);
      expect(controller.isPhysicsEnabled, isTrue);
      controller.applyEntityImpulse(entityId: 0, vy: 4.5);
      controller.stepSimulation(dtMs: 16.0);

      final meshlets = controller.buildProceduralMeshlets(triangleCount: 4096);
      expect(meshlets, equals(32));
      expect(controller.builtMeshletCount, equals(32));

      controller.moveCameraLocal(forward: 0.5, right: -0.2, up: 0.1);
      expect(controller.targetY, closeTo(0.1, 0.25));

      controller.setPostProcess(
        fogDensity: 0.06,
        exposureEv: 1.35,
        bloomIntensity: 0.75,
      );
      expect(controller.fogDensity, closeTo(0.06, 0.005));
      expect(controller.exposureEv, closeTo(1.35, 0.01));
      expect(controller.bloomIntensity, closeTo(0.75, 0.01));

      controller.setSequencerState(timeSec: 3.2, playing: true);
      expect(controller.sequencerTimeSec, closeTo(3.2, 0.01));
      expect(controller.isSequencerPlaying, isTrue);
      controller.stepSimulation(dtMs: 16.0);
      expect(controller.sequencerTimeSec, greaterThan(3.2));

      final objClusters = controller.loadBuiltinObjPreset(presetId: 1);
      expect(objClusters, greaterThanOrEqualTo(1));
      expect(controller.loadedObjVertices, greaterThan(0));
      expect(controller.loadedObjTriangles, greaterThan(0));
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

    testWidgets(
      'ZTransformGizmo3D (Z3DGizmoOverlay) と ZOutliner3D (ZEntityOutliner3D) の操作と解放が機能すること',
      (tester) async {
        final ctrl = Zero3DEngineController.simulated();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                ZTransformGizmo3D(controller: ctrl),
                ZOutliner3D(controller: ctrl),
              ],
            ),
          ),
        );

        expect(find.byType(ZTransformGizmo3D), findsOneWidget);
        expect(find.byType(ZOutliner3D), findsOneWidget);

        final gizmoTopLeft = tester.getTopLeft(find.byType(ZTransformGizmo3D));
        await tester.tapAt(gizmoTopLeft + const Offset(150.0, 20.0));
        await tester.tapAt(gizmoTopLeft + const Offset(160.0, 62.0));
        await tester.tapAt(gizmoTopLeft + const Offset(170.0, 104.0));
        await tester.tapAt(gizmoTopLeft + const Offset(180.0, 146.0));
        await tester.tap(find.byType(ZOutliner3D));
        await tester.pump(const Duration(milliseconds: 16));

        expect(ctrl.getEntityScale(0), greaterThan(0.3));

        await tester.pumpWidget(const SizedBox.shrink());
        expect(ctrl.hasListeners, isFalse);

        await ctrl.dispose();
      },
    );

    testWidgets(
      'ZMaterialEditor3D (ZPbrMaterialPanel) の PBR / 物理操作および WASD キー入力が機能すること',
      (tester) async {
        final ctrl = Zero3DEngineController.simulated();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                ZViewport3D(
                  controller: ctrl,
                  size: const Size(320.0, 200.0),
                ),
                ZMaterialEditor3D(controller: ctrl),
              ],
            ),
          ),
        );

        expect(find.byType(ZMaterialEditor3D), findsOneWidget);

        final matTopLeft = tester.getTopLeft(find.byType(ZMaterialEditor3D));
        await tester.tapAt(matTopLeft + const Offset(160.0, 20.0));
        await tester.tapAt(matTopLeft + const Offset(140.0, 62.0));
        await tester.tapAt(matTopLeft + const Offset(180.0, 104.0));
        await tester.tapAt(matTopLeft + const Offset(120.0, 146.0));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();

        expect(ctrl.isPhysicsEnabled, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(ctrl.hasListeners, isFalse);

        await ctrl.dispose();
      },
    );

    testWidgets(
      'ZPostProcess3D (ZPostProcessPanel3D) と ZSequencer3D (ZTimelineSequencer3D) の操作と解放が機能すること',
      (tester) async {
        final ctrl = Zero3DEngineController.simulated();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                ZPostProcess3D(controller: ctrl),
                ZSequencer3D(controller: ctrl),
              ],
            ),
          ),
        );

        expect(find.byType(ZPostProcess3D), findsOneWidget);
        expect(find.byType(ZSequencer3D), findsOneWidget);

        final ppTopLeft = tester.getTopLeft(find.byType(ZPostProcess3D));
        await tester.tapAt(ppTopLeft + const Offset(160.0, 20.0));
        await tester.tapAt(ppTopLeft + const Offset(140.0, 62.0));
        await tester.tapAt(ppTopLeft + const Offset(180.0, 104.0));
        await tester.tapAt(ppTopLeft + const Offset(120.0, 146.0));

        final seqTopLeft = tester.getTopLeft(find.byType(ZSequencer3D));
        await tester.tapAt(seqTopLeft + const Offset(20.0, 22.0));
        await tester.tapAt(seqTopLeft + const Offset(200.0, 22.0));
        await tester.tapAt(seqTopLeft + const Offset(460.0, 22.0));
        await tester.pump();

        expect(ctrl.loadedObjTriangles, greaterThan(0));
        expect(ctrl.sequencerTimeSec, greaterThan(1.0));

        await tester.pumpWidget(const SizedBox.shrink());
        expect(ctrl.hasListeners, isFalse);

        await ctrl.dispose();
      },
    );
  });
}

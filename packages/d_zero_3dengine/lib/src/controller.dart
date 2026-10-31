import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'engine_state_ffi.dart';

/// Zero-allocation 3D Game Engine & Nanite/RayTracing controller.
///
/// Synchronizes camera orbit, directional lighting, Nanite LOD thresholds,
/// hardware ray tracing bounces, and 144Hz/240Hz/Uncapped frame scheduling
/// directly with C++ via a 128-byte (2 cache lines) FFI shared memory block.
class Zero3DEngineController implements Listenable {
  static const MethodChannel _channel =
      MethodChannel('com.fexcy.d_zero_3dengine');

  /// Maximum meshlet clusters in the built-in procedural DAG hierarchy.
  static const int maxDagClusters = 64;

  /// Triangles per Nanite meshlet cluster (`128` in software/shader mode).
  static const int trianglesPerCluster = 16;

  /// Direct FFI pointer to the 128-byte C++ `Zero3DEngineState`.
  final ffi.Pointer<Zero3DEngineStateNative> statePointer;
  final Zero3DEngineStateView _view;

  /// Direct FFI pointer to the C++ SoA `Zero3DEcsWorld` (when locally owned).
  final ffi.Pointer<Zero3DEcsWorldNative> ecsWorldPointer;

  /// Native GPU zero-copy texture ID (`-1` when using Impeller Shader / SoA fallback).
  final int textureId;
  final bool _ownsState;
  int _spawnedEntityCount = 0;

  // Pre-allocated SoA buffers for Nanite Cluster Bounding Spheres & LOD errors
  late final Float32List _clusterCenterX;
  late final Float32List _clusterCenterY;
  late final Float32List _clusterCenterZ;
  late final Float32List _clusterRadius;
  late final Float32List _clusterBaseError;
  late final Int32List _clusterLodLevel;

  final ZeroIntNotifier _revision = ZeroIntNotifier(0);
  bool _isDisposed = false;

  Zero3DEngineController._({
    required this.statePointer,
    required this.ecsWorldPointer,
    required this.textureId,
    required bool ownsState,
  })  : _ownsState = ownsState,
        _view = Zero3DEngineStateView(statePointer) {
    _clusterCenterX = Float32List(maxDagClusters);
    _clusterCenterY = Float32List(maxDagClusters);
    _clusterCenterZ = Float32List(maxDagClusters);
    _clusterRadius = Float32List(maxDagClusters);
    _clusterBaseError = Float32List(maxDagClusters);
    _clusterLodLevel = Int32List(maxDagClusters);
    _populateNaniteClusterDag();
  }

  /// Creates a native hardware-accelerated 3D engine instance (Metal 3 / DX12 Zero-Copy).
  ///
  /// Automatically falls back to the deterministic FFI + Impeller Shader engine
  /// when running in unit tests or platforms without the native texture registrar.
  static Future<Zero3DEngineController> create({
    int width = 1280,
    int height = 720,
    Zero3DRenderMode renderMode = Zero3DRenderMode.hybridNaniteRt,
    Zero3DFpsMode fpsMode = Zero3DFpsMode.vsyncNative,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('create', {
        'width': width,
        'height': height,
      });
      if (result != null) {
        final int texId = result['textureId'] as int;
        final int addr = result['stateAddress'] as int;
        final int ecsAddr = (result['ecsAddress'] as int?) ?? 0;
        final ptr = ffi.Pointer<Zero3DEngineStateNative>.fromAddress(addr);
        final ecsPtr = ecsAddr != 0
            ? ffi.Pointer<Zero3DEcsWorldNative>.fromAddress(ecsAddr)
            : ffi.nullptr;
        final ctrl = Zero3DEngineController._(
          statePointer: ptr,
          ecsWorldPointer: ecsPtr,
          textureId: texId,
          ownsState: false,
        );
        ctrl.setPipelineConfig(renderMode: renderMode, fpsMode: fpsMode);
        return ctrl;
      }
    } catch (_) {
      // Fallback to local FFI state when MethodChannel is unbound
    }
    return Zero3DEngineController.simulated(
      renderMode: renderMode,
      fpsMode: fpsMode,
    );
  }

  /// Creates an in-memory FFI-backed 3D engine controller (no MethodChannel required).
  factory Zero3DEngineController.simulated({
    Zero3DRenderMode renderMode = Zero3DRenderMode.hybridNaniteRt,
    Zero3DFpsMode fpsMode = Zero3DFpsMode.vsyncNative,
  }) {
    final ptr = Zero3DEngineNativeBindings.instance.createState();
    final ecsPtr = Zero3DEngineNativeBindings.instance.ecsCreateWorld();
    final ctrl = Zero3DEngineController._(
      statePointer: ptr,
      ecsWorldPointer: ecsPtr,
      textureId: -1,
      ownsState: true,
    );
    ctrl.setPipelineConfig(renderMode: renderMode, fpsMode: fpsMode);
    ctrl.spawnEcsEntity(
      x: 0.0,
      y: 0.25,
      z: 0.0,
      scale: 1.0,
      boundRadius: 0.65,
      clusterCount: 128,
    );
    for (int i = 1; i < 64; i++) {
      ctrl.spawnEcsEntity(
        x: ((i % 8) - 3.5) * 1.2,
        y: 0.0,
        z: ((i ~/ 8) - 3.5) * 1.2,
        clusterCount: 64,
      );
    }
    ctrl.stepSimulation(dtMs: 6.94);
    return ctrl;
  }

  /// Binds to an external native 3D engine texture and shared memory address.
  factory Zero3DEngineController.externalStream({
    required int textureId,
    required int stateAddress,
    bool ownsState = false,
  }) {
    final ptr = ffi.Pointer<Zero3DEngineStateNative>.fromAddress(stateAddress);
    return Zero3DEngineController._(
      statePointer: ptr,
      ecsWorldPointer: ffi.nullptr,
      textureId: textureId,
      ownsState: ownsState,
    );
  }

  void _populateNaniteClusterDag() {
    for (int i = 0; i < maxDagClusters; i++) {
      final int lod = i ~/ 16; // 4 LOD tiers (0 = finest, 3 = coarsest)
      final double ring = 0.65 + (i % 4) * 0.35;
      final double angle = (i * 2.0 * math.pi) / 16.0;
      _clusterCenterX[i] = math.cos(angle) * ring;
      _clusterCenterY[i] = ((i % 8) - 3.5) * 0.18;
      _clusterCenterZ[i] = math.sin(angle) * ring;
      _clusterRadius[i] = 0.22 + lod * 0.08;
      _clusterBaseError[i] = 0.45 * (1 << lod);
      _clusterLodLevel[i] = lod;
    }
  }

  /// Whether this controller has been disposed.
  @pragma('vm:prefer-inline')
  bool get isDisposed => _isDisposed;

  /// Whether any listeners are currently registered.
  bool get hasListeners => !_isDisposed && _revision.hasListeners;

  /// Camera horizontal yaw angle in radians.
  @pragma('vm:prefer-inline')
  double get cameraYaw => _isDisposed ? 0.0 : _view.cameraYaw;

  /// Camera vertical pitch angle in radians.
  @pragma('vm:prefer-inline')
  double get cameraPitch => _isDisposed ? 0.0 : _view.cameraPitch;

  /// Camera orbit distance in meters.
  @pragma('vm:prefer-inline')
  double get cameraDistance => _isDisposed ? 3.8 : _view.cameraDistance;

  /// Camera vertical field-of-view in degrees.
  @pragma('vm:prefer-inline')
  double get cameraFovDeg => _isDisposed ? 60.0 : _view.cameraFovDeg;

  /// Camera target X coordinate in meters.
  @pragma('vm:prefer-inline')
  double get targetX => _isDisposed ? 0.0 : _view.targetX;

  /// Camera target Y coordinate in meters.
  @pragma('vm:prefer-inline')
  double get targetY => _isDisposed ? 0.0 : _view.targetY;

  /// Camera target Z coordinate in meters.
  @pragma('vm:prefer-inline')
  double get targetZ => _isDisposed ? 0.0 : _view.targetZ;

  /// Directional light azimuth angle in radians.
  @pragma('vm:prefer-inline')
  double get lightAzimuth => _isDisposed ? 0.78 : _view.lightAzimuth;

  /// Directional light elevation angle in radians.
  @pragma('vm:prefer-inline')
  double get lightElevation => _isDisposed ? 0.85 : _view.lightElevation;

  /// Nanite screen-space error threshold in pixels.
  @pragma('vm:prefer-inline')
  double get lodErrorThreshold => _isDisposed ? 1.0 : _view.lodErrorThreshold;

  /// Maximum hardware ray tracing bounce depth.
  @pragma('vm:prefer-inline')
  int get maxRayBounces => _isDisposed ? 0 : _view.maxRayBounces;

  /// Current active 3D rendering pipeline mode.
  @pragma('vm:prefer-inline')
  Zero3DRenderMode get renderMode {
    if (_isDisposed) return Zero3DRenderMode.hybridNaniteRt;
    final int raw = _view.renderModeRaw;
    if (raw >= 0 && raw < Zero3DRenderMode.values.length) {
      return Zero3DRenderMode.values[raw];
    }
    return Zero3DRenderMode.hybridNaniteRt;
  }

  /// Current frame-rate scheduling mode (VSync / 120 / 144 / 240 / Uncapped).
  @pragma('vm:prefer-inline')
  Zero3DFpsMode get fpsMode {
    if (_isDisposed) return Zero3DFpsMode.vsyncNative;
    final int raw = _view.fpsModeRaw;
    if (raw >= 0 && raw < Zero3DFpsMode.values.length) {
      return Zero3DFpsMode.values[raw];
    }
    return Zero3DFpsMode.vsyncNative;
  }

  /// Current engine status.
  @pragma('vm:prefer-inline')
  Zero3DEngineStatus get status {
    if (_isDisposed) return Zero3DEngineStatus.idle;
    final int raw = _view.statusRaw;
    if (raw >= 0 && raw < Zero3DEngineStatus.values.length) {
      return Zero3DEngineStatus.values[raw];
    }
    return Zero3DEngineStatus.idle;
  }

  /// Measured native render frame rate (FPS).
  @pragma('vm:prefer-inline')
  double get renderFps => _isDisposed ? 0.0 : _view.renderFps;

  /// Measured frame time in milliseconds.
  @pragma('vm:prefer-inline')
  double get frameTimeMs => _isDisposed ? 0.0 : _view.frameTimeMs;

  /// Detected display refresh rate in Hz (e.g. `60`, `120`, `144`, `240`).
  @pragma('vm:prefer-inline')
  double get displayRefreshHz => _isDisposed ? 0.0 : _view.displayRefreshHz;

  /// Total frames rendered since initialization.
  @pragma('vm:prefer-inline')
  int get frameCount => _isDisposed ? 0 : _view.frameCount;

  /// Number of active Nanite meshlet clusters selected in the current frame.
  @pragma('vm:prefer-inline')
  int get activeClusters => _isDisposed ? 0 : _view.activeClusters;

  /// Number of visible triangles emitted after Nanite DAG & backface culling.
  @pragma('vm:prefer-inline')
  int get visibleTriangles => _isDisposed ? 0 : _view.visibleTriangles;

  /// Number of clusters rejected by frustum, occlusion, or LOD culling.
  @pragma('vm:prefer-inline')
  int get culledClusters => _isDisposed ? 0 : _view.culledClusters;

  /// Hardware rays traced in the current frame (in thousands of rays).
  @pragma('vm:prefer-inline')
  int get raysTracedK => _isDisposed ? 0 : _view.raysTracedK;

  /// Sets the camera orbit parameters in shared memory (0ns FFI write).
  void setCameraOrbit({
    double? yaw,
    double? pitch,
    double? distance,
    double? fovDeg,
  }) {
    if (_isDisposed || !_view.isValid) return;
    Zero3DEngineNativeBindings.instance.setCameraOrbit(
      statePointer,
      yaw ?? _view.cameraYaw,
      pitch ?? _view.cameraPitch,
      distance ?? _view.cameraDistance,
      fovDeg ?? _view.cameraFovDeg,
    );
    _revision.add(1);
  }

  /// Orbits the camera by delta `[dYaw]` and `[dPitch]` in radians.
  void orbitBy(double dYaw, double dPitch) {
    if (_isDisposed || !_view.isValid) return;
    if (dYaw.isNaN || dPitch.isNaN) return;
    setCameraOrbit(
      yaw: _view.cameraYaw + dYaw,
      pitch: (_view.cameraPitch + dPitch).clamp(-1.48, 1.48),
    );
  }

  /// Zooms the camera distance by `[deltaDistance]` meters.
  void zoomBy(double deltaDistance) {
    if (_isDisposed || !_view.isValid || deltaDistance.isNaN) return;
    setCameraOrbit(
      distance: (_view.cameraDistance + deltaDistance).clamp(1.2, 40.0),
    );
  }

  /// Sets the 3D camera target position (`tx, ty, tz`) in shared memory.
  void setCameraTarget(double tx, double ty, double tz) {
    if (_isDisposed || !_view.isValid) return;
    Zero3DEngineNativeBindings.instance.setCameraTarget(
      statePointer,
      tx,
      ty,
      tz,
    );
    _revision.add(1);
  }

  /// Pans the 3D camera target by `(dx, dy, dz)` in world space.
  void panCameraBy(double dx, double dy, double dz) {
    if (_isDisposed || !_view.isValid) return;
    if (dx.isNaN || dy.isNaN || dz.isNaN) return;
    setCameraTarget(
      _view.targetX + dx,
      _view.targetY + dy,
      _view.targetZ + dz,
    );
  }

  /// Moves the 3D camera in local 6DOF coordinates (`forward`, `right`, `up`).
  void moveCameraLocal({
    double forward = 0.0,
    double right = 0.0,
    double up = 0.0,
  }) {
    if (_isDisposed || !_view.isValid) return;
    Zero3DEngineNativeBindings.instance.moveCameraLocal(
      statePointer,
      forward,
      right,
      up,
    );
    _revision.add(1);
  }

  /// Sets directional light azimuth and elevation angles in radians.
  void setLightAngles(double azimuth, double elevation) {
    if (_isDisposed || !_view.isValid) return;
    Zero3DEngineNativeBindings.instance.setLightAngles(
      statePointer,
      azimuth,
      elevation,
    );
    _revision.add(1);
  }

  /// Configures the 3D rendering mode, FPS cap (120/144/240/Uncapped), Nanite LOD threshold, and RT bounces.
  void setPipelineConfig({
    Zero3DRenderMode? renderMode,
    Zero3DFpsMode? fpsMode,
    int? targetFpsLimit,
    double? lodErrorThreshold,
    int? maxRayBounces,
  }) {
    if (_isDisposed || !_view.isValid) return;
    final int modeIdx = (renderMode ?? this.renderMode).index;
    final int fpsIdx = (fpsMode ?? this.fpsMode).index;
    final int limit = targetFpsLimit ?? _defaultLimitForFpsMode(fpsIdx);
    final double lod = lodErrorThreshold ?? _view.lodErrorThreshold;
    final int bounces = maxRayBounces ?? _view.maxRayBounces;

    Zero3DEngineNativeBindings.instance.setPipelineConfig(
      statePointer,
      modeIdx,
      fpsIdx,
      limit,
      lod,
      bounces,
    );
    _revision.add(1);
  }

  int _defaultLimitForFpsMode(int fpsIdx) {
    if (fpsIdx == Zero3DFpsMode.cap120.index) return 120;
    if (fpsIdx == Zero3DFpsMode.cap144.index) return 144;
    if (fpsIdx == Zero3DFpsMode.cap240.index) return 240;
    return 0;
  }

  /// Advances the C++ Nanite DAG culling and telemetry simulation by `[dtMs]` milliseconds.
  void stepSimulation({double dtMs = 6.94, int totalDagClusters = 4096}) {
    if (_isDisposed || !_view.isValid) return;
    if (ecsWorldPointer.address != 0 && _spawnedEntityCount > 0) {
      Zero3DEngineNativeBindings.instance.ecsStepSequencer(
        ecsWorldPointer,
        dtMs * 0.001,
      );
      Zero3DEngineNativeBindings.instance.ecsStepPhysics(
        ecsWorldPointer,
        dtMs * 0.001,
      );
      Zero3DEngineNativeBindings.instance.ecsCullAndUpdateState(
        ecsWorldPointer,
        statePointer,
        dtMs,
      );
    } else {
      Zero3DEngineNativeBindings.instance.simulateFrameStep(
        statePointer,
        totalDagClusters,
        dtMs,
      );
    }
    _revision.add(1);
  }

  /// PBR Metallic parameter (`0.0 .. 1.0`).
  double get pbrMetallic {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.75;
    return Zero3DEngineNativeBindings.instance.ecsGetPbrMetallic(
      ecsWorldPointer,
    );
  }

  /// PBR Roughness parameter (`0.04 .. 1.0`).
  double get pbrRoughness {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.18;
    return Zero3DEngineNativeBindings.instance.ecsGetPbrRoughness(
      ecsWorldPointer,
    );
  }

  /// PBR Emissive intensity (`0.0 .. 5.0`).
  double get pbrEmissive {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.25;
    return Zero3DEngineNativeBindings.instance.ecsGetPbrEmissive(
      ecsWorldPointer,
    );
  }

  /// Updates Cook-Torrance GGX PBR material parameters (`metallic`, `roughness`, `emissive`).
  void setPbrMaterial({
    double? metallic,
    double? roughness,
    double? emissive,
  }) {
    if (_isDisposed || ecsWorldPointer.address == 0) return;
    Zero3DEngineNativeBindings.instance.ecsSetPbrMaterial(
      ecsWorldPointer,
      metallic ?? pbrMetallic,
      roughness ?? pbrRoughness,
      emissive ?? pbrEmissive,
    );
    _revision.add(1);
  }

  /// Whether C++ rigid-body gravity & collision physics is active.
  bool get isPhysicsEnabled {
    if (_isDisposed || ecsWorldPointer.address == 0) return false;
    return Zero3DEngineNativeBindings.instance.ecsGetPhysicsEnabled(
          ecsWorldPointer,
        ) !=
        0;
  }

  /// Enables or disables C++ rigid-body physics simulation.
  void setPhysicsEnabled(bool enabled) {
    if (_isDisposed || ecsWorldPointer.address == 0) return;
    Zero3DEngineNativeBindings.instance.ecsSetPhysicsEnabled(
      ecsWorldPointer,
      enabled ? 1 : 0,
    );
    _revision.add(1);
  }

  /// Applies a 3D velocity impulse `(vx, vy, vz)` to `[entityId]` (defaults to selected entity).
  void applyEntityImpulse({
    int? entityId,
    double vx = 0.0,
    double vy = 5.2,
    double vz = 0.0,
  }) {
    if (_isDisposed || ecsWorldPointer.address == 0) return;
    final int id = entityId ?? (selectedEntityId >= 0 ? selectedEntityId : 0);
    Zero3DEngineNativeBindings.instance.ecsApplyImpulse(
      ecsWorldPointer,
      id,
      vx,
      vy,
      vz,
    );
    _revision.add(1);
  }

  /// Number of 128-triangle Nanite meshlet clusters built by the C++ Meshlet Builder.
  int get builtMeshletCount {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0;
    return Zero3DEngineNativeBindings.instance.ecsGetBuiltMeshletCount(
      ecsWorldPointer,
    );
  }

  /// Builds 128-triangle Nanite meshlet clusters from a high-poly 3D mesh of `[triangleCount]` triangles in C++.
  int buildProceduralMeshlets({int triangleCount = 4096}) {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0;
    final int count = Zero3DEngineNativeBindings.instance
        .ecsBuildProceduralMeshlets(ecsWorldPointer, triangleCount);
    _revision.add(1);
    return count;
  }

  /// Volumetric Fog density (`0.0 .. 1.0`).
  double get fogDensity {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.15;
    return Zero3DEngineNativeBindings.instance.ecsGetFogDensity(
      ecsWorldPointer,
    );
  }

  /// ACES Filmic exposure EV (`0.2 .. 4.0`).
  double get exposureEv {
    if (_isDisposed || ecsWorldPointer.address == 0) return 1.25;
    return Zero3DEngineNativeBindings.instance.ecsGetExposureEv(
      ecsWorldPointer,
    );
  }

  /// Specular Bloom intensity (`0.0 .. 2.0`).
  double get bloomIntensity {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.45;
    return Zero3DEngineNativeBindings.instance.ecsGetBloomIntensity(
      ecsWorldPointer,
    );
  }

  /// Updates Volumetric Fog, ACES Exposure EV, and Specular Bloom intensity.
  void setPostProcess({
    double? fogDensity,
    double? exposureEv,
    double? bloomIntensity,
  }) {
    if (_isDisposed || ecsWorldPointer.address == 0) return;
    Zero3DEngineNativeBindings.instance.ecsSetPostProcess(
      ecsWorldPointer,
      fogDensity ?? this.fogDensity,
      exposureEv ?? this.exposureEv,
      bloomIntensity ?? this.bloomIntensity,
    );
    _revision.add(1);
  }

  /// Current 3D Sequencer timeline position in seconds (`0.0 .. 30.0`).
  double get sequencerTimeSec {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.0;
    return Zero3DEngineNativeBindings.instance.ecsGetSequencerTime(
      ecsWorldPointer,
    );
  }

  /// Whether the 3D Sequencer timeline is actively playing.
  bool get isSequencerPlaying {
    if (_isDisposed || ecsWorldPointer.address == 0) return false;
    return Zero3DEngineNativeBindings.instance.ecsGetSequencerPlaying(
          ecsWorldPointer,
        ) !=
        0;
  }

  /// Sets the 3D Sequencer timeline scrub position (`0.0 .. 30.0s`) and play state.
  void setSequencerState({double? timeSec, bool? playing}) {
    if (_isDisposed || ecsWorldPointer.address == 0) return;
    Zero3DEngineNativeBindings.instance.ecsSetSequencerState(
      ecsWorldPointer,
      timeSec ?? sequencerTimeSec,
      (playing ?? isSequencerPlaying) ? 1 : 0,
    );
    _revision.add(1);
  }

  /// Number of vertices parsed by the C++ Wavefront `.obj` mesh loader.
  int get loadedObjVertices {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0;
    return Zero3DEngineNativeBindings.instance.ecsGetLoadedObjVertices(
      ecsWorldPointer,
    );
  }

  /// Number of triangles parsed by the C++ Wavefront `.obj` mesh loader.
  int get loadedObjTriangles {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0;
    return Zero3DEngineNativeBindings.instance.ecsGetLoadedObjTriangles(
      ecsWorldPointer,
    );
  }

  /// Parses a Wavefront `.obj` 3D mesh preset (`presetId = 0 or 1`) in C++ and builds Nanite meshlets.
  int loadBuiltinObjPreset({int presetId = 1}) {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0;
    final int tris = Zero3DEngineNativeBindings.instance
        .ecsLoadBuiltinObjPreset(ecsWorldPointer, presetId);
    _revision.add(1);
    return tris;
  }

  /// Number of 3D entities spawned in the C++ SoA ECS world.
  int get spawnedEntityCount {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0;
    final int c = Zero3DEngineNativeBindings.instance.ecsGetEntityCount(
      ecsWorldPointer,
    );
    return c > 0 ? c : _spawnedEntityCount;
  }

  /// Currently selected entity ID in `Zero3DEcsWorld` (`-1` if none).
  int get selectedEntityId {
    if (_isDisposed || ecsWorldPointer.address == 0) return -1;
    return Zero3DEngineNativeBindings.instance.ecsGetSelectedEntity(
      ecsWorldPointer,
    );
  }

  /// Selects an entity by ID (`0 .. spawnedEntityCount - 1`, or `-1` to clear).
  void selectEntity(int entityId) {
    if (_isDisposed || ecsWorldPointer.address == 0) return;
    Zero3DEngineNativeBindings.instance.ecsSetSelectedEntity(
      ecsWorldPointer,
      entityId,
    );
    _revision.add(1);
  }

  /// Reads the X coordinate of `[entityId]` in `Zero3DEcsWorld`.
  double getEntityX(int entityId) {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.0;
    return Zero3DEngineNativeBindings.instance.ecsGetEntityX(
      ecsWorldPointer,
      entityId,
    );
  }

  /// Reads the Y coordinate of `[entityId]` in `Zero3DEcsWorld`.
  double getEntityY(int entityId) {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.0;
    return Zero3DEngineNativeBindings.instance.ecsGetEntityY(
      ecsWorldPointer,
      entityId,
    );
  }

  /// Reads the Z coordinate of `[entityId]` in `Zero3DEcsWorld`.
  double getEntityZ(int entityId) {
    if (_isDisposed || ecsWorldPointer.address == 0) return 0.0;
    return Zero3DEngineNativeBindings.instance.ecsGetEntityZ(
      ecsWorldPointer,
      entityId,
    );
  }

  /// Reads the uniform scale of `[entityId]` in `Zero3DEcsWorld`.
  double getEntityScale(int entityId) {
    if (_isDisposed || ecsWorldPointer.address == 0) return 1.0;
    return Zero3DEngineNativeBindings.instance.ecsGetEntityScale(
      ecsWorldPointer,
      entityId,
    );
  }

  /// Updates the 3D transform `(x, y, z, scale)` of `[entityId]` in `Zero3DEcsWorld`.
  void setEntityTransform({
    required int entityId,
    double? x,
    double? y,
    double? z,
    double? scale,
  }) {
    if (_isDisposed || ecsWorldPointer.address == 0) return;
    final double nx = x ?? getEntityX(entityId);
    final double ny = y ?? getEntityY(entityId);
    final double nz = z ?? getEntityZ(entityId);
    final double ns = scale ?? getEntityScale(entityId);
    Zero3DEngineNativeBindings.instance.ecsSetEntityTransform(
      ecsWorldPointer,
      entityId,
      nx,
      ny,
      nz,
      ns,
    );
    _revision.add(1);
  }

  /// Fires a 3D ray from the camera through normalized device coordinates `(ndcX, ndcY)`
  /// in `[-1.0 .. 1.0]` and selects the closest intersected ECS entity.
  int raycastPick(double ndcX, double ndcY) {
    if (_isDisposed || !_view.isValid || ecsWorldPointer.address == 0) {
      return -1;
    }
    final int hitId = Zero3DEngineNativeBindings.instance.ecsRaycastPick(
      ecsWorldPointer,
      statePointer,
      ndcX,
      ndcY,
    );
    if (hitId >= 0) {
      _revision.add(1);
    }
    return hitId;
  }

  /// Spawns a 3D entity in the C++ SoA ECS world (`Zero3DEcsWorld`).
  int spawnEcsEntity({
    required double x,
    required double y,
    required double z,
    double scale = 1.0,
    double boundRadius = 0.6,
    int clusterCount = 64,
  }) {
    if (_isDisposed || ecsWorldPointer.address == 0) return -1;
    final int id = Zero3DEngineNativeBindings.instance.ecsSpawnEntity(
      ecsWorldPointer,
      x,
      y,
      z,
      scale,
      boundRadius,
      clusterCount,
    );
    if (id >= 0) {
      _spawnedEntityCount = id + 1;
      _revision.add(1);
    }
    return id;
  }

  /// Evaluates Nanite cluster culling and projects visible meshlets into pre-allocated
  /// screen-space `[outPositions]` and `[outColors]` buffers (0 heap allocations).
  int evaluateAndProjectNaniteClusters({
    required double centerX,
    required double centerY,
    required double scale,
    required Float32List outPositions,
    required Int32List outColors,
  }) {
    if (_isDisposed || !_view.isValid) return 0;
    final double yaw = _view.cameraYaw;
    final double pitch = _view.cameraPitch;
    final double camDist = _view.cameraDistance;
    final double lodLimit = _view.lodErrorThreshold;
    final int mode = _view.renderModeRaw;

    final double cy = math.cos(yaw), sy = math.sin(yaw);
    final double cp = math.cos(pitch), sp = math.sin(pitch);

    int emittedTris = 0;
    final int maxTris = outPositions.length ~/ 6;

    for (int c = 0; c < maxDagClusters; c++) {
      final double wx = _clusterCenterX[c];
      final double wy = _clusterCenterY[c];
      final double wz = _clusterCenterZ[c];

      final double rx = wx * cy - wz * sy;
      final double rz0 = wx * sy + wz * cy;
      final double ry = wy * cp - rz0 * sp;
      final double rz = wy * sp + rz0 * cp;
      final double depth = camDist - rz;
      if (depth <= 0.35) continue;

      final double projErr = (_clusterBaseError[c] * 2.4) / depth;
      if (projErr > lodLimit * 2.2 && _clusterLodLevel[c] > 1) continue;

      emittedTris = _emitClusterQuadTriangles(
        clusterIndex: c,
        lodLevel: _clusterLodLevel[c],
        renderMode: mode,
        screenX: centerX + (rx / depth) * scale,
        screenY: centerY - (ry / depth) * scale,
        screenRadius: (_clusterRadius[c] / depth) * scale,
        emittedTris: emittedTris,
        maxTris: maxTris,
        outPositions: outPositions,
        outColors: outColors,
      );
    }
    return emittedTris;
  }

  int _emitClusterQuadTriangles({
    required int clusterIndex,
    required int lodLevel,
    required int renderMode,
    required double screenX,
    required double screenY,
    required double screenRadius,
    required int emittedTris,
    required int maxTris,
    required Float32List outPositions,
    required Int32List outColors,
  }) {
    if (emittedTris + 2 > maxTris) return emittedTris;
    final int col = _colorForCluster(clusterIndex, lodLevel, renderMode);
    final double r = screenRadius.clamp(2.0, 64.0);

    final int p = emittedTris * 6;
    // Triangle 0
    outPositions[p] = screenX - r;
    outPositions[p + 1] = screenY - r;
    outPositions[p + 2] = screenX + r;
    outPositions[p + 3] = screenY - r;
    outPositions[p + 4] = screenX + r;
    outPositions[p + 5] = screenY + r;
    // Triangle 1
    outPositions[p + 6] = screenX - r;
    outPositions[p + 7] = screenY - r;
    outPositions[p + 8] = screenX + r;
    outPositions[p + 9] = screenY + r;
    outPositions[p + 10] = screenX - r;
    outPositions[p + 11] = screenY + r;

    final int cBase = emittedTris * 3;
    for (int k = 0; k < 6; k++) {
      outColors[cBase + k] = col;
    }
    return emittedTris + 2;
  }

  int _colorForCluster(int idx, int lod, int mode) {
    if (mode == Zero3DRenderMode.naniteClusters.index) {
      final int r = ((idx * 73) & 0x7F) + 100;
      final int g = ((idx * 151) & 0x7F) + 90;
      final int b = ((lod * 60 + 80) & 0xFF);
      return ((0xFF << 24) | (r << 16) | (g << 8) | b).toSigned(32);
    }
    final int shade = (220 - lod * 35).clamp(80, 240);
    return ((0xFF << 24) | (30 << 16) | (shade << 8) | 250).toSigned(32);
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

  /// Disposes the native 3D engine texture and C++ shared state (idempotent).
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _revision.dispose();
    if (_ownsState && ecsWorldPointer.address != 0) {
      Zero3DEngineNativeBindings.instance.ecsDestroyWorld(ecsWorldPointer);
    }
    if (_ownsState && statePointer.address != 0) {
      Zero3DEngineNativeBindings.instance.destroyState(statePointer);
    }
    if (textureId != -1) {
      try {
        await _channel.invokeMethod('dispose', {'textureId': textureId});
      } catch (_) {}
    }
  }
}

import 'dart:ffi' as ffi;
import 'dart:io';

/// 3D rendering pipeline mode corresponding to `Zero3DRenderMode`.
enum Zero3DRenderMode {
  /// Hybrid Nanite cluster culling + hardware ray tracing (shadows/reflections).
  hybridNaniteRt,

  /// Full hardware ray-traced global illumination & reflections.
  raytracingGi,

  /// Unreal Engine 5 Nanite-style meshlet cluster & LOD heatmap visualization.
  naniteClusters,

  /// Frustum & backface culling wireframe verification view.
  wireframeCull,
}

/// Frame-rate scheduling mode corresponding to `Zero3DFpsMode`.
enum Zero3DFpsMode {
  /// Synchronize with the monitor's native peak refresh rate (120Hz / 144Hz / 240Hz).
  vsyncNative,

  /// Target 120 FPS.
  cap120,

  /// Target 144 FPS (for 144Hz gaming monitors).
  cap144,

  /// Target 240 FPS (for 240Hz gaming monitors).
  cap240,

  /// Uncapped render loop (decoupled from VSync: 300–1000+ FPS).
  uncapped,
}

/// Engine runtime status corresponding to `Zero3DEngineStatus`.
enum Zero3DEngineStatus {
  /// Engine is idle.
  idle,

  /// Engine is actively rendering frames.
  rendering,

  /// Engine rendering is paused.
  paused,

  /// Engine encountered a hardware or initialization error.
  error,
}

/// Exact 128-byte (2 cache lines) Dart FFI struct matching C++ `Zero3DEngineState`.
final class Zero3DEngineStateNative extends ffi.Struct {
  // --- Cache Line 0 (Offsets 0..63): Dart -> Native ---
  @ffi.Float()
  external double cameraYaw;

  @ffi.Float()
  external double cameraPitch;

  @ffi.Float()
  external double cameraDistance;

  @ffi.Float()
  external double cameraFovDeg;

  @ffi.Float()
  external double targetX;

  @ffi.Float()
  external double targetY;

  @ffi.Float()
  external double targetZ;

  @ffi.Float()
  external double lightAzimuth;

  @ffi.Float()
  external double lightElevation;

  @ffi.Float()
  external double lodErrorThreshold;

  @ffi.Int32()
  external int renderMode;

  @ffi.Int32()
  external int fpsMode;

  @ffi.Int32()
  external int targetFpsLimit;

  @ffi.Int32()
  external int maxRayBounces;

  @ffi.Uint32()
  external int cmdSeq;

  @ffi.Uint32()
  external int magicGuard;

  // --- Cache Line 1 (Offsets 64..127): Native -> Dart Telemetry ---
  @ffi.Uint64()
  external int frameCount;

  @ffi.Int64()
  external int lastFrameTimeUs;

  @ffi.Float()
  external double renderFps;

  @ffi.Float()
  external double frameTimeMs;

  @ffi.Float()
  external double displayRefreshHz;

  @ffi.Int32()
  external int status;

  @ffi.Int32()
  external int viewportWidth;

  @ffi.Int32()
  external int viewportHeight;

  @ffi.Int32()
  external int activeClusters;

  @ffi.Int32()
  external int visibleTriangles;

  @ffi.Int32()
  external int culledClusters;

  @ffi.Int32()
  external int raysTracedK;

  @ffi.Uint32()
  external int telemetrySeq;

  @ffi.Uint32()
  external int reservedPad;
}

/// Zero-overhead direct memory view over [Zero3DEngineStateNative].
final class Zero3DEngineStateView {
  /// Expected magic canary value (`0x5A334445` = `"Z3DE"`).
  static const int magicAlive = 0x5A334445;

  // 4-byte stride indices
  static const int _idxCameraYaw = 0;
  static const int _idxCameraPitch = 1;
  static const int _idxCameraDist = 2;
  static const int _idxCameraFov = 3;
  static const int _idxTargetX = 4;
  static const int _idxTargetY = 5;
  static const int _idxTargetZ = 6;
  static const int _idxLightAzimuth = 7;
  static const int _idxLightElevation = 8;
  static const int _idxLodError = 9;
  static const int _idxRenderMode = 10;
  static const int _idxFpsMode = 11;
  static const int _idxMaxBounces = 13;
  static const int _idxMagicGuard = 15; // offset 60

  // Cache Line 1 (offset 64+)
  static const int _idxFrameCountU64 = 8; // offset 64 (8-byte stride)
  static const int _idxRenderFps = 20; // offset 80 (4-byte stride)
  static const int _idxFrameTimeMs = 21; // offset 84
  static const int _idxDisplayHz = 22; // offset 88
  static const int _idxStatus = 23; // offset 92
  static const int _idxViewportW = 24; // offset 96
  static const int _idxViewportH = 25; // offset 100
  static const int _idxActiveClusters = 26; // offset 104
  static const int _idxVisibleTris = 27; // offset 108
  static const int _idxCulledClusters = 28; // offset 112
  static const int _idxRaysTracedK = 29; // offset 116

  final ffi.Pointer<Zero3DEngineStateNative> pointer;
  final ffi.Pointer<ffi.Uint64> _u64;
  final ffi.Pointer<ffi.Int32> _i32;
  final ffi.Pointer<ffi.Uint32> _u32;
  final ffi.Pointer<ffi.Float> _f32;

  /// Creates a direct typed pointer view over [pointer].
  Zero3DEngineStateView(this.pointer)
      : _u64 = pointer.cast<ffi.Uint64>(),
        _i32 = pointer.cast<ffi.Int32>(),
        _u32 = pointer.cast<ffi.Uint32>(),
        _f32 = pointer.cast<ffi.Float>();

  /// Checks 64-byte alignment and the magic canary without risking unaligned faults.
  @pragma('vm:prefer-inline')
  bool get isValid {
    final int addr = pointer.address;
    if (addr == 0 || (addr & 63) != 0) return false;
    return _u32[_idxMagicGuard] == magicAlive;
  }

  @pragma('vm:prefer-inline')
  double get cameraYaw => isValid ? _f32[_idxCameraYaw] : 0.45;

  @pragma('vm:prefer-inline')
  double get cameraPitch => isValid ? _f32[_idxCameraPitch] : 0.32;

  @pragma('vm:prefer-inline')
  double get cameraDistance => isValid ? _f32[_idxCameraDist] : 3.8;

  @pragma('vm:prefer-inline')
  double get cameraFovDeg => isValid ? _f32[_idxCameraFov] : 60.0;

  @pragma('vm:prefer-inline')
  double get targetX => isValid ? _f32[_idxTargetX] : 0.0;

  @pragma('vm:prefer-inline')
  double get targetY => isValid ? _f32[_idxTargetY] : 0.0;

  @pragma('vm:prefer-inline')
  double get targetZ => isValid ? _f32[_idxTargetZ] : 0.0;

  @pragma('vm:prefer-inline')
  double get lightAzimuth => isValid ? _f32[_idxLightAzimuth] : 0.78;

  @pragma('vm:prefer-inline')
  double get lightElevation => isValid ? _f32[_idxLightElevation] : 0.85;

  @pragma('vm:prefer-inline')
  double get lodErrorThreshold => isValid ? _f32[_idxLodError] : 1.0;

  @pragma('vm:prefer-inline')
  int get renderModeRaw => isValid ? _i32[_idxRenderMode] : 0;

  @pragma('vm:prefer-inline')
  int get fpsModeRaw => isValid ? _i32[_idxFpsMode] : 0;

  @pragma('vm:prefer-inline')
  int get maxRayBounces => isValid ? _i32[_idxMaxBounces] : 2;

  @pragma('vm:prefer-inline')
  int get frameCount => isValid ? _u64[_idxFrameCountU64] : 0;

  @pragma('vm:prefer-inline')
  double get renderFps => isValid ? _f32[_idxRenderFps] : 0.0;

  @pragma('vm:prefer-inline')
  double get frameTimeMs => isValid ? _f32[_idxFrameTimeMs] : 0.0;

  @pragma('vm:prefer-inline')
  double get displayRefreshHz => isValid ? _f32[_idxDisplayHz] : 60.0;

  @pragma('vm:prefer-inline')
  int get statusRaw => isValid ? _i32[_idxStatus] : 0;

  @pragma('vm:prefer-inline')
  int get viewportWidth => isValid ? _i32[_idxViewportW] : 0;

  @pragma('vm:prefer-inline')
  int get viewportHeight => isValid ? _i32[_idxViewportH] : 0;

  @pragma('vm:prefer-inline')
  int get activeClusters => isValid ? _i32[_idxActiveClusters] : 0;

  @pragma('vm:prefer-inline')
  int get visibleTriangles => isValid ? _i32[_idxVisibleTris] : 0;

  @pragma('vm:prefer-inline')
  int get culledClusters => isValid ? _i32[_idxCulledClusters] : 0;

  @pragma('vm:prefer-inline')
  int get raysTracedK => isValid ? _i32[_idxRaysTracedK] : 0;
}

typedef _NativeCreateState = ffi.Pointer<Zero3DEngineStateNative> Function();
typedef Dart3DCreateState = ffi.Pointer<Zero3DEngineStateNative> Function();

typedef _NativeDestroyState = ffi.Void Function(
    ffi.Pointer<Zero3DEngineStateNative>);
typedef Dart3DDestroyState = void Function(
    ffi.Pointer<Zero3DEngineStateNative>);

typedef _NativeSetCameraOrbit = ffi.Void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  ffi.Float,
  ffi.Float,
  ffi.Float,
  ffi.Float,
);
typedef Dart3DSetCameraOrbit = void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  double,
  double,
  double,
  double,
);

typedef _NativeSetCameraTarget = ffi.Void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  ffi.Float,
  ffi.Float,
  ffi.Float,
);
typedef Dart3DSetCameraTarget = void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  double,
  double,
  double,
);

typedef _NativeSetLightAngles = ffi.Void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  ffi.Float,
  ffi.Float,
);
typedef Dart3DSetLightAngles = void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  double,
  double,
);

typedef _NativeSetPipelineConfig = ffi.Void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Float,
  ffi.Int32,
);
typedef Dart3DSetPipelineConfig = void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  int,
  int,
  int,
  double,
  int,
);

typedef _NativeSimulateStep = ffi.Void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  ffi.Int32,
  ffi.Float,
);
typedef Dart3DSimulateStep = void Function(
  ffi.Pointer<Zero3DEngineStateNative>,
  int,
  double,
);

/// Opaque FFI handle to C++ `Zero3DEcsWorld`.
final class Zero3DEcsWorldNative extends ffi.Opaque {}

typedef _NativeEcsCreateWorld = ffi.Pointer<Zero3DEcsWorldNative> Function();
typedef Dart3DEcsCreateWorld = ffi.Pointer<Zero3DEcsWorldNative> Function();

typedef _NativeEcsDestroyWorld = ffi.Void Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
);
typedef Dart3DEcsDestroyWorld = void Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
);

typedef _NativeEcsSpawnEntity = ffi.Int32 Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  ffi.Float,
  ffi.Float,
  ffi.Float,
  ffi.Float,
  ffi.Float,
  ffi.Int32,
);
typedef Dart3DEcsSpawnEntity = int Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  double,
  double,
  double,
  double,
  double,
  int,
);

typedef _NativeEcsCullAndUpdate = ffi.Int32 Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  ffi.Pointer<Zero3DEngineStateNative>,
  ffi.Float,
);
typedef Dart3DEcsCullAndUpdate = int Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  ffi.Pointer<Zero3DEngineStateNative>,
  double,
);

typedef _NativeEcsGetInt = ffi.Int32 Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
);
typedef Dart3DEcsGetInt = int Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
);

typedef _NativeEcsSetInt = ffi.Void Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  ffi.Int32,
);
typedef Dart3DEcsSetInt = void Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  int,
);

typedef _NativeEcsSetTransform = ffi.Void Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  ffi.Int32,
  ffi.Float,
  ffi.Float,
  ffi.Float,
  ffi.Float,
);
typedef Dart3DEcsSetTransform = void Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  int,
  double,
  double,
  double,
  double,
);

typedef _NativeEcsGetEntityFloat = ffi.Float Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  ffi.Int32,
);
typedef Dart3DEcsGetEntityFloat = double Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  int,
);

typedef _NativeEcsRaycastPick = ffi.Int32 Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  ffi.Pointer<Zero3DEngineStateNative>,
  ffi.Float,
  ffi.Float,
);
typedef Dart3DEcsRaycastPick = int Function(
  ffi.Pointer<Zero3DEcsWorldNative>,
  ffi.Pointer<Zero3DEngineStateNative>,
  double,
  double,
);

typedef _NativePackVisBuffer64 = ffi.Uint64 Function(
  ffi.Float,
  ffi.Uint32,
  ffi.Uint32,
);
typedef Dart3DPackVisBuffer64 = int Function(double, int, int);

typedef _NativeUnpackVisBuffer32 = ffi.Uint32 Function(ffi.Uint64);
typedef Dart3DUnpackVisBuffer32 = int Function(int);

/// Low-overhead `isLeaf: true` FFI bindings for `d_zero_3dengine`.
class Zero3DEngineNativeBindings {
  /// Singleton binding instance.
  static final Zero3DEngineNativeBindings instance =
      Zero3DEngineNativeBindings._();

  late final ffi.DynamicLibrary _dylib;

  /// Allocates a 128-byte cache-aligned `Zero3DEngineState`.
  late final Dart3DCreateState createState;

  /// Safely destroys a `Zero3DEngineState` (idempotent via magic canary).
  late final Dart3DDestroyState destroyState;

  /// Updates camera orbit angles and FOV atomically via seqlock.
  late final Dart3DSetCameraOrbit setCameraOrbit;

  /// Updates 3D camera target position (`tx, ty, tz`) atomically via seqlock.
  late final Dart3DSetCameraTarget setCameraTarget;

  /// Updates directional light angles atomically via seqlock.
  late final Dart3DSetLightAngles setLightAngles;

  /// Updates Nanite & Ray Tracing pipeline settings atomically via seqlock.
  late final Dart3DSetPipelineConfig setPipelineConfig;

  /// Runs a deterministic Nanite DAG culling and telemetry step in C++.
  late final Dart3DSimulateStep simulateFrameStep;

  /// Allocates a 64-byte aligned C++ SoA `Zero3DEcsWorld`.
  late final Dart3DEcsCreateWorld ecsCreateWorld;

  /// Safely destroys a `Zero3DEcsWorld` (idempotent via magic canary).
  late final Dart3DEcsDestroyWorld ecsDestroyWorld;

  /// Spawns a 3D entity in the C++ SoA ECS world and returns its entity index.
  late final Dart3DEcsSpawnEntity ecsSpawnEntity;

  /// Performs SIMD-friendly distance/frustum culling across ECS entities and updates state.
  late final Dart3DEcsCullAndUpdate ecsCullAndUpdateState;

  /// Returns active entity count in `Zero3DEcsWorld`.
  late final Dart3DEcsGetInt ecsGetEntityCount;

  /// Returns currently selected entity ID (`-1` if none).
  late final Dart3DEcsGetInt ecsGetSelectedEntity;

  /// Sets currently selected entity ID.
  late final Dart3DEcsSetInt ecsSetSelectedEntity;

  /// Updates an entity's 3D world position `(x, y, z)` and `scale`.
  late final Dart3DEcsSetTransform ecsSetEntityTransform;

  /// Reads an entity's X coordinate.
  late final Dart3DEcsGetEntityFloat ecsGetEntityX;

  /// Reads an entity's Y coordinate.
  late final Dart3DEcsGetEntityFloat ecsGetEntityY;

  /// Reads an entity's Z coordinate.
  late final Dart3DEcsGetEntityFloat ecsGetEntityZ;

  /// Reads an entity's uniform scale.
  late final Dart3DEcsGetEntityFloat ecsGetEntityScale;

  /// Performs a 3D ray-sphere intersection pick test against all ECS entities.
  late final Dart3DEcsRaycastPick ecsRaycastPick;

  /// Packs normalized depth, cluster ID, and triangle ID into a 64-bit Visibility Buffer pixel.
  late final Dart3DPackVisBuffer64 packVisBuffer64;

  /// Unpacks the 24-bit Nanite Cluster ID from a 64-bit Visibility Buffer pixel.
  late final Dart3DUnpackVisBuffer32 unpackVisBufferCluster;

  /// Unpacks the 8-bit Triangle ID from a 64-bit Visibility Buffer pixel.
  late final Dart3DUnpackVisBuffer32 unpackVisBufferTriangle;

  Zero3DEngineNativeBindings._() {
    _dylib = _loadLibrary();
    createState = _dylib.lookupFunction<_NativeCreateState, Dart3DCreateState>(
      'zero_3d_create_state',
      isLeaf: true,
    );
    destroyState =
        _dylib.lookupFunction<_NativeDestroyState, Dart3DDestroyState>(
      'zero_3d_destroy_state',
      isLeaf: true,
    );
    setCameraOrbit =
        _dylib.lookupFunction<_NativeSetCameraOrbit, Dart3DSetCameraOrbit>(
      'zero_3d_set_camera_orbit',
      isLeaf: true,
    );
    setCameraTarget =
        _dylib.lookupFunction<_NativeSetCameraTarget, Dart3DSetCameraTarget>(
      'zero_3d_set_camera_target',
      isLeaf: true,
    );
    setLightAngles =
        _dylib.lookupFunction<_NativeSetLightAngles, Dart3DSetLightAngles>(
      'zero_3d_set_light_angles',
      isLeaf: true,
    );
    setPipelineConfig = _dylib
        .lookupFunction<_NativeSetPipelineConfig, Dart3DSetPipelineConfig>(
      'zero_3d_set_pipeline_config',
      isLeaf: true,
    );
    simulateFrameStep =
        _dylib.lookupFunction<_NativeSimulateStep, Dart3DSimulateStep>(
      'zero_3d_simulate_frame_step',
      isLeaf: true,
    );
    ecsCreateWorld =
        _dylib.lookupFunction<_NativeEcsCreateWorld, Dart3DEcsCreateWorld>(
      'zero_3d_ecs_create_world',
      isLeaf: true,
    );
    ecsDestroyWorld =
        _dylib.lookupFunction<_NativeEcsDestroyWorld, Dart3DEcsDestroyWorld>(
      'zero_3d_ecs_destroy_world',
      isLeaf: true,
    );
    ecsSpawnEntity =
        _dylib.lookupFunction<_NativeEcsSpawnEntity, Dart3DEcsSpawnEntity>(
      'zero_3d_ecs_spawn_entity',
      isLeaf: true,
    );
    ecsCullAndUpdateState = _dylib
        .lookupFunction<_NativeEcsCullAndUpdate, Dart3DEcsCullAndUpdate>(
      'zero_3d_ecs_cull_and_update_state',
      isLeaf: true,
    );
    ecsGetEntityCount =
        _dylib.lookupFunction<_NativeEcsGetInt, Dart3DEcsGetInt>(
      'zero_3d_ecs_get_entity_count',
      isLeaf: true,
    );
    ecsGetSelectedEntity =
        _dylib.lookupFunction<_NativeEcsGetInt, Dart3DEcsGetInt>(
      'zero_3d_ecs_get_selected_entity',
      isLeaf: true,
    );
    ecsSetSelectedEntity =
        _dylib.lookupFunction<_NativeEcsSetInt, Dart3DEcsSetInt>(
      'zero_3d_ecs_set_selected_entity',
      isLeaf: true,
    );
    ecsSetEntityTransform =
        _dylib.lookupFunction<_NativeEcsSetTransform, Dart3DEcsSetTransform>(
      'zero_3d_ecs_set_entity_transform',
      isLeaf: true,
    );
    ecsGetEntityX = _dylib
        .lookupFunction<_NativeEcsGetEntityFloat, Dart3DEcsGetEntityFloat>(
      'zero_3d_ecs_get_entity_x',
      isLeaf: true,
    );
    ecsGetEntityY = _dylib
        .lookupFunction<_NativeEcsGetEntityFloat, Dart3DEcsGetEntityFloat>(
      'zero_3d_ecs_get_entity_y',
      isLeaf: true,
    );
    ecsGetEntityZ = _dylib
        .lookupFunction<_NativeEcsGetEntityFloat, Dart3DEcsGetEntityFloat>(
      'zero_3d_ecs_get_entity_z',
      isLeaf: true,
    );
    ecsGetEntityScale = _dylib
        .lookupFunction<_NativeEcsGetEntityFloat, Dart3DEcsGetEntityFloat>(
      'zero_3d_ecs_get_entity_scale',
      isLeaf: true,
    );
    ecsRaycastPick =
        _dylib.lookupFunction<_NativeEcsRaycastPick, Dart3DEcsRaycastPick>(
      'zero_3d_ecs_raycast_pick',
      isLeaf: true,
    );
    packVisBuffer64 =
        _dylib.lookupFunction<_NativePackVisBuffer64, Dart3DPackVisBuffer64>(
      'zero_3d_pack_visbuffer64',
      isLeaf: true,
    );
    unpackVisBufferCluster = _dylib
        .lookupFunction<_NativeUnpackVisBuffer32, Dart3DUnpackVisBuffer32>(
      'zero_3d_unpack_visbuffer_cluster',
      isLeaf: true,
    );
    unpackVisBufferTriangle = _dylib
        .lookupFunction<_NativeUnpackVisBuffer32, Dart3DUnpackVisBuffer32>(
      'zero_3d_unpack_visbuffer_triangle',
      isLeaf: true,
    );
  }

  static bool _isTestOrDebugEnvironment() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
    bool inDebug = false;
    assert(() {
      inDebug = true;
      return true;
    }());
    return inDebug;
  }

  static ffi.DynamicLibrary? _loadMacOSTestFallback() {
    if (!_isTestOrDebugEnvironment()) return null;
    const candidates = <String>[
      'test/libzero_3dengine_test.dylib',
      'packages/d_zero_3dengine/test/libzero_3dengine_test.dylib',
      'src/libzero_3dengine_native.dylib',
      'packages/d_zero_3dengine/src/libzero_3dengine_native.dylib',
    ];
    for (final rel in candidates) {
      final f = File(rel);
      if (f.existsSync()) {
        return ffi.DynamicLibrary.open(f.absolute.path);
      }
    }
    return _buildMacOSTestDylib();
  }

  static ffi.DynamicLibrary? _buildMacOSTestDylib() {
    const targets = <(String, String)>[
      ('src/zero_3d_engine_state.cpp', 'test/libzero_3dengine_test.dylib'),
      (
        'packages/d_zero_3dengine/src/zero_3d_engine_state.cpp',
        'packages/d_zero_3dengine/test/libzero_3dengine_test.dylib',
      ),
    ];
    for (final (srcPath, outPath) in targets) {
      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) continue;
      final res = Process.runSync('clang++', [
        '-std=c++17',
        '-O2',
        '-dynamiclib',
        srcFile.path,
        '-o',
        outPath,
      ]);
      if (res.exitCode == 0 && File(outPath).existsSync()) {
        return ffi.DynamicLibrary.open(File(outPath).absolute.path);
      }
    }
    return null;
  }

  static ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isIOS) return ffi.DynamicLibrary.process();
    if (Platform.isMacOS) {
      final proc = ffi.DynamicLibrary.process();
      if (proc.providesSymbol('zero_3d_create_state')) return proc;
      return _loadMacOSTestFallback() ?? proc;
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return ffi.DynamicLibrary.open('libzero_3dengine_native.so');
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('zero_3dengine_native.dll');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

#ifndef ZERO_3D_ENGINE_STATE_H
#define ZERO_3D_ENGINE_STATE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
#include <atomic>
extern "C" {
#endif

// レンダリングパイプラインモード
typedef enum {
    ZERO_3D_MODE_HYBRID_NANITE_RT = 0, // Nanite クラスタカリング + Ray Tracing ハイブリッド
    ZERO_3D_MODE_RAYTRACING_GI    = 1, // フル・レイトレーシング (Reflections + Shadows + AO/GI)
    ZERO_3D_MODE_NANITE_CLUSTERS  = 2, // Nanite Meshlet クラスタ & LOD 可視化 (UE5 Cluster View)
    ZERO_3D_MODE_WIREFRAME_CULL   = 3  // 視錘台・背面カリング検証モード
} Zero3DRenderMode;

// フレームレート駆動モード (60Hz / 120Hz / 144Hz / 240Hz / Uncapped)
typedef enum {
    ZERO_3D_FPS_VSYNC_NATIVE = 0, // モニターのネイティブ最大リフレッシュレート (120/144/165/240Hz) に同期
    ZERO_3D_FPS_CAP_120      = 1, // 120 FPS ターゲット
    ZERO_3D_FPS_CAP_144      = 2, // 144 FPS ターゲット (144Hz ゲーミングモニター向け)
    ZERO_3D_FPS_CAP_240      = 3, // 240 FPS ターゲット (240Hz ゲーミングモニター向け)
    ZERO_3D_FPS_UNCAPPED     = 4  // VSync 解除・上限解放 (Render Thread 最速駆動: 300~1000+ FPS)
} Zero3DFpsMode;

// エンジンの動作ステータス
typedef enum {
    ZERO_3D_STATUS_IDLE      = 0,
    ZERO_3D_STATUS_RENDERING = 1,
    ZERO_3D_STATUS_PAUSED    = 2,
    ZERO_3D_STATUS_ERROR     = 3
} Zero3DEngineStatus;

// =========================================================================================
// Dart と Native (C++ / Metal 3 / DirectX 12 / Vulkan) で直接共有するメモリブロック
// alignas(64) で 2 キャッシュライン (128 bytes) に厳密固定し、
// [Cache Line 0 (0..63)]   : Dart ──(Write)──> Native (Camera / Light / Mode / FPS Cap)
// [Cache Line 1 (64..127)] : Native ──(Write)──> Dart (FPS / FrameTime / Nanite Clusters / Rays)
// と完全に分離することで、CPU コア間のキャッシュコヒーレンシ競合（False Sharing）を 100% 根絶する。
// =========================================================================================
#ifdef __cplusplus
struct alignas(64) Zero3DEngineState {
    // --- Cache Line 0 (Offsets 0..63): Dart UI/Game Logic -> Native Render Thread ---
    std::atomic<float> camera_yaw;          // offset  0: カメラ水平回転角 (radians)
    std::atomic<float> camera_pitch;        // offset  4: カメラ垂直回転角 (radians, clamped)
    std::atomic<float> camera_distance;     // offset  8: カメラ距離 (> 0.5m)
    std::atomic<float> camera_fov_deg;      // offset 12: 垂直視野角 (degrees, 20..120)
    std::atomic<float> target_x;            // offset 16: 注視点 X
    std::atomic<float> target_y;            // offset 20: 注視点 Y
    std::atomic<float> target_z;            // offset 24: 注視点 Z
    std::atomic<float> light_azimuth;       // offset 28: 太陽/ディレクショナルライト方位角 (radians)
    std::atomic<float> light_elevation;     // offset 32: ライト仰角 (radians)
    std::atomic<float> lod_error_threshold; // offset 36: Nanite 画面空間許容誤差 (pixels, 0.25..8.0)
    std::atomic<int32_t> render_mode;       // offset 40: Zero3DRenderMode
    std::atomic<int32_t> fps_mode;          // offset 44: Zero3DFpsMode (VSync / 144Hz / 240Hz / Uncapped)
    std::atomic<int32_t> target_fps_limit;  // offset 48: カスタム FPS 上限 (0 = 無制限)
    std::atomic<int32_t> max_ray_bounces;   // offset 52: レイトレーシング最大反射バウンス数 (1..8)
    std::atomic<uint32_t> cmd_seq;          // offset 56: Seqlock カウンタ (Dart 書き込み中は奇数)
    std::atomic<uint32_t> magic_guard;      // offset 60: 生存確認カナリア値 (0x5A334445 = "Z3DE")

    // --- Cache Line 1 (Offsets 64..127): Native Render Thread -> Dart Telemetry HUD ---
    std::atomic<uint64_t> frame_count;      // offset 64: 描画完了した総フレーム数
    std::atomic<int64_t> last_frame_time_us;// offset 72: 最終フレーム描画タイムスタンプ (単調時計 us)
    std::atomic<float> render_fps;          // offset 80: Native Render 実測 FPS (120 / 144 / 240 / 500+)
    std::atomic<float> frame_time_ms;       // offset 84: 1フレームあたりの GPU/Render 処理時間 (ms)
    std::atomic<float> display_refresh_hz;  // offset 88: 検出されたモニターのリフレッシュレート (60/120/144/240Hz)
    std::atomic<int32_t> status;            // offset 92: Zero3DEngineStatus
    std::atomic<int32_t> viewport_width;    // offset 96: レンダーターゲット幅 (px)
    std::atomic<int32_t> viewport_height;   // offset 100: レンダーターゲット高さ (px)
    std::atomic<int32_t> active_clusters;   // offset 104: カリング通過した Nanite アクティブクラスタ数
    std::atomic<int32_t> visible_triangles; // offset 108: ラスタライズ/RT 対象の可視三角形数
    std::atomic<int32_t> culled_clusters;   // offset 112: 視錘台/Hi-Z/背面カリングで棄却されたクラスタ数
    std::atomic<int32_t> rays_traced_k;     // offset 116: フレームあたり発射されたレイ数 (×1,000 rays)
    std::atomic<uint32_t> telemetry_seq;    // offset 120: Seqlock カウンタ (Native 書き込み中は奇数)
    uint32_t reserved_pad;                  // offset 124: 128-byte アライメントパディング
};

static_assert(sizeof(Zero3DEngineState) == 128, "Zero3DEngineState must be exactly 128 bytes (2 cache lines)");
static_assert(alignof(Zero3DEngineState) == 64, "Zero3DEngineState must be 64-byte cache-line aligned");
#else
typedef struct Zero3DEngineState Zero3DEngineState;
#endif

#if defined(_WIN32)
#define ZERO_3D_EXPORT __declspec(dllexport)
#else
#define ZERO_3D_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// メモリ安全性カナリア定数 ("Z3DE")
#define ZERO_3D_MAGIC_ALIVE 0x5A334445u
#define ZERO_3D_MAGIC_FREED 0xDEAD3344u

// =========================================================================================
// Nanite Meshlet Cluster Descriptor (32 bytes, 32-byte aligned)
// 1 Cluster = 64 Vertices / 128 Triangles の境界球・法線コーン・LOD 階層誤差を表す
// =========================================================================================
#ifdef __cplusplus
struct alignas(32) Zero3DNaniteCluster {
    float center_x;       // offset  0: バウンディングスフィア中心 X
    float center_y;       // offset  4: バウンディングスフィア中心 Y
    float center_z;       // offset  8: バウンディングスフィア中心 Z
    float radius;         // offset 12: バウンディングスフィア半径 (> 0)
    float cone_axis_x;    // offset 16: 法線コーン軸 X (背面クラスタ一括棄却用)
    float cone_axis_y;    // offset 20: 法線コーン軸 Y
    float cone_axis_z;    // offset 24: 法線コーン軸 Z
    float lod_error;      // offset 28: 画面空間投影誤差基準値 (pixels at 1m)
};
static_assert(sizeof(Zero3DNaniteCluster) == 32, "Zero3DNaniteCluster must be 32 bytes");
#else
typedef struct Zero3DNaniteCluster Zero3DNaniteCluster;
#endif

// =========================================================================================
// Zero-Allocation SoA Entity Component System (ECS) World
// 最大 1,024 エンティティの Transform / Bounding Radius / Meshlet Cluster 範囲を連続配列で保持
// =========================================================================================
#define ZERO_3D_ECS_MAX_ENTITIES 1024
#define ZERO_3D_ECS_MAGIC_ALIVE 0x5A454353u // "ZECS"
#define ZERO_3D_ECS_MAGIC_FREED 0xDEAD4543u

#ifdef __cplusplus
struct alignas(64) Zero3DEcsWorld {
    std::atomic<uint32_t> magic_guard;     // 生存確認カナリア ("ZECS")
    std::atomic<int32_t> entity_count;     // アクティブエンティティ数 (0..1024)
    std::atomic<int32_t> selected_entity;  // 選択中エンティティ ID (-1 = 未選択)
    alignas(64) float pos_x[ZERO_3D_ECS_MAX_ENTITIES];
    alignas(64) float pos_y[ZERO_3D_ECS_MAX_ENTITIES];
    alignas(64) float pos_z[ZERO_3D_ECS_MAX_ENTITIES];
    alignas(64) float rot_yaw[ZERO_3D_ECS_MAX_ENTITIES];
    alignas(64) float scale[ZERO_3D_ECS_MAX_ENTITIES];
    alignas(64) float bound_radius[ZERO_3D_ECS_MAX_ENTITIES];
    alignas(64) int32_t cluster_count[ZERO_3D_ECS_MAX_ENTITIES];
    alignas(64) uint8_t visible_mask[ZERO_3D_ECS_MAX_ENTITIES];
};
#else
typedef struct Zero3DEcsWorld Zero3DEcsWorld;
#endif

// 1. 共有メモリライフサイクル (作成・破棄・生存検証)
ZERO_3D_EXPORT Zero3DEngineState* zero_3d_create_state(void);
ZERO_3D_EXPORT void zero_3d_destroy_state(Zero3DEngineState* state);
ZERO_3D_EXPORT bool zero_3d_is_state_valid(const Zero3DEngineState* state);
ZERO_3D_EXPORT int64_t zero_3d_now_us(void);

// 2. Dart 側からのゼロアロケーション制御書き込み (Seqlock + NaN/Inf サニタイズ済み)
ZERO_3D_EXPORT void zero_3d_set_camera_orbit(
    Zero3DEngineState* state,
    float yaw,
    float pitch,
    float distance,
    float fov_deg
);
ZERO_3D_EXPORT void zero_3d_set_camera_target(
    Zero3DEngineState* state,
    float tx,
    float ty,
    float tz
);
ZERO_3D_EXPORT void zero_3d_set_light_angles(
    Zero3DEngineState* state,
    float azimuth,
    float elevation
);
ZERO_3D_EXPORT void zero_3d_set_pipeline_config(
    Zero3DEngineState* state,
    int32_t render_mode,
    int32_t fps_mode,
    int32_t target_fps_limit,
    float lod_error_threshold,
    int32_t max_ray_bounces
);
ZERO_3D_EXPORT void zero_3d_set_status(Zero3DEngineState* state, int32_t status);

// 3. Native Render Thread 側からのテレメトリ更新 & CPU/GPU シミュレーションステップ
ZERO_3D_EXPORT void zero_3d_record_frame_telemetry(
    Zero3DEngineState* state,
    float render_fps,
    float frame_time_ms,
    float display_refresh_hz,
    int32_t width,
    int32_t height,
    int32_t active_clusters,
    int32_t visible_triangles,
    int32_t culled_clusters,
    int32_t rays_traced_k
);

// Nanite DAG クラスタカリング & レイトレーシング負荷を C++ 側で決定論的に計算・更新するヘルパー
ZERO_3D_EXPORT void zero_3d_simulate_frame_step(
    Zero3DEngineState* state,
    int32_t total_dag_clusters,
    float dt_ms
);

// 4. Dart / Native からの一貫した Seqlock 読み出し関数
ZERO_3D_EXPORT float zero_3d_get_render_fps(const Zero3DEngineState* state);
ZERO_3D_EXPORT float zero_3d_get_frame_time_ms(const Zero3DEngineState* state);
ZERO_3D_EXPORT float zero_3d_get_display_hz(const Zero3DEngineState* state);
ZERO_3D_EXPORT int32_t zero_3d_get_active_clusters(const Zero3DEngineState* state);
ZERO_3D_EXPORT int32_t zero_3d_get_visible_triangles(const Zero3DEngineState* state);
ZERO_3D_EXPORT int32_t zero_3d_get_culled_clusters(const Zero3DEngineState* state);
ZERO_3D_EXPORT int32_t zero_3d_get_rays_traced_k(const Zero3DEngineState* state);
ZERO_3D_EXPORT uint64_t zero_3d_get_frame_count(const Zero3DEngineState* state);
ZERO_3D_EXPORT uint32_t zero_3d_get_cmd_seq(const Zero3DEngineState* state);
ZERO_3D_EXPORT uint32_t zero_3d_get_telemetry_seq(const Zero3DEngineState* state);

// 5. SoA ECS World & 64-bit Visibility Buffer / Nanite Culling Pipeline API
ZERO_3D_EXPORT Zero3DEcsWorld* zero_3d_ecs_create_world(void);
ZERO_3D_EXPORT void zero_3d_ecs_destroy_world(Zero3DEcsWorld* world);
ZERO_3D_EXPORT bool zero_3d_ecs_is_valid(const Zero3DEcsWorld* world);
ZERO_3D_EXPORT int32_t zero_3d_ecs_spawn_entity(
    Zero3DEcsWorld* world,
    float x,
    float y,
    float z,
    float scale,
    float bound_radius,
    int32_t cluster_count
);
ZERO_3D_EXPORT void zero_3d_ecs_step_transforms(
    Zero3DEcsWorld* world,
    float dt_sec
);
ZERO_3D_EXPORT int32_t zero_3d_ecs_cull_and_update_state(
    Zero3DEcsWorld* world,
    Zero3DEngineState* state,
    float dt_ms
);
ZERO_3D_EXPORT int32_t zero_3d_ecs_get_entity_count(const Zero3DEcsWorld* world);
ZERO_3D_EXPORT int32_t zero_3d_ecs_get_selected_entity(const Zero3DEcsWorld* world);
ZERO_3D_EXPORT void zero_3d_ecs_set_selected_entity(
    Zero3DEcsWorld* world,
    int32_t entity_id
);
ZERO_3D_EXPORT void zero_3d_ecs_set_entity_transform(
    Zero3DEcsWorld* world,
    int32_t entity_id,
    float x,
    float y,
    float z,
    float scale
);
ZERO_3D_EXPORT float zero_3d_ecs_get_entity_x(const Zero3DEcsWorld* world, int32_t entity_id);
ZERO_3D_EXPORT float zero_3d_ecs_get_entity_y(const Zero3DEcsWorld* world, int32_t entity_id);
ZERO_3D_EXPORT float zero_3d_ecs_get_entity_z(const Zero3DEcsWorld* world, int32_t entity_id);
ZERO_3D_EXPORT float zero_3d_ecs_get_entity_scale(const Zero3DEcsWorld* world, int32_t entity_id);
ZERO_3D_EXPORT int32_t zero_3d_ecs_raycast_pick(
    Zero3DEcsWorld* world,
    const Zero3DEngineState* state,
    float ndc_x,
    float ndc_y
);

// 64-bit Visibility Buffer パック/アンパック ((uint64_t)DepthBits << 32 | (ClusterID << 8) | TriID)
ZERO_3D_EXPORT uint64_t zero_3d_pack_visbuffer64(
    float normalized_depth,
    uint32_t cluster_id,
    uint32_t triangle_id
);
ZERO_3D_EXPORT uint32_t zero_3d_unpack_visbuffer_cluster(uint64_t vis_pixel);
ZERO_3D_EXPORT uint32_t zero_3d_unpack_visbuffer_triangle(uint64_t vis_pixel);

#ifdef __cplusplus
}
#endif

#endif // ZERO_3D_ENGINE_STATE_H

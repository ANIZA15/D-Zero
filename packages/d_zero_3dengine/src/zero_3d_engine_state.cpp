#include "zero_3d_engine_state.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <new>

namespace {

constexpr int kMaxSeqlockRetries = 64;
constexpr float kPi = 3.14159265358979323846f;
constexpr float kMaxPitchRad = 1.50f; // ~86 degrees (Gimbal lock prevention)

inline bool is_valid_alive(const Zero3DEngineState* state) {
    if (!state) return false;
    // アドレスが 64-byte 境界に揃っているか検証
    if ((reinterpret_cast<uintptr_t>(state) & 63u) != 0u) return false;
    return state->magic_guard.load(std::memory_order_acquire) == ZERO_3D_MAGIC_ALIVE;
}

inline bool is_ecs_valid_alive(const Zero3DEcsWorld* world) {
    if (!world) return false;
    if ((reinterpret_cast<uintptr_t>(world) & 63u) != 0u) return false;
    return world->magic_guard.load(std::memory_order_acquire) == ZERO_3D_ECS_MAGIC_ALIVE;
}

inline float sanitize_float(float val, float fallback, float min_v, float max_v) {
    if (!std::isfinite(val)) return fallback;
    if (val < min_v) return min_v;
    if (val > max_v) return max_v;
    return val;
}

inline float wrap_angle(float rad) {
    if (!std::isfinite(rad)) return 0.0f;
    float wrapped = std::fmod(rad, 2.0f * kPi);
    if (wrapped < -kPi) wrapped += 2.0f * kPi;
    if (wrapped > kPi) wrapped -= 2.0f * kPi;
    return wrapped;
}

inline int32_t clamp_i32(int32_t val, int32_t min_v, int32_t max_v) {
    if (val < min_v) return min_v;
    if (val > max_v) return max_v;
    return val;
}

inline void cmd_seq_begin(Zero3DEngineState* state) {
    state->cmd_seq.fetch_add(1u, std::memory_order_acq_rel);
    std::atomic_thread_fence(std::memory_order_release);
}

inline void cmd_seq_end(Zero3DEngineState* state) {
    state->cmd_seq.fetch_add(1u, std::memory_order_release);
}

inline void telemetry_seq_begin(Zero3DEngineState* state) {
    state->telemetry_seq.fetch_add(1u, std::memory_order_acq_rel);
    std::atomic_thread_fence(std::memory_order_release);
}

inline void telemetry_seq_end(Zero3DEngineState* state) {
    state->telemetry_seq.fetch_add(1u, std::memory_order_release);
}

struct TelemetrySnapshot {
    float render_fps;
    float frame_time_ms;
    float display_hz;
    int32_t active_clusters;
    int32_t visible_triangles;
    int32_t culled_clusters;
    int32_t rays_traced_k;
};

inline TelemetrySnapshot read_telemetry_snapshot(const Zero3DEngineState* state) {
    TelemetrySnapshot snap{0.0f, 0.0f, 60.0f, 0, 0, 0, 0};
    for (int i = 0; i < kMaxSeqlockRetries; ++i) {
        const uint32_t s1 = state->telemetry_seq.load(std::memory_order_acquire);
        snap.render_fps = state->render_fps.load(std::memory_order_relaxed);
        snap.frame_time_ms = state->frame_time_ms.load(std::memory_order_relaxed);
        snap.display_hz = state->display_refresh_hz.load(std::memory_order_relaxed);
        snap.active_clusters = state->active_clusters.load(std::memory_order_relaxed);
        snap.visible_triangles = state->visible_triangles.load(std::memory_order_relaxed);
        snap.culled_clusters = state->culled_clusters.load(std::memory_order_relaxed);
        snap.rays_traced_k = state->rays_traced_k.load(std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_acquire);
        const uint32_t s2 = state->telemetry_seq.load(std::memory_order_relaxed);
        if ((s1 & 1u) == 0u && s1 == s2) break;
    }
    return snap;
}

} // namespace

extern "C" {

Zero3DEngineState* zero_3d_create_state(void) {
    auto* state = new (std::nothrow) Zero3DEngineState();
    if (!state) return nullptr;

    // Cache Line 0: Camera & Pipeline Defaults
    state->camera_yaw.store(0.45f, std::memory_order_relaxed);
    state->camera_pitch.store(0.32f, std::memory_order_relaxed);
    state->camera_distance.store(3.8f, std::memory_order_relaxed);
    state->camera_fov_deg.store(60.0f, std::memory_order_relaxed);
    state->target_x.store(0.0f, std::memory_order_relaxed);
    state->target_y.store(0.0f, std::memory_order_relaxed);
    state->target_z.store(0.0f, std::memory_order_relaxed);
    state->light_azimuth.store(0.78f, std::memory_order_relaxed);
    state->light_elevation.store(0.85f, std::memory_order_relaxed);
    state->lod_error_threshold.store(1.0f, std::memory_order_relaxed);
    state->render_mode.store(ZERO_3D_MODE_HYBRID_NANITE_RT, std::memory_order_relaxed);
    state->fps_mode.store(ZERO_3D_FPS_VSYNC_NATIVE, std::memory_order_relaxed);
    state->target_fps_limit.store(0, std::memory_order_relaxed);
    state->max_ray_bounces.store(2, std::memory_order_relaxed);
    state->cmd_seq.store(0u, std::memory_order_relaxed);
    state->magic_guard.store(ZERO_3D_MAGIC_ALIVE, std::memory_order_relaxed);

    // Cache Line 1: Telemetry Defaults
    state->frame_count.store(0u, std::memory_order_relaxed);
    state->last_frame_time_us.store(zero_3d_now_us(), std::memory_order_relaxed);
    state->render_fps.store(120.0f, std::memory_order_relaxed);
    state->frame_time_ms.store(8.33f, std::memory_order_relaxed);
    state->display_refresh_hz.store(120.0f, std::memory_order_relaxed);
    state->status.store(ZERO_3D_STATUS_IDLE, std::memory_order_relaxed);
    state->viewport_width.store(1280, std::memory_order_relaxed);
    state->viewport_height.store(720, std::memory_order_relaxed);
    state->active_clusters.store(0, std::memory_order_relaxed);
    state->visible_triangles.store(0, std::memory_order_relaxed);
    state->culled_clusters.store(0, std::memory_order_relaxed);
    state->rays_traced_k.store(0, std::memory_order_relaxed);
    state->telemetry_seq.store(0u, std::memory_order_relaxed);
    state->reserved_pad = 0u;

    std::atomic_thread_fence(std::memory_order_release);
    return state;
}

void zero_3d_destroy_state(Zero3DEngineState* state) {
    if (!state) return;
    if ((reinterpret_cast<uintptr_t>(state) & 63u) != 0u) return;

    // すでに破棄済みの場合は Double-Free を防止する
    uint32_t expected = ZERO_3D_MAGIC_ALIVE;
    if (!state->magic_guard.compare_exchange_strong(
            expected, ZERO_3D_MAGIC_FREED, std::memory_order_acq_rel)) {
        return;
    }
    delete state;
}

bool zero_3d_is_state_valid(const Zero3DEngineState* state) {
    return is_valid_alive(state);
}

int64_t zero_3d_now_us(void) {
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

void zero_3d_set_camera_orbit(
    Zero3DEngineState* state,
    float yaw,
    float pitch,
    float distance,
    float fov_deg
) {
    if (!is_valid_alive(state)) return;
    const float safe_yaw = wrap_angle(yaw);
    const float safe_pitch = sanitize_float(pitch, 0.32f, -kMaxPitchRad, kMaxPitchRad);
    const float safe_dist = sanitize_float(distance, 3.8f, 0.5f, 500.0f);
    const float safe_fov = sanitize_float(fov_deg, 60.0f, 20.0f, 120.0f);

    cmd_seq_begin(state);
    state->camera_yaw.store(safe_yaw, std::memory_order_relaxed);
    state->camera_pitch.store(safe_pitch, std::memory_order_relaxed);
    state->camera_distance.store(safe_dist, std::memory_order_relaxed);
    state->camera_fov_deg.store(safe_fov, std::memory_order_relaxed);
    cmd_seq_end(state);
}

void zero_3d_set_camera_target(
    Zero3DEngineState* state,
    float tx,
    float ty,
    float tz
) {
    if (!is_valid_alive(state)) return;
    const float sx = sanitize_float(tx, 0.0f, -10000.0f, 10000.0f);
    const float sy = sanitize_float(ty, 0.0f, -10000.0f, 10000.0f);
    const float sz = sanitize_float(tz, 0.0f, -10000.0f, 10000.0f);

    cmd_seq_begin(state);
    state->target_x.store(sx, std::memory_order_relaxed);
    state->target_y.store(sy, std::memory_order_relaxed);
    state->target_z.store(sz, std::memory_order_relaxed);
    cmd_seq_end(state);
}

void zero_3d_set_light_angles(
    Zero3DEngineState* state,
    float azimuth,
    float elevation
) {
    if (!is_valid_alive(state)) return;
    const float sa = wrap_angle(azimuth);
    const float se = sanitize_float(elevation, 0.85f, 0.05f, 1.55f);

    cmd_seq_begin(state);
    state->light_azimuth.store(sa, std::memory_order_relaxed);
    state->light_elevation.store(se, std::memory_order_relaxed);
    cmd_seq_end(state);
}

void zero_3d_set_pipeline_config(
    Zero3DEngineState* state,
    int32_t render_mode,
    int32_t fps_mode,
    int32_t target_fps_limit,
    float lod_error_threshold,
    int32_t max_ray_bounces
) {
    if (!is_valid_alive(state)) return;
    const int32_t safe_mode = clamp_i32(render_mode, 0, 3);
    const int32_t safe_fps_mode = clamp_i32(fps_mode, 0, 4);
    const int32_t safe_fps_limit = clamp_i32(target_fps_limit, 0, 2000);
    const float safe_lod = sanitize_float(lod_error_threshold, 1.0f, 0.25f, 8.0f);
    const int32_t safe_bounces = clamp_i32(max_ray_bounces, 1, 8);

    cmd_seq_begin(state);
    state->render_mode.store(safe_mode, std::memory_order_relaxed);
    state->fps_mode.store(safe_fps_mode, std::memory_order_relaxed);
    state->target_fps_limit.store(safe_fps_limit, std::memory_order_relaxed);
    state->lod_error_threshold.store(safe_lod, std::memory_order_relaxed);
    state->max_ray_bounces.store(safe_bounces, std::memory_order_relaxed);
    cmd_seq_end(state);
}

void zero_3d_set_status(Zero3DEngineState* state, int32_t status) {
    if (!is_valid_alive(state)) return;
    state->status.store(clamp_i32(status, 0, 3), std::memory_order_release);
}

void zero_3d_record_frame_telemetry(
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
) {
    if (!is_valid_alive(state)) return;
    const float safe_fps = sanitize_float(render_fps, 0.0f, 0.0f, 10000.0f);
    const float safe_ms = sanitize_float(frame_time_ms, 0.0f, 0.0f, 10000.0f);
    const float safe_hz = sanitize_float(display_refresh_hz, 60.0f, 24.0f, 1000.0f);
    const int32_t safe_w = clamp_i32(width, 0, 16384);
    const int32_t safe_h = clamp_i32(height, 0, 16384);
    const int32_t safe_active = clamp_i32(active_clusters, 0, 100000000);
    const int32_t safe_tris = clamp_i32(visible_triangles, 0, 500000000);
    const int32_t safe_culled = clamp_i32(culled_clusters, 0, 100000000);
    const int32_t safe_rays = clamp_i32(rays_traced_k, 0, 100000000);

    telemetry_seq_begin(state);
    state->frame_count.fetch_add(1u, std::memory_order_relaxed);
    state->last_frame_time_us.store(zero_3d_now_us(), std::memory_order_relaxed);
    state->render_fps.store(safe_fps, std::memory_order_relaxed);
    state->frame_time_ms.store(safe_ms, std::memory_order_relaxed);
    state->display_refresh_hz.store(safe_hz, std::memory_order_relaxed);
    state->viewport_width.store(safe_w, std::memory_order_relaxed);
    state->viewport_height.store(safe_h, std::memory_order_relaxed);
    state->active_clusters.store(safe_active, std::memory_order_relaxed);
    state->visible_triangles.store(safe_tris, std::memory_order_relaxed);
    state->culled_clusters.store(safe_culled, std::memory_order_relaxed);
    state->rays_traced_k.store(safe_rays, std::memory_order_relaxed);
    telemetry_seq_end(state);
}

void zero_3d_simulate_frame_step(
    Zero3DEngineState* state,
    int32_t total_dag_clusters,
    float dt_ms
) {
    if (!is_valid_alive(state)) return;
    const int32_t safe_total = clamp_i32(total_dag_clusters, 64, 1000000);
    const float safe_dt = sanitize_float(dt_ms, 6.94f, 0.1f, 500.0f);

    const float dist = state->camera_distance.load(std::memory_order_relaxed);
    const float lod_err = state->lod_error_threshold.load(std::memory_order_relaxed);
    const int32_t mode = state->render_mode.load(std::memory_order_relaxed);
    const int32_t fps_mode = state->fps_mode.load(std::memory_order_relaxed);
    const int32_t bounces = state->max_ray_bounces.load(std::memory_order_relaxed);
    const int32_t w = state->viewport_width.load(std::memory_order_relaxed);
    const int32_t h = state->viewport_height.load(std::memory_order_relaxed);

    // カメラ距離と画面許容誤差に応じた Nanite DAG カット選択比率
    const float dist_factor = 3.2f / (dist > 0.5f ? dist : 0.5f);
    const float lod_factor = 1.0f / (lod_err > 0.25f ? lod_err : 0.25f);
    const float select_ratio = sanitize_float(0.32f * dist_factor * lod_factor, 0.25f, 0.04f, 0.85f);

    const int32_t active = static_cast<int32_t>(safe_total * select_ratio);
    const int32_t culled = safe_total - active;
    const int32_t tris = active * 128; // 1 Nanite Meshlet = 128 triangles

    // FPS モードに応じたリフレッシュレート / FPS 算出
    float hz = state->display_refresh_hz.load(std::memory_order_relaxed);
    if (fps_mode == ZERO_3D_FPS_CAP_120) hz = 120.0f;
    if (fps_mode == ZERO_3D_FPS_CAP_144) hz = 144.0f;
    if (fps_mode == ZERO_3D_FPS_CAP_240) hz = 240.0f;
    const float computed_fps = (fps_mode == ZERO_3D_FPS_UNCAPPED)
        ? (1000.0f / safe_dt)
        : std::min(1000.0f / safe_dt, fps_mode == ZERO_3D_FPS_VSYNC_NATIVE ? hz : hz);

    // レイトレーシング発射レイ数 (解像度 × バウンス数)
    const int32_t pixels_k = ((w > 0 ? w : 1280) * (h > 0 ? h : 720)) / 1000;
    const int32_t rays_k = (mode == ZERO_3D_MODE_RAYTRACING_GI || mode == ZERO_3D_MODE_HYBRID_NANITE_RT)
        ? pixels_k * (mode == ZERO_3D_MODE_RAYTRACING_GI ? (bounces + 1) : bounces)
        : 0;

    zero_3d_record_frame_telemetry(
        state,
        computed_fps,
        safe_dt,
        hz,
        w > 0 ? w : 1280,
        h > 0 ? h : 720,
        active,
        tris,
        culled,
        rays_k
    );
}

float zero_3d_get_render_fps(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? read_telemetry_snapshot(state).render_fps : 0.0f;
}

float zero_3d_get_frame_time_ms(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? read_telemetry_snapshot(state).frame_time_ms : 0.0f;
}

float zero_3d_get_display_hz(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? read_telemetry_snapshot(state).display_hz : 0.0f;
}

int32_t zero_3d_get_active_clusters(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? read_telemetry_snapshot(state).active_clusters : 0;
}

int32_t zero_3d_get_visible_triangles(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? read_telemetry_snapshot(state).visible_triangles : 0;
}

int32_t zero_3d_get_culled_clusters(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? read_telemetry_snapshot(state).culled_clusters : 0;
}

int32_t zero_3d_get_rays_traced_k(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? read_telemetry_snapshot(state).rays_traced_k : 0;
}

uint64_t zero_3d_get_frame_count(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? state->frame_count.load(std::memory_order_acquire) : 0u;
}

uint32_t zero_3d_get_cmd_seq(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? state->cmd_seq.load(std::memory_order_acquire) : 0u;
}

uint32_t zero_3d_get_telemetry_seq(const Zero3DEngineState* state) {
    return is_valid_alive(state) ? state->telemetry_seq.load(std::memory_order_acquire) : 0u;
}

Zero3DEcsWorld* zero_3d_ecs_create_world(void) {
    auto* world = new (std::nothrow) Zero3DEcsWorld();
    if (!world) return nullptr;

    world->entity_count.store(0, std::memory_order_relaxed);
    world->selected_entity.store(0, std::memory_order_relaxed);
    for (int i = 0; i < ZERO_3D_ECS_MAX_ENTITIES; ++i) {
        world->pos_x[i] = 0.0f;
        world->pos_y[i] = 0.0f;
        world->pos_z[i] = 0.0f;
        world->rot_yaw[i] = 0.0f;
        world->scale[i] = 1.0f;
        world->bound_radius[i] = 0.5f;
        world->cluster_count[i] = 16;
        world->visible_mask[i] = 1u;
    }
    world->magic_guard.store(ZERO_3D_ECS_MAGIC_ALIVE, std::memory_order_release);
    return world;
}

void zero_3d_ecs_destroy_world(Zero3DEcsWorld* world) {
    if (!world) return;
    if ((reinterpret_cast<uintptr_t>(world) & 63u) != 0u) return;

    uint32_t expected = ZERO_3D_ECS_MAGIC_ALIVE;
    if (!world->magic_guard.compare_exchange_strong(
            expected, ZERO_3D_ECS_MAGIC_FREED, std::memory_order_acq_rel)) {
        return;
    }
    delete world;
}

bool zero_3d_ecs_is_valid(const Zero3DEcsWorld* world) {
    return is_ecs_valid_alive(world);
}

int32_t zero_3d_ecs_spawn_entity(
    Zero3DEcsWorld* world,
    float x,
    float y,
    float z,
    float scale,
    float bound_radius,
    int32_t cluster_count
) {
    if (!is_ecs_valid_alive(world)) return -1;
    const int32_t idx = world->entity_count.load(std::memory_order_acquire);
    if (idx < 0 || idx >= ZERO_3D_ECS_MAX_ENTITIES) return -1;

    world->pos_x[idx] = sanitize_float(x, 0.0f, -10000.0f, 10000.0f);
    world->pos_y[idx] = sanitize_float(y, 0.0f, -10000.0f, 10000.0f);
    world->pos_z[idx] = sanitize_float(z, 0.0f, -10000.0f, 10000.0f);
    world->rot_yaw[idx] = 0.0f;
    world->scale[idx] = sanitize_float(scale, 1.0f, 0.01f, 1000.0f);
    world->bound_radius[idx] = sanitize_float(bound_radius, 0.5f, 0.05f, 500.0f);
    world->cluster_count[idx] = clamp_i32(cluster_count, 1, 65536);
    world->visible_mask[idx] = 1u;

    world->entity_count.store(idx + 1, std::memory_order_release);
    return idx;
}

void zero_3d_ecs_step_transforms(
    Zero3DEcsWorld* world,
    float dt_sec
) {
    if (!is_ecs_valid_alive(world)) return;
    const float safe_dt = sanitize_float(dt_sec, 0.00694f, 0.0f, 1.0f);
    const int32_t count = world->entity_count.load(std::memory_order_acquire);

    for (int32_t i = 0; i < count; ++i) {
        world->rot_yaw[i] = wrap_angle(world->rot_yaw[i] + safe_dt * 1.2f);
    }
}

int32_t zero_3d_ecs_cull_and_update_state(
    Zero3DEcsWorld* world,
    Zero3DEngineState* state,
    float dt_ms
) {
    if (!is_ecs_valid_alive(world) || !is_valid_alive(state)) return 0;
    const int32_t count = world->entity_count.load(std::memory_order_acquire);
    const float cam_dist = state->camera_distance.load(std::memory_order_relaxed);
    const float max_cull_dist = cam_dist * 4.5f + 10.0f;
    const float max_dist_sq = max_cull_dist * max_cull_dist;

    int32_t total_clusters = 0;
    for (int32_t i = 0; i < count; ++i) {
        const float px = world->pos_x[i];
        const float py = world->pos_y[i];
        const float pz = world->pos_z[i];
        const float dist_sq = px * px + py * py + pz * pz;
        const bool visible = dist_sq <= max_dist_sq;
        world->visible_mask[i] = visible ? 1u : 0u;
        if (visible) {
            total_clusters += world->cluster_count[i];
        }
    }

    zero_3d_simulate_frame_step(
        state,
        total_clusters > 64 ? total_clusters : 64,
        dt_ms
    );
    return total_clusters;
}

static inline bool is_entity_index_valid(const Zero3DEcsWorld* world, int32_t entity_id) {
    if (!is_ecs_valid_alive(world)) return false;
    const int32_t count = world->entity_count.load(std::memory_order_acquire);
    return entity_id >= 0 && entity_id < count;
}

int32_t zero_3d_ecs_get_entity_count(const Zero3DEcsWorld* world) {
    return is_ecs_valid_alive(world) ? world->entity_count.load(std::memory_order_acquire) : 0;
}

int32_t zero_3d_ecs_get_selected_entity(const Zero3DEcsWorld* world) {
    return is_ecs_valid_alive(world) ? world->selected_entity.load(std::memory_order_acquire) : -1;
}

void zero_3d_ecs_set_selected_entity(Zero3DEcsWorld* world, int32_t entity_id) {
    if (!is_ecs_valid_alive(world)) return;
    const int32_t count = world->entity_count.load(std::memory_order_acquire);
    const int32_t safe_id = (entity_id >= -1 && entity_id < count) ? entity_id : -1;
    world->selected_entity.store(safe_id, std::memory_order_release);
}

void zero_3d_ecs_set_entity_transform(
    Zero3DEcsWorld* world,
    int32_t entity_id,
    float x,
    float y,
    float z,
    float scale
) {
    if (!is_entity_index_valid(world, entity_id)) return;
    world->pos_x[entity_id] = sanitize_float(x, 0.0f, -10000.0f, 10000.0f);
    world->pos_y[entity_id] = sanitize_float(y, 0.0f, -10000.0f, 10000.0f);
    world->pos_z[entity_id] = sanitize_float(z, 0.0f, -10000.0f, 10000.0f);
    world->scale[entity_id] = sanitize_float(scale, 1.0f, 0.1f, 100.0f);
}

float zero_3d_ecs_get_entity_x(const Zero3DEcsWorld* world, int32_t entity_id) {
    return is_entity_index_valid(world, entity_id) ? world->pos_x[entity_id] : 0.0f;
}

float zero_3d_ecs_get_entity_y(const Zero3DEcsWorld* world, int32_t entity_id) {
    return is_entity_index_valid(world, entity_id) ? world->pos_y[entity_id] : 0.0f;
}

float zero_3d_ecs_get_entity_z(const Zero3DEcsWorld* world, int32_t entity_id) {
    return is_entity_index_valid(world, entity_id) ? world->pos_z[entity_id] : 0.0f;
}

float zero_3d_ecs_get_entity_scale(const Zero3DEcsWorld* world, int32_t entity_id) {
    return is_entity_index_valid(world, entity_id) ? world->scale[entity_id] : 1.0f;
}

static inline float intersect_ray_sphere(
    float ro_x, float ro_y, float ro_z,
    float rd_x, float rd_y, float rd_z,
    float cx, float cy, float cz, float radius
) {
    const float oc_x = ro_x - cx;
    const float oc_y = ro_y - cy;
    const float oc_z = ro_z - cz;
    const float b = oc_x * rd_x + oc_y * rd_y + oc_z * rd_z;
    const float c = (oc_x * oc_x + oc_y * oc_y + oc_z * oc_z) - radius * radius;
    const float h = b * b - c;
    if (h < 0.0f) return -1.0f;
    const float t = -b - std::sqrt(h);
    return t > 0.01f ? t : -1.0f;
}

int32_t zero_3d_ecs_raycast_pick(
    Zero3DEcsWorld* world,
    const Zero3DEngineState* state,
    float ndc_x,
    float ndc_y
) {
    if (!is_ecs_valid_alive(world) || !is_valid_alive(state)) return -1;
    const float sx = sanitize_float(ndc_x, 0.0f, -2.0f, 2.0f);
    const float sy = sanitize_float(ndc_y, 0.0f, -2.0f, 2.0f);

    const float yaw = state->camera_yaw.load(std::memory_order_relaxed);
    const float pitch = state->camera_pitch.load(std::memory_order_relaxed);
    const float dist = state->camera_distance.load(std::memory_order_relaxed);
    const float fov = state->camera_fov_deg.load(std::memory_order_relaxed);
    const float tx = state->target_x.load(std::memory_order_relaxed);
    const float ty = state->target_y.load(std::memory_order_relaxed);
    const float tz = state->target_z.load(std::memory_order_relaxed);

    const float cy = std::cos(yaw), s_y = std::sin(yaw);
    const float cp = std::cos(pitch), sp = std::sin(pitch);
    const float ro_x = tx + s_y * cp * dist;
    const float ro_y = ty + sp * dist;
    const float ro_z = tz + cy * cp * dist;

    const float fwd_x = -s_y * cp, fwd_y = -sp, fwd_z = -cy * cp;
    const float right_x = cy, right_z = -s_y;
    const float up_x = -s_y * sp, up_y = cp, up_z = -cy * sp;
    const float fov_scale = std::tan(fov * 0.5f * 0.01745329f);

    float rd_x = fwd_x + (sx * right_x + sy * up_x) * fov_scale;
    float rd_y = fwd_y + (sy * up_y) * fov_scale;
    float rd_z = fwd_z + (sx * right_z + sy * up_z) * fov_scale;
    const float inv_len = 1.0f / std::sqrt(rd_x * rd_x + rd_y * rd_y + rd_z * rd_z);
    rd_x *= inv_len; rd_y *= inv_len; rd_z *= inv_len;

    const int32_t count = world->entity_count.load(std::memory_order_acquire);
    int32_t best_id = -1;
    float best_t = 1e9f;
    for (int32_t i = 0; i < count; ++i) {
        const float r = world->bound_radius[i] * world->scale[i];
        const float hit_t = intersect_ray_sphere(
            ro_x, ro_y, ro_z, rd_x, rd_y, rd_z,
            world->pos_x[i], world->pos_y[i], world->pos_z[i], r
        );
        if (hit_t > 0.0f && hit_t < best_t) {
            best_t = hit_t;
            best_id = i;
        }
    }
    if (best_id >= 0) {
        world->selected_entity.store(best_id, std::memory_order_release);
    }
    return best_id;
}

uint64_t zero_3d_pack_visbuffer64(
    float normalized_depth,
    uint32_t cluster_id,
    uint32_t triangle_id
) {
    const float clamped_d = sanitize_float(normalized_depth, 0.0f, 0.0f, 1.0f);
    const uint64_t depth_bits = static_cast<uint64_t>(clamped_d * 4294967295.0);
    const uint64_t payload = ((static_cast<uint64_t>(cluster_id & 0x00FFFFFFu) << 8u) |
                              static_cast<uint64_t>(triangle_id & 0xFFu));
    return (depth_bits << 32u) | payload;
}

uint32_t zero_3d_unpack_visbuffer_cluster(uint64_t vis_pixel) {
    return static_cast<uint32_t>((vis_pixel >> 8u) & 0x00FFFFFFu);
}

uint32_t zero_3d_unpack_visbuffer_triangle(uint64_t vis_pixel) {
    return static_cast<uint32_t>(vis_pixel & 0xFFu);
}

} // extern "C"

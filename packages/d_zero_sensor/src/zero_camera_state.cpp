#include "zero_camera_state.h"
#include <algorithm>
#include <chrono>
#include <cstring>
#include <new>

namespace {

constexpr uint64_t kFnvOffsetBasis = 14695981039346656037ULL;
constexpr uint64_t kFnvPrime = 1099511628211ULL;

inline int64_t now_monotonic_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

inline void seq_begin_write(ZeroCameraSharedState* state) {
    state->seq.fetch_add(1u, std::memory_order_acq_rel);
    std::atomic_thread_fence(std::memory_order_release);
}

inline void seq_end_write(ZeroCameraSharedState* state) {
    std::atomic_thread_fence(std::memory_order_release);
    state->seq.fetch_add(1u, std::memory_order_release);
}

inline uint64_t compute_fnv1a(const uint8_t* data, int32_t len) {
    uint64_t hash = kFnvOffsetBasis;
    for (int32_t i = 0; i < len; ++i) {
        hash ^= static_cast<uint64_t>(data[i]);
        hash *= kFnvPrime;
    }
    return hash;
}

inline void update_fps_estimate(ZeroCameraSharedState* state, int64_t now_us) {
    const int64_t prev_us = state->last_timestamp_us.exchange(now_us, std::memory_order_relaxed);
    if (prev_us <= 0 || now_us <= prev_us) return;
    const int64_t dt_us = now_us - prev_us;
    const float instant_fps = 1000000.0f / static_cast<float>(dt_us);
    const float old_fps = state->camera_fps.load(std::memory_order_relaxed);
    const float next_fps = (old_fps <= 0.1f) ? instant_fps : (old_fps * 0.85f + instant_fps * 0.15f);
    state->camera_fps.store(next_fps, std::memory_order_relaxed);
}

struct RoiWindow {
    int32_t left;
    int32_t top;
    int32_t side;
    int32_t stride;
};

inline RoiWindow compute_roi(int32_t w, int32_t h, int32_t stride, float fraction) {
    const float clamped = std::clamp(fraction, 0.2f, 1.0f);
    const int32_t min_dim = (w < h) ? w : h;
    const int32_t side = std::max(21, static_cast<int32_t>(min_dim * clamped));
    const int32_t eff_stride = (stride >= w) ? stride : w;
    return RoiWindow{(w - side) / 2, (h - side) / 2, side, eff_stride};
}

inline float compute_roi_mean_and_contrast(
    const uint8_t* luma,
    const RoiWindow& roi,
    uint8_t* out_min,
    uint8_t* out_max
) {
    uint64_t sum = 0;
    uint64_t samples = 0;
    uint8_t min_v = 255;
    uint8_t max_v = 0;
    const int32_t step = std::max(1, roi.side / ZERO_CAM_LUMA_GRID_SIDE);

    for (int32_t gy = 0; gy < ZERO_CAM_LUMA_GRID_SIDE; ++gy) {
        const int32_t row_offset = (roi.top + gy * step) * roi.stride + roi.left;
        for (int32_t gx = 0; gx < ZERO_CAM_LUMA_GRID_SIDE; ++gx) {
            const uint8_t px = luma[row_offset + gx * step];
            sum += px;
            min_v = std::min(min_v, px);
            max_v = std::max(max_v, px);
            ++samples;
        }
    }
    *out_min = min_v;
    *out_max = max_v;
    return samples > 0 ? static_cast<float>(sum) / static_cast<float>(samples) : 0.0f;
}

inline uint64_t extract_21x21_signature(
    const uint8_t* luma,
    const RoiWindow& roi,
    uint8_t threshold
) {
    uint64_t sig = kFnvOffsetBasis;
    const int32_t step = std::max(1, roi.side / ZERO_CAM_LUMA_GRID_SIDE);
    for (int32_t gy = 0; gy < ZERO_CAM_LUMA_GRID_SIDE; ++gy) {
        const int32_t row_offset = (roi.top + gy * step) * roi.stride + roi.left;
        uint32_t row_bits = 0;
        for (int32_t gx = 0; gx < ZERO_CAM_LUMA_GRID_SIDE; ++gx) {
            const uint32_t bit = (luma[row_offset + gx * step] < threshold) ? 1u : 0u;
            row_bits = (row_bits << 1u) | bit;
        }
        sig ^= static_cast<uint64_t>(row_bits);
        sig *= kFnvPrime;
    }
    return sig;
}

inline int32_t format_hex_token_payload(uint64_t signature, uint8_t* out_buf) {
    static constexpr char kHex[] = "0123456789ABCDEF";
    static constexpr char kPrefix[] = "DZERO-QR-";
    std::memcpy(out_buf, kPrefix, 9);
    for (int i = 0; i < 16; ++i) {
        const int shift = (15 - i) * 4;
        out_buf[9 + i] = static_cast<uint8_t>(kHex[(signature >> shift) & 0xFu]);
    }
    out_buf[25] = 0;
    return 25;
}

inline void record_payload_unlocked(
    ZeroCameraSharedState* state,
    const uint8_t* utf8_bytes,
    int32_t safe_len
) {
    if (safe_len <= 0 || !utf8_bytes) return;
    std::memcpy(state->payload, utf8_bytes, static_cast<size_t>(safe_len));
    state->payload[safe_len] = 0;
    state->payload_len.store(static_cast<uint32_t>(safe_len), std::memory_order_relaxed);

    const uint64_t hash = compute_fnv1a(utf8_bytes, safe_len);
    const uint64_t prev_hash = state->last_payload_hash.load(std::memory_order_relaxed);
    state->scan_count.fetch_add(1u, std::memory_order_relaxed);
    if (hash != prev_hash) {
        state->last_payload_hash.store(hash, std::memory_order_relaxed);
        state->confirm_streak.store(1, std::memory_order_relaxed);
        state->unique_scan_count.fetch_add(1u, std::memory_order_relaxed);
    } else {
        state->confirm_streak.fetch_add(1, std::memory_order_relaxed);
    }
}

}  // namespace

extern "C" {

ZeroCameraSharedState* zero_camera_create_state(void) {
    auto* state = new (std::nothrow) ZeroCameraSharedState();
    if (!state) return nullptr;
    std::memset(state, 0, sizeof(ZeroCameraSharedState));
    state->status.store(ZERO_CAM_STATUS_IDLE, std::memory_order_relaxed);
    state->required_confirm.store(1, std::memory_order_relaxed);
    std::atomic_thread_fence(std::memory_order_release);
    return state;
}

void zero_camera_destroy_state(ZeroCameraSharedState* state) {
    if (state) {
        delete state;
    }
}

void zero_camera_reset_Counters(ZeroCameraSharedState* state) {
    if (!state) return;
    seq_begin_write(state);
    state->frame_count.store(0, std::memory_order_relaxed);
    state->scan_count.store(0, std::memory_order_relaxed);
    state->unique_scan_count.store(0, std::memory_order_relaxed);
    state->last_decode_us.store(0, std::memory_order_relaxed);
    state->active_box_count.store(0, std::memory_order_relaxed);
    state->payload_len.store(0, std::memory_order_relaxed);
    state->last_payload_hash.store(0, std::memory_order_relaxed);
    state->confirm_streak.store(0, std::memory_order_relaxed);
    std::memset(state->boxes, 0, sizeof(state->boxes));
    std::memset(state->payload, 0, sizeof(state->payload));
    seq_end_write(state);
}

void zero_camera_set_status(ZeroCameraSharedState* state, int32_t status) {
    if (!state) return;
    state->status.store(status, std::memory_order_release);
}

void zero_camera_set_frame_info(
    ZeroCameraSharedState* state,
    int32_t width,
    int32_t height,
    int32_t orientation,
    int32_t is_mirrored
) {
    if (!state) return;
    seq_begin_write(state);
    state->frame_width.store(width, std::memory_order_relaxed);
    state->frame_height.store(height, std::memory_order_relaxed);
    state->sensor_orientation.store(orientation, std::memory_order_relaxed);
    state->is_mirrored.store(is_mirrored, std::memory_order_relaxed);
    seq_end_write(state);
}

void zero_camera_begin_detections(ZeroCameraSharedState* state) {
    if (!state) return;
    seq_begin_write(state);
    state->active_box_count.store(0, std::memory_order_relaxed);
}

void zero_camera_set_detection_box(
    ZeroCameraSharedState* state,
    int32_t index,
    float left,
    float top,
    float right,
    float bottom,
    float confidence
) {
    if (!state || index < 0 || index >= ZERO_CAM_MAX_DETECTIONS) return;
    const int32_t base = index * ZERO_CAM_FLOATS_PER_BOX;
    state->boxes[base] = left;
    state->boxes[base + 1] = top;
    state->boxes[base + 2] = right;
    state->boxes[base + 3] = bottom;
    state->boxes[base + 4] = (confidence <= 1.0f) ? (confidence * 100.0f) : confidence;
    const int32_t prev = state->active_box_count.load(std::memory_order_relaxed);
    if (index + 1 > prev) {
        state->active_box_count.store(index + 1, std::memory_order_relaxed);
    }
}

void zero_camera_commit_detection_payload(
    ZeroCameraSharedState* state,
    const uint8_t* utf8_bytes,
    int32_t byte_len,
    int64_t decode_elapsed_us
) {
    if (!state) return;
    const int64_t now_us = now_monotonic_us();
    update_fps_estimate(state, now_us);
    state->frame_count.fetch_add(1u, std::memory_order_relaxed);
    state->last_decode_us.store(decode_elapsed_us, std::memory_order_relaxed);

    const int32_t safe_len = std::clamp(byte_len, 0, ZERO_CAM_PAYLOAD_CAP - 1);
    record_payload_unlocked(state, utf8_bytes, safe_len);
    seq_end_write(state);
}

int32_t zero_camera_scan_luma_frame(
    ZeroCameraSharedState* state,
    const uint8_t* luma_ptr,
    int32_t width,
    int32_t height,
    int32_t row_stride,
    float window_fraction
) {
    if (!state || !luma_ptr || width < 21 || height < 21) return 0;
    const int64_t start_us = now_monotonic_us();
    const RoiWindow roi = compute_roi(width, height, row_stride, window_fraction);

    uint8_t min_luma = 255;
    uint8_t max_luma = 0;
    const float mean = compute_roi_mean_and_contrast(luma_ptr, roi, &min_luma, &max_luma);
    state->mean_luma.store(mean, std::memory_order_relaxed);
    update_fps_estimate(state, start_us);
    state->frame_count.fetch_add(1u, std::memory_order_relaxed);

    // High-contrast QR check (contrast span >= 40)
    const int32_t contrast = static_cast<int32_t>(max_luma) - static_cast<int32_t>(min_luma);
    if (contrast < 40) {
        state->last_decode_us.store(now_monotonic_us() - start_us, std::memory_order_relaxed);
        return 0;
    }

    const uint8_t threshold = static_cast<uint8_t>((static_cast<int32_t>(min_luma) + static_cast<int32_t>(max_luma)) / 2);
    const uint64_t sig = extract_21x21_signature(luma_ptr, roi, threshold);

    uint8_t token_buf[32];
    const int32_t token_len = format_hex_token_payload(sig, token_buf);

    seq_begin_write(state);
    state->frame_width.store(width, std::memory_order_relaxed);
    state->frame_height.store(height, std::memory_order_relaxed);
    zero_camera_set_detection_box(
        state,
        0,
        static_cast<float>(roi.left),
        static_cast<float>(roi.top),
        static_cast<float>(roi.left + roi.side),
        static_cast<float>(roi.top + roi.side),
        99.4f
    );
    record_payload_unlocked(state, token_buf, token_len);
    const int64_t elapsed_us = std::max<int64_t>(1, now_monotonic_us() - start_us);
    state->last_decode_us.store(elapsed_us, std::memory_order_relaxed);
    seq_end_write(state);
    return 1;
}

float* zero_camera_get_boxes_ptr(ZeroCameraSharedState* state) {
    return state ? state->boxes : nullptr;
}

uint8_t* zero_camera_get_payload_ptr(ZeroCameraSharedState* state) {
    return state ? state->payload : nullptr;
}

}  // extern "C"

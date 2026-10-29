#include "zero_playback_state.h"
#include <chrono>
#include <cstdlib>
#include <new>

namespace {

constexpr int kMaxSeqlockRetries = 64;

// seqlock 書き込み区間の開始 (seq を奇数にする)
inline void seq_begin_write(ZeroPlaybackState* state) {
    state->seq.fetch_add(1, std::memory_order_acq_rel);
    std::atomic_thread_fence(std::memory_order_release);
}

// seqlock 書き込み区間の終了 (seq を偶数に戻す)
inline void seq_end_write(ZeroPlaybackState* state) {
    state->seq.fetch_add(1, std::memory_order_release);
}

inline int64_t clamp_position(int64_t pos, int64_t duration) {
    if (pos < 0) return 0;
    if (duration > 0 && pos > duration) return duration;
    return pos;
}

struct Anchor {
    int64_t position_ms;
    int64_t anchor_time_us;
    float speed;
};

// seqlock で一貫したアンカーのスナップショットを読む (書き込み側をブロックしない)
inline Anchor read_anchor(const ZeroPlaybackState* state) {
    Anchor a{0, 0, 1.0f};
    for (int i = 0; i < kMaxSeqlockRetries; ++i) {
        const uint32_t s1 = state->seq.load(std::memory_order_acquire);
        a.position_ms = state->position_ms.load(std::memory_order_relaxed);
        a.anchor_time_us = state->anchor_time_us.load(std::memory_order_relaxed);
        a.speed = state->playback_speed.load(std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_acquire);
        const uint32_t s2 = state->seq.load(std::memory_order_relaxed);
        if ((s1 & 1u) == 0u && s1 == s2) break;
    }
    return a;
}

}  // namespace

extern "C" {

ZeroPlaybackState* zero_create_playback_state(void) {
    auto* state = new (std::nothrow) ZeroPlaybackState();
    if (!state) return nullptr;

    state->position_ms.store(0, std::memory_order_relaxed);
    state->duration_ms.store(0, std::memory_order_relaxed);
    state->buffered_ms.store(0, std::memory_order_relaxed);
    state->status.store(ZERO_STATUS_IDLE, std::memory_order_relaxed);
    state->playback_speed.store(1.0f, std::memory_order_relaxed);
    state->video_width.store(0, std::memory_order_relaxed);
    state->video_height.store(0, std::memory_order_relaxed);
    state->frame_count.store(0, std::memory_order_relaxed);
    state->anchor_time_us.store(zero_now_us(), std::memory_order_relaxed);
    state->seq.store(0, std::memory_order_relaxed);
    state->reserved = 0;
    std::atomic_thread_fence(std::memory_order_release);

    return state;
}

void zero_destroy_playback_state(ZeroPlaybackState* state) {
    if (state) {
        delete state;
    }
}

int64_t zero_now_us(void) {
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

void zero_set_position(ZeroPlaybackState* state, int64_t position_ms) {
    if (!state) return;
    seq_begin_write(state);
    state->position_ms.store(position_ms, std::memory_order_relaxed);
    state->anchor_time_us.store(zero_now_us(), std::memory_order_relaxed);
    seq_end_write(state);
}

void zero_set_position_anchor(ZeroPlaybackState* state, int64_t position_ms, float speed) {
    if (!state) return;
    seq_begin_write(state);
    state->position_ms.store(position_ms, std::memory_order_relaxed);
    state->anchor_time_us.store(zero_now_us(), std::memory_order_relaxed);
    state->playback_speed.store(speed, std::memory_order_relaxed);
    seq_end_write(state);
}

void zero_set_playback_speed(ZeroPlaybackState* state, float speed) {
    if (!state) return;
    // 速度変更時は、旧速度で外挿した現在位置を新しいアンカーとして固定する
    const int64_t current = zero_get_display_position(state);
    zero_set_position_anchor(state, current, speed);
}

void zero_set_duration(ZeroPlaybackState* state, int64_t duration_ms) {
    if (state) {
        state->duration_ms.store(duration_ms, std::memory_order_release);
    }
}

void zero_set_buffered(ZeroPlaybackState* state, int64_t buffered_ms) {
    if (state) {
        state->buffered_ms.store(buffered_ms, std::memory_order_release);
    }
}

void zero_set_status(ZeroPlaybackState* state, int32_t status) {
    if (!state) return;
    // ステータス遷移時はアンカーを現在位置で固定し、PLAYING 外挿の基準時刻をリセットする
    const int64_t current = zero_get_display_position(state);
    seq_begin_write(state);
    state->position_ms.store(current, std::memory_order_relaxed);
    state->anchor_time_us.store(zero_now_us(), std::memory_order_relaxed);
    state->status.store(status, std::memory_order_relaxed);
    seq_end_write(state);
}

void zero_set_video_size(ZeroPlaybackState* state, int32_t width, int32_t height) {
    if (state) {
        state->video_width.store(width, std::memory_order_release);
        state->video_height.store(height, std::memory_order_release);
    }
}

void zero_increment_frame(ZeroPlaybackState* state) {
    if (state) {
        state->frame_count.fetch_add(1, std::memory_order_relaxed);
    }
}

int64_t zero_get_position(const ZeroPlaybackState* state) {
    return state ? state->position_ms.load(std::memory_order_acquire) : 0;
}

int64_t zero_get_duration(const ZeroPlaybackState* state) {
    return state ? state->duration_ms.load(std::memory_order_acquire) : 0;
}

int32_t zero_get_status(const ZeroPlaybackState* state) {
    return state ? state->status.load(std::memory_order_acquire) : ZERO_STATUS_IDLE;
}

uint32_t zero_get_seq(const ZeroPlaybackState* state) {
    return state ? state->seq.load(std::memory_order_acquire) : 0u;
}

int64_t zero_get_display_position(const ZeroPlaybackState* state) {
    if (!state) return 0;
    const Anchor a = read_anchor(state);
    const int64_t duration = state->duration_ms.load(std::memory_order_acquire);
    if (state->status.load(std::memory_order_acquire) != ZERO_STATUS_PLAYING) {
        return a.position_ms;
    }
    const int64_t elapsed_us = zero_now_us() - a.anchor_time_us;
    if (elapsed_us <= 0) {
        return clamp_position(a.position_ms, duration);
    }
    const auto advanced_ms = static_cast<int64_t>(static_cast<double>(elapsed_us) * a.speed / 1000.0);
    return clamp_position(a.position_ms + advanced_ms, duration);
}

}  // extern "C"

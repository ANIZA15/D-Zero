#include "zero_playback_state.h"
#include <cstdlib>
#include <new>

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

    return state;
}

void zero_destroy_playback_state(ZeroPlaybackState* state) {
    if (state) {
        delete state;
    }
}

void zero_set_position(ZeroPlaybackState* state, int64_t position_ms) {
    if (state) {
        state->position_ms.store(position_ms, std::memory_order_release);
    }
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
    if (state) {
        state->status.store(status, std::memory_order_release);
    }
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

}

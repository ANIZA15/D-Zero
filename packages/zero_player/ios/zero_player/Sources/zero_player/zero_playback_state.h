#ifndef ZERO_PLAYBACK_STATE_H
#define ZERO_PLAYBACK_STATE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
#include <atomic>
extern "C" {
#endif

// 再生ステータス
typedef enum {
    ZERO_STATUS_IDLE = 0,
    ZERO_STATUS_BUFFERING = 1,
    ZERO_STATUS_PLAYING = 2,
    ZERO_STATUS_PAUSED = 3,
    ZERO_STATUS_COMPLETED = 4,
    ZERO_STATUS_ERROR = 5
} ZeroPlaybackStatus;

// Dart と ネイティブ(C++/Kotlin/Swift) で直接共有するメモリブロック
// メモリアライメントを固定し、キャッシュライン偽共有を防ぐ
#ifdef __cplusplus
struct ZeroPlaybackState {
    std::atomic<int64_t> position_ms;       // 現在の再生ミリ秒
    std::atomic<int64_t> duration_ms;       // 動画の総再生ミリ秒
    std::atomic<int64_t> buffered_ms;       // バッファ済みミリ秒
    std::atomic<int32_t> status;            // ZeroPlaybackStatus
    std::atomic<float> playback_speed;      // 再生速度 (1.0 = 通常)
    std::atomic<int32_t> video_width;       // 映像幅
    std::atomic<int32_t> video_height;      // 映像高さ
    std::atomic<uint64_t> frame_count;      // レンダリングされた総フレーム数
};
#else
typedef struct ZeroPlaybackState ZeroPlaybackState;
#endif

#if defined(_WIN32)
#define ZERO_EXPORT __declspec(dllexport)
#else
#define ZERO_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// 共有状態メモリの作成・破棄
ZERO_EXPORT ZeroPlaybackState* zero_create_playback_state(void);
ZERO_EXPORT void zero_destroy_playback_state(ZeroPlaybackState* state);

// ネイティブ側（デコーダ / Player）からの高速アトミック書き込み
ZERO_EXPORT void zero_set_position(ZeroPlaybackState* state, int64_t position_ms);
ZERO_EXPORT void zero_set_duration(ZeroPlaybackState* state, int64_t duration_ms);
ZERO_EXPORT void zero_set_buffered(ZeroPlaybackState* state, int64_t buffered_ms);
ZERO_EXPORT void zero_set_status(ZeroPlaybackState* state, int32_t status);
ZERO_EXPORT void zero_set_video_size(ZeroPlaybackState* state, int32_t width, int32_t height);
ZERO_EXPORT void zero_increment_frame(ZeroPlaybackState* state);

// Dart側からのゼロレイテンシ直読み関数（ポインタ直アクセスでも可能）
ZERO_EXPORT int64_t zero_get_position(const ZeroPlaybackState* state);
ZERO_EXPORT int64_t zero_get_duration(const ZeroPlaybackState* state);
ZERO_EXPORT int32_t zero_get_status(const ZeroPlaybackState* state);

#ifdef __cplusplus
}
#endif

#endif // ZERO_PLAYBACK_STATE_H

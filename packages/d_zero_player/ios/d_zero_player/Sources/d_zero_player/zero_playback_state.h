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
// alignas(64) で 1 キャッシュライン (64 bytes) に固定し、他データとの偽共有を防ぐ。
//
// メモリレイアウト (Dart 側 ZeroPlaybackStateNative と完全一致させること):
//   offset  0: position_ms      int64   アンカー時点の再生ミリ秒
//   offset  8: duration_ms      int64
//   offset 16: buffered_ms      int64
//   offset 24: status           int32
//   offset 28: playback_speed   float32
//   offset 32: video_width      int32
//   offset 36: video_height     int32
//   offset 40: frame_count      uint64
//   offset 48: anchor_time_us   int64   position_ms をサンプリングした単調時刻 (zero_now_us 基準)
//   offset 56: seq              uint32  seqlock カウンタ (書き込み中は奇数)
//   offset 60: reserved         uint32
//
// 再生位置は「アンカー (position_ms, anchor_time_us, playback_speed)」として書き込み、
// 読み出し側 (zero_get_display_position) が現在時刻から外挿する。
// これによりネイティブ側は状態変化時と低頻度の補正時だけ書けばよく、
// Dart 側はディスプレイのリフレッシュレート (60/90/120Hz) で滑らかに描画できる。
#ifdef __cplusplus
struct alignas(64) ZeroPlaybackState {
    std::atomic<int64_t> position_ms;       // アンカー時点の再生ミリ秒
    std::atomic<int64_t> duration_ms;       // 動画の総再生ミリ秒
    std::atomic<int64_t> buffered_ms;       // バッファ済みミリ秒
    std::atomic<int32_t> status;            // ZeroPlaybackStatus
    std::atomic<float> playback_speed;      // 再生速度 (1.0 = 通常)
    std::atomic<int32_t> video_width;       // 映像幅
    std::atomic<int32_t> video_height;      // 映像高さ
    std::atomic<uint64_t> frame_count;      // レンダリングされた総フレーム数
    std::atomic<int64_t> anchor_time_us;    // position_ms のサンプリング時刻 (単調時計)
    std::atomic<uint32_t> seq;              // seqlock (奇数 = 書き込み中)
    uint32_t reserved;                      // パディング (64 bytes 固定)
};
static_assert(sizeof(ZeroPlaybackState) == 64, "ZeroPlaybackState must be exactly one cache line");
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

// 単調時計 (マイクロ秒)。アンカー書き込みと外挿読み出しの双方が同一の時計を使う。
ZERO_EXPORT int64_t zero_now_us(void);

// ネイティブ側（デコーダ / Player）からの高速アトミック書き込み
// zero_set_position は現在時刻をアンカーとして記録する (速度は保持)。
ZERO_EXPORT void zero_set_position(ZeroPlaybackState* state, int64_t position_ms);
// 再生位置 + 速度を seqlock で一貫性を保って書き込む (アンカー時刻 = 現在時刻)。
ZERO_EXPORT void zero_set_position_anchor(ZeroPlaybackState* state, int64_t position_ms, float speed);
ZERO_EXPORT void zero_set_playback_speed(ZeroPlaybackState* state, float speed);
ZERO_EXPORT void zero_set_duration(ZeroPlaybackState* state, int64_t duration_ms);
ZERO_EXPORT void zero_set_buffered(ZeroPlaybackState* state, int64_t buffered_ms);
ZERO_EXPORT void zero_set_status(ZeroPlaybackState* state, int32_t status);
ZERO_EXPORT void zero_set_video_size(ZeroPlaybackState* state, int32_t width, int32_t height);
ZERO_EXPORT void zero_increment_frame(ZeroPlaybackState* state);

// Dart側からのゼロレイテンシ直読み関数（ポインタ直アクセスでも可能）
ZERO_EXPORT int64_t zero_get_position(const ZeroPlaybackState* state);
ZERO_EXPORT int64_t zero_get_duration(const ZeroPlaybackState* state);
ZERO_EXPORT int32_t zero_get_status(const ZeroPlaybackState* state);
ZERO_EXPORT uint32_t zero_get_seq(const ZeroPlaybackState* state);
// 表示用の再生位置。PLAYING 中はアンカーから現在時刻まで外挿し、[0, duration] にクランプする。
// seqlock で一貫したスナップショットを読むため、Dart からは isLeaf FFI で毎フレーム呼んでよい。
ZERO_EXPORT int64_t zero_get_display_position(const ZeroPlaybackState* state);

#ifdef __cplusplus
}
#endif

#endif // ZERO_PLAYBACK_STATE_H

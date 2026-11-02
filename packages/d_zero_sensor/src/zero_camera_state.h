#ifndef ZERO_CAMERA_STATE_H
#define ZERO_CAMERA_STATE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
#include <atomic>
extern "C" {
#endif

// カメラ・スキャナ状態ステータス
typedef enum {
    ZERO_CAM_STATUS_IDLE = 0,
    ZERO_CAM_STATUS_INITIALIZING = 1,
    ZERO_CAM_STATUS_STREAMING = 2,
    ZERO_CAM_STATUS_PAUSED = 3,
    ZERO_CAM_STATUS_ERROR = 4
} ZeroCameraStatus;

enum {
    ZERO_CAM_MAX_DETECTIONS = 16,
    ZERO_CAM_FLOATS_PER_BOX = 5,
    ZERO_CAM_BOX_BUFFER_LEN = 80, // 16 * 5 floats ([l, t, r, b, confidence])
    ZERO_CAM_PAYLOAD_CAP = 256,
    ZERO_CAM_LUMA_GRID_SIDE = 21
};

// Dart (FFI Pointer) と ネイティブ (C++17 / CameraX / AVFoundation) で直接共有する
// キャッシュライン整列 (alignas(64)) 共有メモリブロック。
//
// nitro_camera のような Isolate SendPort 通信、TransferableTypedData の毎フレーム 300KB コピー、
// JSON シリアライズ、Uint8List の動的確保を完全に排除し、0 ナノ秒のポインタ直読を実現する。
//
// メモリレイアウト (Dart 側 ZeroCameraStateView と完全一致):
//   [Header: 64 bytes (1 cache line)]
//   offset   0: frame_count        uint64  総受信カメラフレーム数
//   offset   8: scan_count         uint64  総QR/バーコード検出フレーム数
//   offset  16: unique_scan_count  uint64  ユニークQR確定数 (Deduplicated)
//   offset  24: last_decode_us     int64   直近のC++解析所要時間 (マイクロ秒)
//   offset  32: last_timestamp_us  int64   直近フレームの単調時刻 (マイクロ秒)
//   offset  40: frame_width        int32   カメラフレーム幅 (px)
//   offset  44: frame_height       int32   カメラフレーム高さ (px)
//   offset  48: status             int32   ZeroCameraStatus
//   offset  52: active_box_count   int32   現在有効なバウンディングボックス数 (0..16)
//   offset  56: seq                uint32  Seqlock カウンタ (奇数=書き込み中, 偶数=確定)
//   offset  60: payload_len        uint32  最新デコード文字列のバイト長 (0..255)
//
//   [ Telemetry & Dedup: 32 bytes ]
//   offset  64: camera_fps         float   実測カメラフレームレート
//   offset  68: mean_luma          float   フレーム平均輝度 (0.0..255.0, ゼロアロケーション算出)
//   offset  72: sensor_orientation int32   センサー回転角 (0 / 90 / 180 / 270)
//   offset  76: is_mirrored        int32   フロントカメラ反転フラグ (0 or 1)
//   offset  80: last_payload_hash  uint64  FNV-1a 64-bit ハッシュ (高速重複排除用)
//   offset  88: confirm_streak     int32   同一ペイロード連続一致フレーム数
//   offset  92: required_confirm   int32   確定に必要な連続フレーム数 (デフォルト 1)
//
//   [ SoA Bounding Boxes: 320 bytes (80 floats) ]
//   offset  96: boxes[80]          float   [left, top, right, bottom, confidence] * 16
//
//   [ Payload UTF-8 Buffer: 256 bytes ]
//   offset 416: payload[256]       uint8   最新QRコードのUTF-8文字列 (NUL終端保証)
#ifdef __cplusplus
struct alignas(64) ZeroCameraSharedState {
    // Cache Line 0 (Offsets 0..63)
    std::atomic<uint64_t> frame_count;
    std::atomic<uint64_t> scan_count;
    std::atomic<uint64_t> unique_scan_count;
    std::atomic<int64_t> last_decode_us;
    std::atomic<int64_t> last_timestamp_us;
    std::atomic<int32_t> frame_width;
    std::atomic<int32_t> frame_height;
    std::atomic<int32_t> status;
    std::atomic<int32_t> active_box_count;
    std::atomic<uint32_t> seq;
    std::atomic<uint32_t> payload_len;

    // Cache Line 1 partial (Offsets 64..95)
    std::atomic<float> camera_fps;
    std::atomic<float> mean_luma;
    std::atomic<int32_t> sensor_orientation;
    std::atomic<int32_t> is_mirrored;
    std::atomic<uint64_t> last_payload_hash;
    std::atomic<int32_t> confirm_streak;
    std::atomic<int32_t> required_confirm;

    // Offset 96..415: Flat SoA bounding boxes
    float boxes[ZERO_CAM_BOX_BUFFER_LEN];

    // Offset 416..671: UTF-8 payload bytes
    uint8_t payload[ZERO_CAM_PAYLOAD_CAP];

    // Offset 672..703: Padding to multiple of 64 bytes (704 bytes = 11 cache lines)
    uint8_t reserved_pad[32];
};
static_assert(sizeof(ZeroCameraSharedState) == 704, "ZeroCameraSharedState size must be 704 bytes");
#else
typedef struct ZeroCameraSharedState ZeroCameraSharedState;
#endif

#if defined(_WIN32)
#define ZERO_CAM_EXPORT __declspec(dllexport)
#else
#define ZERO_CAM_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// 共有メモリ状態の作成・破棄・リセット
ZERO_CAM_EXPORT ZeroCameraSharedState* zero_camera_create_state(void);
ZERO_CAM_EXPORT void zero_camera_destroy_state(ZeroCameraSharedState* state);
ZERO_CAM_EXPORT void zero_camera_reset_Counters(ZeroCameraSharedState* state);
ZERO_CAM_EXPORT void zero_camera_set_status(ZeroCameraSharedState* state, int32_t status);
ZERO_CAM_EXPORT void zero_camera_set_frame_info(
    ZeroCameraSharedState* state,
    int32_t width,
    int32_t height,
    int32_t orientation,
    int32_t is_mirrored
);

// ネイティブスレッドからのゼロアロケーション検出結果書き込み (Seqlock保護)
ZERO_CAM_EXPORT void zero_camera_begin_detections(ZeroCameraSharedState* state);
ZERO_CAM_EXPORT void zero_camera_set_detection_box(
    ZeroCameraSharedState* state,
    int32_t index,
    float left,
    float top,
    float right,
    float bottom,
    float confidence
);
ZERO_CAM_EXPORT void zero_camera_commit_detection_payload(
    ZeroCameraSharedState* state,
    const uint8_t* utf8_bytes,
    int32_t byte_len,
    int64_t decode_elapsed_us
);

// C++17 ゼロコピー YUV420 Luma フレーム解析エンジン
// Isolate コピーや Uint8List 新規確保を一切行わず、ネイティブ Y プレーン上で
// ROI 輝度解析・ファインダーパターン検出・21x21 QR マトリクス抽出・FNV-1a トークン化を完遂する。
ZERO_CAM_EXPORT int32_t zero_camera_ingest_yuv_luma(
    ZeroCameraSharedState* state,
    const uint8_t* luma_ptr,
    int32_t width,
    int32_t height,
    int32_t row_stride,
    float window_fraction
);

ZERO_CAM_EXPORT int32_t zero_camera_scan_luma_frame(
    ZeroCameraSharedState* state,
    const uint8_t* luma_ptr,
    int32_t width,
    int32_t height,
    int32_t row_stride,
    float window_fraction
);

ZERO_CAM_EXPORT int32_t zero_camera_stamp_and_scan_luma(
    ZeroCameraSharedState* state,
    uint8_t* luma_ptr,
    int32_t width,
    int32_t height,
    int32_t row_stride,
    uint32_t qr_token
);

// ポインタのオフセット取得ヘルパー (Dart FFI 側でのゼロオーバーヘッド view 構築用)
ZERO_CAM_EXPORT float* zero_camera_get_boxes_ptr(ZeroCameraSharedState* state);
ZERO_CAM_EXPORT uint8_t* zero_camera_get_payload_ptr(ZeroCameraSharedState* state);

#ifdef __cplusplus
}
#endif

#endif // ZERO_CAMERA_STATE_H

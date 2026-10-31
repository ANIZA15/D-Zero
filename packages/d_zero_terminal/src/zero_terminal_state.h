#ifndef ZERO_TERMINAL_STATE_H
#define ZERO_TERMINAL_STATE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
#include <atomic>
extern "C" {
#endif

// 最大ビューポート・スクロールバック定数
#define ZERO_TERM_MAX_COLS 256
#define ZERO_TERM_MAX_ROWS 128
#define ZERO_TERM_VIEWPORT_STRIDE 256
#define ZERO_TERM_VIEWPORT_CELLS (ZERO_TERM_MAX_COLS * ZERO_TERM_MAX_ROWS)
#define ZERO_TERM_MAX_SCROLLBACK 16384
#define ZERO_TERM_MINIMAP_BINS 256

// メモリ安全性カナリア定数 ("ZTRM")
#define ZERO_TERM_MAGIC_ALIVE 0x5A54524Du
#define ZERO_TERM_MAGIC_FREED 0xDEAD5452u

// セル属性ビットフラグ (viewport_attrs)
#define ZERO_TERM_ATTR_NONE      0x00u
#define ZERO_TERM_ATTR_BOLD      0x01u
#define ZERO_TERM_ATTR_DIM       0x02u
#define ZERO_TERM_ATTR_ITALIC    0x04u
#define ZERO_TERM_ATTR_UNDERLINE 0x08u
#define ZERO_TERM_ATTR_BLINK     0x10u
#define ZERO_TERM_ATTR_INVERSE   0x20u

// 特殊キーコード (zero_terminal_send_key_code 用)
typedef enum {
    ZERO_TERM_KEY_ENTER     = 1,
    ZERO_TERM_KEY_BACKSPACE = 2,
    ZERO_TERM_KEY_TAB       = 3,
    ZERO_TERM_KEY_ESCAPE    = 4,
    ZERO_TERM_KEY_UP        = 5,
    ZERO_TERM_KEY_DOWN      = 6,
    ZERO_TERM_KEY_RIGHT     = 7,
    ZERO_TERM_KEY_LEFT      = 8,
    ZERO_TERM_KEY_HOME      = 9,
    ZERO_TERM_KEY_END       = 10,
    ZERO_TERM_KEY_PAGE_UP   = 11,
    ZERO_TERM_KEY_PAGE_DOWN = 12,
    ZERO_TERM_KEY_DELETE    = 13,
    ZERO_TERM_KEY_CTRL_C    = 14,
    ZERO_TERM_KEY_CTRL_D    = 15,
    ZERO_TERM_KEY_CTRL_L    = 16
} ZeroTerminalKeyCode;

// カーソル形状
typedef enum {
    ZERO_TERM_CURSOR_BLOCK     = 0,
    ZERO_TERM_CURSOR_BEAM      = 1,
    ZERO_TERM_CURSOR_UNDERLINE = 2
} ZeroTerminalCursorStyle;

// ターミナルエンジンの動作ステータス
typedef enum {
    ZERO_TERM_STATUS_IDLE        = 0,
    ZERO_TERM_STATUS_PTY_RUNNING = 1,
    ZERO_TERM_STATUS_STREAM_ONLY = 2,
    ZERO_TERM_STATUS_EXITED      = 3,
    ZERO_TERM_STATUS_ERROR       = 4
} ZeroTerminalStatus;

// =========================================================================================
// Dart と Native (C++17 VT Parser & POSIX PTY Thread) で直接共有する 128-byte メモリブロック
// alignas(64) で 2 キャッシュライン (128 bytes) に固定し、False Sharing を防止する。
// =========================================================================================
#ifdef __cplusplus
struct alignas(64) ZeroTerminalState {
    // --- Cache Line 0 (Offsets 0..63): Grid Geometry, Cursor & Process State ---
    std::atomic<int32_t> cols;                // offset  0: 現在の列数 (16..256)
    std::atomic<int32_t> rows;                // offset  4: 現在の行数 (4..128)
    std::atomic<int32_t> scrollback_capacity; // offset  8: スクロールバック最大保持行数
    std::atomic<int32_t> cursor_col;          // offset 12: カーソル列 (0..cols-1)
    std::atomic<int32_t> cursor_row;          // offset 16: カーソル行 (0..rows-1)
    std::atomic<int32_t> cursor_visible;      // offset 20: カーソル可視フラグ (1=表示, 0=非表示)
    std::atomic<int32_t> cursor_style;        // offset 24: ZeroTerminalCursorStyle
    std::atomic<int32_t> scroll_offset;       // offset 28: スクロールバックオフセット (0=最新)
    std::atomic<int32_t> total_lines;         // offset 32: リングバッファ内の有効総行数
    std::atomic<int32_t> status;              // offset 36: ZeroTerminalStatus
    std::atomic<int32_t> child_pid;           // offset 40: PTY 子プロセス PID (-1=未起動)
    std::atomic<int32_t> pty_fd;              // offset 44: PTY マスタ FD (-1=未接続)
    std::atomic<int32_t> exit_code;           // offset 48: 子プロセス終了コード
    std::atomic<int32_t> alt_screen_active;   // offset 52: オルタネートスクリーン (0=通常, 1=Alt)
    std::atomic<uint32_t> seq;                // offset 56: Seqlock カウンタ (書き込み中は奇数)
    std::atomic<uint32_t> magic_guard;        // offset 60: 生存確認カナリア値 (0x5A54524D)

    // --- Cache Line 1 (Offsets 64..127): Telemetry & Dirty Row Mask ---
    std::atomic<uint64_t> bytes_processed;    // offset 64: 累積処理バイト数
    std::atomic<uint64_t> frames_committed;   // offset 72: 累積ビューポート同期回数
    std::atomic<uint64_t> escape_seqs_parsed; // offset 80: 累積エスケープシーケンス解析数
    std::atomic<uint64_t> dirty_row_mask_lo;  // offset 88: 行 0..63 の Dirty ビットマスク
    std::atomic<uint64_t> dirty_row_mask_hi;  // offset 96: 行 64..127 の Dirty ビットマスク
    std::atomic<float> throughput_mb_s;       // offset 104: パーススループット (MB/s)
    std::atomic<float> parse_latency_ns;      // offset 108: 1バイトあたり処理時間 (ns)
    std::atomic<uint32_t> active_fg_argb;     // offset 112: 現在の SGR 前景色 (0xAARRGGBB)
    std::atomic<uint32_t> active_bg_argb;     // offset 116: 現在の SGR 背景色 (0xAARRGGBB)
    std::atomic<uint32_t> active_attrs;       // offset 120: 現在の SGR 属性フラグ
    uint32_t reserved_pad;                    // offset 124: 128-byte アライメントパディング
};

static_assert(sizeof(ZeroTerminalState) == 128, "ZeroTerminalState must be exactly 128 bytes (2 cache lines)");
static_assert(alignof(ZeroTerminalState) == 64, "ZeroTerminalState must be 64-byte cache-line aligned");
#else
typedef struct ZeroTerminalState ZeroTerminalState;
#endif

#if defined(_WIN32)
#define ZERO_TERM_EXPORT __declspec(dllexport)
#else
#define ZERO_TERM_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// ABI バージョン取得 (リンカの Dead-Strip 防止用)
ZERO_TERM_EXPORT uint32_t zero_terminal_abi_version(void);
ZERO_TERM_EXPORT bool zero_terminal_is_state_valid(const ZeroTerminalState* state);

// ターミナル共有メモリ・VTパーサー状態の生成と破棄
ZERO_TERM_EXPORT ZeroTerminalState* zero_terminal_create_state(
    int32_t cols,
    int32_t rows,
    int32_t scrollback_capacity
);
ZERO_TERM_EXPORT void zero_terminal_destroy_state(ZeroTerminalState* state);

// 画面・状態のリセットとリサイズ
ZERO_TERM_EXPORT void zero_terminal_reset(ZeroTerminalState* state);
ZERO_TERM_EXPORT void zero_terminal_clear_screen(ZeroTerminalState* state);
ZERO_TERM_EXPORT void zero_terminal_resize(ZeroTerminalState* state, int32_t cols, int32_t rows);

// スクロールバック操作およびカーソル設定
ZERO_TERM_EXPORT void zero_terminal_set_scroll_offset(ZeroTerminalState* state, int32_t offset);
ZERO_TERM_EXPORT void zero_terminal_scroll_by(ZeroTerminalState* state, int32_t delta_lines);
ZERO_TERM_EXPORT void zero_terminal_set_cursor_style(
    ZeroTerminalState* state,
    int32_t style,
    int32_t visible
);
ZERO_TERM_EXPORT void zero_terminal_clear_dirty_mask(ZeroTerminalState* state);

// ゼロアロケーション VT100/ANSI/UTF-8 ストリーム直接フィード (SSH / テスト / 仮想ストリーム用)
ZERO_TERM_EXPORT int32_t zero_terminal_feed_bytes(
    ZeroTerminalState* state,
    const uint8_t* bytes,
    int32_t length
);

// 実 POSIX PTY (forkpty) の起動・入力送信・停止
ZERO_TERM_EXPORT int32_t zero_terminal_spawn_pty(
    ZeroTerminalState* state,
    const char* shell_path,
    const char* working_dir
);
ZERO_TERM_EXPORT int32_t zero_terminal_write_input(
    ZeroTerminalState* state,
    const uint8_t* bytes,
    int32_t length
);
ZERO_TERM_EXPORT int32_t zero_terminal_send_key_code(
    ZeroTerminalState* state,
    int32_t key_code,
    int32_t modifiers
);
ZERO_TERM_EXPORT void zero_terminal_stop_pty(ZeroTerminalState* state);

// ベンチマーク・ストレステスト用: C++ 側で高速 ANSI TrueColor ログバーストを生成・パース
ZERO_TERM_EXPORT int32_t zero_terminal_generate_stress_burst(
    ZeroTerminalState* state,
    int32_t line_count,
    uint32_t seed
);

// Zero-Copy ビューポート SoA 配列ポインタ取得 (固定容量 ZERO_TERM_VIEWPORT_CELLS = 256 * 128)
ZERO_TERM_EXPORT const uint32_t* zero_terminal_get_viewport_codepoints(const ZeroTerminalState* state);
ZERO_TERM_EXPORT const uint32_t* zero_terminal_get_viewport_fg_argb(const ZeroTerminalState* state);
ZERO_TERM_EXPORT const uint32_t* zero_terminal_get_viewport_bg_argb(const ZeroTerminalState* state);
ZERO_TERM_EXPORT const uint8_t* zero_terminal_get_viewport_attrs(const ZeroTerminalState* state);

// Zero-Copy ミニマップ・レーダー用配列ポインタ取得 (固定容量 ZERO_TERM_MINIMAP_BINS = 256)
ZERO_TERM_EXPORT const uint32_t* zero_terminal_get_minimap_colors(const ZeroTerminalState* state);
ZERO_TERM_EXPORT const uint8_t* zero_terminal_get_minimap_fill(const ZeroTerminalState* state);

#ifdef __cplusplus
}
#endif

#endif // ZERO_TERMINAL_STATE_H

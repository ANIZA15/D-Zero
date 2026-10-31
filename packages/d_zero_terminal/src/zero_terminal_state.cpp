#include "zero_terminal_state.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>
#include <thread>
#include <unordered_set>
#include <vector>

#if defined(__APPLE__)
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <util.h>
#elif defined(__linux__)
#include <fcntl.h>
#include <poll.h>
#include <pty.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace {

constexpr uint32_t kDefaultFgArgb = 0xFFE6EDF3u;
constexpr uint32_t kDefaultBgArgb = 0xFF0D1117u;
constexpr int32_t kMaxCsiParams = 16;

// 標準 16 色 ANSI パレット (Catppuccin / TokyoNight 風ハイコントラスト配色)
constexpr uint32_t kAnsi16Palette[16] = {
    0xFF1F242Du, // 0: Black
    0xFFFF6B6Bu, // 1: Red
    0xFF4ECDC4u, // 2: Green
    0xFFFFE66Du, // 3: Yellow
    0xFF58A6FFu, // 4: Blue
    0xFFBC8CFFu, // 5: Magenta
    0xFF39C5BBu, // 6: Cyan
    0xFFC9D1D9u, // 7: White
    0xFF6E7681u, // 8: Bright Black (Gray)
    0xFFFF8787u, // 9: Bright Red
    0xFF63E6BEu, // 10: Bright Green
    0xFFFFF3BFu, // 11: Bright Yellow
    0xFF79C0FFu, // 12: Bright Blue
    0xFFD2A8FFu, // 13: Bright Magenta
    0xFF56D4DDu, // 14: Bright Cyan
    0xFFFFFFFFu  // 15: Bright White
};

enum ParserMode : uint8_t {
    kModeNormal = 0,
    kModeEscape = 1,
    kModeCsi = 2,
    kModeOsc = 3,
    kModeOscEsc = 4
};

struct alignas(64) ZeroTerminalContext {
    ZeroTerminalState pub;

    std::mutex mutex;
    std::atomic<bool> pty_stop_flag{false};
    std::thread pty_thread;

    // ゼロコピー Viewport SoA バッファ (固定 256 x 128 = 32,768 セル)
    uint32_t viewport_codepoints[ZERO_TERM_VIEWPORT_CELLS];
    uint32_t viewport_fg_argb[ZERO_TERM_VIEWPORT_CELLS];
    uint32_t viewport_bg_argb[ZERO_TERM_VIEWPORT_CELLS];
    uint8_t viewport_attrs[ZERO_TERM_VIEWPORT_CELLS];

    // ミニマップ集計配列 (固定 256 ビン)
    uint32_t minimap_colors[ZERO_TERM_MINIMAP_BINS];
    uint8_t minimap_fill[ZERO_TERM_MINIMAP_BINS];

    // スクロールバック + プライマリ画面リングバッファ
    int32_t ring_capacity = 1024;
    int32_t ring_head = 0; // 画面先頭行 (row=0) に対応するリングインデックス
    std::vector<uint32_t> ring_codepoints;
    std::vector<uint32_t> ring_fg_argb;
    std::vector<uint32_t> ring_bg_argb;
    std::vector<uint8_t> ring_attrs;
    std::vector<uint16_t> ring_line_len;
    std::vector<uint32_t> ring_line_color;

    // オルタネートスクリーン退避用スナップショット (?1049h / ?1049l)
    int32_t saved_cursor_col = 0;
    int32_t saved_cursor_row = 0;
    int32_t alt_saved_col = 0;
    int32_t alt_saved_row = 0;
    uint32_t alt_codepoints[ZERO_TERM_VIEWPORT_CELLS];
    uint32_t alt_fg_argb[ZERO_TERM_VIEWPORT_CELLS];
    uint32_t alt_bg_argb[ZERO_TERM_VIEWPORT_CELLS];
    uint8_t alt_attrs[ZERO_TERM_VIEWPORT_CELLS];

    // VT100 / UTF-8 パーサーステートマシン
    ParserMode parser_mode = kModeNormal;
    bool csi_private = false;
    int32_t csi_params[kMaxCsiParams];
    int32_t csi_param_count = 0;
    bool csi_has_digit = false;

    uint32_t utf8_accum = 0;
    uint8_t utf8_remaining = 0;
};

std::mutex g_live_mutex;
std::unordered_set<uintptr_t> g_live_contexts;

inline int32_t clamp_i32(int32_t v, int32_t lo, int32_t hi) {
    return std::max(lo, std::min(v, hi));
}

bool is_registered_alive(const ZeroTerminalState* state) {
    if (!state) return false;
    const uintptr_t addr = reinterpret_cast<uintptr_t>(state);
    if ((addr & 63u) != 0u) return false;
    std::lock_guard<std::mutex> lock(g_live_mutex);
    if (g_live_contexts.find(addr) == g_live_contexts.end()) return false;
    return state->magic_guard.load(std::memory_order_acquire) == ZERO_TERM_MAGIC_ALIVE;
}

ZeroTerminalContext* as_context(ZeroTerminalState* state) {
    if (!is_registered_alive(state)) return nullptr;
    return reinterpret_cast<ZeroTerminalContext*>(state);
}

const ZeroTerminalContext* as_const_context(const ZeroTerminalState* state) {
    if (!is_registered_alive(state)) return nullptr;
    return reinterpret_cast<const ZeroTerminalContext*>(state);
}

inline void seq_begin(ZeroTerminalState* state) {
    state->seq.fetch_add(1u, std::memory_order_acq_rel);
    std::atomic_thread_fence(std::memory_order_release);
}

inline void seq_end(ZeroTerminalState* state) {
    state->seq.fetch_add(1u, std::memory_order_release);
}

inline void mark_row_dirty(ZeroTerminalState* state, int32_t row) {
    if (row < 0 || row >= ZERO_TERM_MAX_ROWS) return;
    if (row < 64) {
        state->dirty_row_mask_lo.fetch_or(1ULL << row, std::memory_order_relaxed);
    } else {
        state->dirty_row_mask_hi.fetch_or(1ULL << (row - 64), std::memory_order_relaxed);
    }
}

inline void mark_all_rows_dirty(ZeroTerminalState* state) {
    state->dirty_row_mask_lo.store(~0ULL, std::memory_order_relaxed);
    state->dirty_row_mask_hi.store(~0ULL, std::memory_order_relaxed);
}

uint32_t xterm_256_to_argb(int32_t idx) {
    const int32_t clamped = clamp_i32(idx, 0, 255);
    if (clamped < 16) return kAnsi16Palette[clamped];
    if (clamped < 232) {
        const int32_t cube = clamped - 16;
        const int32_t r6 = (cube / 36) % 6;
        const int32_t g6 = (cube / 6) % 6;
        const int32_t b6 = cube % 6;
        const uint32_t r = r6 == 0 ? 0u : static_cast<uint32_t>(55 + r6 * 40);
        const uint32_t g = g6 == 0 ? 0u : static_cast<uint32_t>(55 + g6 * 40);
        const uint32_t b = b6 == 0 ? 0u : static_cast<uint32_t>(55 + b6 * 40);
        return 0xFF000000u | (r << 16) | (g << 8) | b;
    }
    const uint32_t gray = static_cast<uint32_t>(8 + (clamped - 232) * 10);
    return 0xFF000000u | (gray << 16) | (gray << 8) | gray;
}

void clear_ring_row(ZeroTerminalContext* ctx, int32_t ring_row, uint32_t fg, uint32_t bg) {
    const int32_t base = ring_row * ZERO_TERM_MAX_COLS;
    std::fill_n(&ctx->ring_codepoints[base], ZERO_TERM_MAX_COLS, 0x20u);
    std::fill_n(&ctx->ring_fg_argb[base], ZERO_TERM_MAX_COLS, fg);
    std::fill_n(&ctx->ring_bg_argb[base], ZERO_TERM_MAX_COLS, bg);
    std::fill_n(&ctx->ring_attrs[base], ZERO_TERM_MAX_COLS, 0u);
    ctx->ring_line_len[ring_row] = 0u;
    ctx->ring_line_color[ring_row] = fg;
}

void clear_alt_row(ZeroTerminalContext* ctx, int32_t row, uint32_t fg, uint32_t bg) {
    const int32_t base = row * ZERO_TERM_VIEWPORT_STRIDE;
    std::fill_n(&ctx->alt_codepoints[base], ZERO_TERM_MAX_COLS, 0x20u);
    std::fill_n(&ctx->alt_fg_argb[base], ZERO_TERM_MAX_COLS, fg);
    std::fill_n(&ctx->alt_bg_argb[base], ZERO_TERM_MAX_COLS, bg);
    std::fill_n(&ctx->alt_attrs[base], ZERO_TERM_MAX_COLS, 0u);
}

int32_t screen_row_to_ring(const ZeroTerminalContext* ctx, int32_t screen_row) {
    return (ctx->ring_head + screen_row) % ctx->ring_capacity;
}

void sync_minimap_bins(ZeroTerminalContext* ctx, int32_t total_lines, int32_t cols) {
    const int32_t oldest_ring =
        (ctx->ring_head + ctx->pub.rows.load(std::memory_order_relaxed) - total_lines + ctx->ring_capacity) %
        ctx->ring_capacity;
    const int32_t safe_cols = std::max(1, cols);
    for (int32_t b = 0; b < ZERO_TERM_MINIMAP_BINS; ++b) {
        const int32_t line_idx = (b * total_lines) / ZERO_TERM_MINIMAP_BINS;
        const int32_t r_idx = (oldest_ring + line_idx) % ctx->ring_capacity;
        const int32_t len = ctx->ring_line_len[r_idx];
        ctx->minimap_fill[b] = static_cast<uint8_t>(clamp_i32((len * 255) / safe_cols, 0, 255));
        ctx->minimap_colors[b] = ctx->ring_line_color[r_idx];
    }
}

void copy_alt_to_viewport(ZeroTerminalContext* ctx, int32_t rows) {
    const int32_t count = rows * ZERO_TERM_VIEWPORT_STRIDE;
    std::memcpy(ctx->viewport_codepoints, ctx->alt_codepoints, count * sizeof(uint32_t));
    std::memcpy(ctx->viewport_fg_argb, ctx->alt_fg_argb, count * sizeof(uint32_t));
    std::memcpy(ctx->viewport_bg_argb, ctx->alt_bg_argb, count * sizeof(uint32_t));
    std::memcpy(ctx->viewport_attrs, ctx->alt_attrs, count * sizeof(uint8_t));
}

void copy_ring_to_viewport(ZeroTerminalContext* ctx, int32_t rows, int32_t scroll_off) {
    for (int32_t r = 0; r < rows; ++r) {
        const int32_t ring_r =
            (ctx->ring_head + r - scroll_off + ctx->ring_capacity) % ctx->ring_capacity;
        const int32_t src_base = ring_r * ZERO_TERM_MAX_COLS;
        const int32_t dst_base = r * ZERO_TERM_VIEWPORT_STRIDE;
        std::memcpy(&ctx->viewport_codepoints[dst_base], &ctx->ring_codepoints[src_base],
                    ZERO_TERM_MAX_COLS * sizeof(uint32_t));
        std::memcpy(&ctx->viewport_fg_argb[dst_base], &ctx->ring_fg_argb[src_base],
                    ZERO_TERM_MAX_COLS * sizeof(uint32_t));
        std::memcpy(&ctx->viewport_bg_argb[dst_base], &ctx->ring_bg_argb[src_base],
                    ZERO_TERM_MAX_COLS * sizeof(uint32_t));
        std::memcpy(&ctx->viewport_attrs[dst_base], &ctx->ring_attrs[src_base],
                    ZERO_TERM_MAX_COLS * sizeof(uint8_t));
    }
}

void commit_viewport_locked(ZeroTerminalContext* ctx) {
    const int32_t rows = ctx->pub.rows.load(std::memory_order_relaxed);
    const int32_t cols = ctx->pub.cols.load(std::memory_order_relaxed);
    const int32_t total = ctx->pub.total_lines.load(std::memory_order_relaxed);
    const int32_t max_scroll = std::max(0, total - rows);
    const int32_t scroll_off =
        clamp_i32(ctx->pub.scroll_offset.load(std::memory_order_relaxed), 0, max_scroll);
    ctx->pub.scroll_offset.store(scroll_off, std::memory_order_relaxed);

    seq_begin(&ctx->pub);
    if (ctx->pub.alt_screen_active.load(std::memory_order_relaxed) != 0) {
        copy_alt_to_viewport(ctx, rows);
    } else {
        copy_ring_to_viewport(ctx, rows, scroll_off);
    }
    sync_minimap_bins(ctx, std::max(rows, total), cols);
    ctx->pub.frames_committed.fetch_add(1u, std::memory_order_relaxed);
    mark_all_rows_dirty(&ctx->pub);
    seq_end(&ctx->pub);
}

void advance_line_locked(ZeroTerminalContext* ctx) {
    const int32_t rows = ctx->pub.rows.load(std::memory_order_relaxed);
    const int32_t cur_row = ctx->pub.cursor_row.load(std::memory_order_relaxed);
    if (cur_row + 1 < rows) {
        ctx->pub.cursor_row.store(cur_row + 1, std::memory_order_relaxed);
        return;
    }
    if (ctx->pub.alt_screen_active.load(std::memory_order_relaxed) != 0) {
        const int32_t move_cells = (rows - 1) * ZERO_TERM_VIEWPORT_STRIDE;
        std::memmove(ctx->alt_codepoints, &ctx->alt_codepoints[ZERO_TERM_VIEWPORT_STRIDE],
                     move_cells * sizeof(uint32_t));
        std::memmove(ctx->alt_fg_argb, &ctx->alt_fg_argb[ZERO_TERM_VIEWPORT_STRIDE],
                     move_cells * sizeof(uint32_t));
        std::memmove(ctx->alt_bg_argb, &ctx->alt_bg_argb[ZERO_TERM_VIEWPORT_STRIDE],
                     move_cells * sizeof(uint32_t));
        std::memmove(ctx->alt_attrs, &ctx->alt_attrs[ZERO_TERM_VIEWPORT_STRIDE],
                     move_cells * sizeof(uint8_t));
        clear_alt_row(ctx, rows - 1, kDefaultFgArgb, kDefaultBgArgb);
        return;
    }
    ctx->ring_head = (ctx->ring_head + 1) % ctx->ring_capacity;
    const int32_t new_bottom = screen_row_to_ring(ctx, rows - 1);
    clear_ring_row(ctx, new_bottom, kDefaultFgArgb, kDefaultBgArgb);
    const int32_t prev_total = ctx->pub.total_lines.load(std::memory_order_relaxed);
    if (prev_total < ctx->ring_capacity) {
        ctx->pub.total_lines.store(prev_total + 1, std::memory_order_relaxed);
    }
}

void write_cell_locked(ZeroTerminalContext* ctx, int32_t row, int32_t col, uint32_t cp) {
    const uint32_t fg = ctx->pub.active_fg_argb.load(std::memory_order_relaxed);
    const uint32_t bg = ctx->pub.active_bg_argb.load(std::memory_order_relaxed);
    const uint8_t attr = static_cast<uint8_t>(ctx->pub.active_attrs.load(std::memory_order_relaxed));

    if (ctx->pub.alt_screen_active.load(std::memory_order_relaxed) != 0) {
        const int32_t idx = row * ZERO_TERM_VIEWPORT_STRIDE + col;
        ctx->alt_codepoints[idx] = cp;
        ctx->alt_fg_argb[idx] = fg;
        ctx->alt_bg_argb[idx] = bg;
        ctx->alt_attrs[idx] = attr;
        return;
    }
    const int32_t ring_r = screen_row_to_ring(ctx, row);
    const int32_t idx = ring_r * ZERO_TERM_MAX_COLS + col;
    ctx->ring_codepoints[idx] = cp;
    ctx->ring_fg_argb[idx] = fg;
    ctx->ring_bg_argb[idx] = bg;
    ctx->ring_attrs[idx] = attr;
    if (col + 1 > ctx->ring_line_len[ring_r]) {
        ctx->ring_line_len[ring_r] = static_cast<uint16_t>(col + 1);
    }
    if (cp > 0x20u) {
        ctx->ring_line_color[ring_r] = fg;
    }
}

void put_codepoint_locked(ZeroTerminalContext* ctx, uint32_t cp) {
    const int32_t cols = ctx->pub.cols.load(std::memory_order_relaxed);
    int32_t col = ctx->pub.cursor_col.load(std::memory_order_relaxed);
    if (col >= cols) {
        ctx->pub.cursor_col.store(0, std::memory_order_relaxed);
        advance_line_locked(ctx);
        col = 0;
    }
    const int32_t row = ctx->pub.cursor_row.load(std::memory_order_relaxed);
    write_cell_locked(ctx, row, col, cp);
    ctx->pub.cursor_col.store(col + 1, std::memory_order_relaxed);
    mark_row_dirty(&ctx->pub, row);
}

void handle_control_char_locked(ZeroTerminalContext* ctx, uint8_t ch) {
    if (ch == '\r') {
        ctx->pub.cursor_col.store(0, std::memory_order_relaxed);
    } else if (ch == '\n' || ch == '\v' || ch == '\f') {
        advance_line_locked(ctx);
    } else if (ch == '\b') {
        const int32_t col = ctx->pub.cursor_col.load(std::memory_order_relaxed);
        ctx->pub.cursor_col.store(std::max(0, col - 1), std::memory_order_relaxed);
    } else if (ch == '\t') {
        const int32_t cols = ctx->pub.cols.load(std::memory_order_relaxed);
        const int32_t col = ctx->pub.cursor_col.load(std::memory_order_relaxed);
        const int32_t next_tab = std::min(cols - 1, ((col >> 3) + 1) << 3);
        ctx->pub.cursor_col.store(next_tab, std::memory_order_relaxed);
    }
}

void erase_in_line_locked(ZeroTerminalContext* ctx, int32_t mode) {
    const int32_t cols = ctx->pub.cols.load(std::memory_order_relaxed);
    const int32_t row = ctx->pub.cursor_row.load(std::memory_order_relaxed);
    const int32_t col = clamp_i32(ctx->pub.cursor_col.load(std::memory_order_relaxed), 0, cols - 1);
    const int32_t start_c = (mode == 0) ? col : 0;
    const int32_t end_c = (mode == 1) ? (col + 1) : cols;
    for (int32_t c = start_c; c < end_c; ++c) {
        write_cell_locked(ctx, row, c, 0x20u);
    }
    if (mode == 2 && ctx->pub.alt_screen_active.load(std::memory_order_relaxed) == 0) {
        ctx->ring_line_len[screen_row_to_ring(ctx, row)] = 0u;
    }
}

void erase_in_display_locked(ZeroTerminalContext* ctx, int32_t mode) {
    const int32_t rows = ctx->pub.rows.load(std::memory_order_relaxed);
    const int32_t cur_row = ctx->pub.cursor_row.load(std::memory_order_relaxed);
    if (mode == 2 || mode == 3) {
        for (int32_t r = 0; r < rows; ++r) {
            if (ctx->pub.alt_screen_active.load(std::memory_order_relaxed) != 0) {
                clear_alt_row(ctx, r, kDefaultFgArgb, kDefaultBgArgb);
            } else {
                clear_ring_row(ctx, screen_row_to_ring(ctx, r), kDefaultFgArgb, kDefaultBgArgb);
            }
        }
        return;
    }
    erase_in_line_locked(ctx, mode);
    const int32_t r_start = (mode == 0) ? (cur_row + 1) : 0;
    const int32_t r_end = (mode == 0) ? rows : cur_row;
    for (int32_t r = r_start; r < r_end; ++r) {
        if (ctx->pub.alt_screen_active.load(std::memory_order_relaxed) != 0) {
            clear_alt_row(ctx, r, kDefaultFgArgb, kDefaultBgArgb);
        } else {
            clear_ring_row(ctx, screen_row_to_ring(ctx, r), kDefaultFgArgb, kDefaultBgArgb);
        }
    }
}

int32_t apply_extended_color_locked(ZeroTerminalContext* ctx, bool is_fg, int32_t idx) {
    if (idx + 1 >= ctx->csi_param_count) return idx;
    const int32_t kind = ctx->csi_params[idx + 1];
    if (kind == 5 && idx + 2 < ctx->csi_param_count) {
        const uint32_t col = xterm_256_to_argb(ctx->csi_params[idx + 2]);
        if (is_fg) ctx->pub.active_fg_argb.store(col, std::memory_order_relaxed);
        else ctx->pub.active_bg_argb.store(col, std::memory_order_relaxed);
        return idx + 2;
    }
    if (kind == 2 && idx + 4 < ctx->csi_param_count) {
        const uint32_t r = static_cast<uint32_t>(clamp_i32(ctx->csi_params[idx + 2], 0, 255));
        const uint32_t g = static_cast<uint32_t>(clamp_i32(ctx->csi_params[idx + 3], 0, 255));
        const uint32_t b = static_cast<uint32_t>(clamp_i32(ctx->csi_params[idx + 4], 0, 255));
        const uint32_t col = 0xFF000000u | (r << 16) | (g << 8) | b;
        if (is_fg) ctx->pub.active_fg_argb.store(col, std::memory_order_relaxed);
        else ctx->pub.active_bg_argb.store(col, std::memory_order_relaxed);
        return idx + 4;
    }
    return idx;
}

void apply_single_sgr_attr_locked(ZeroTerminalContext* ctx, int32_t code) {
    uint32_t attrs = ctx->pub.active_attrs.load(std::memory_order_relaxed);
    if (code == 0) {
        ctx->pub.active_fg_argb.store(kDefaultFgArgb, std::memory_order_relaxed);
        ctx->pub.active_bg_argb.store(kDefaultBgArgb, std::memory_order_relaxed);
        ctx->pub.active_attrs.store(ZERO_TERM_ATTR_NONE, std::memory_order_relaxed);
        return;
    }
    static constexpr uint8_t kSetAttrMap[8] = {
        0, ZERO_TERM_ATTR_BOLD, ZERO_TERM_ATTR_DIM, ZERO_TERM_ATTR_ITALIC,
        ZERO_TERM_ATTR_UNDERLINE, ZERO_TERM_ATTR_BLINK, 0, ZERO_TERM_ATTR_INVERSE
    };
    if (code >= 1 && code <= 7) {
        ctx->pub.active_attrs.store(attrs | kSetAttrMap[code], std::memory_order_relaxed);
    } else if (code == 22) {
        ctx->pub.active_attrs.store(attrs & ~(ZERO_TERM_ATTR_BOLD | ZERO_TERM_ATTR_DIM), std::memory_order_relaxed);
    } else if (code == 24) {
        ctx->pub.active_attrs.store(attrs & ~ZERO_TERM_ATTR_UNDERLINE, std::memory_order_relaxed);
    } else if (code == 27) {
        ctx->pub.active_attrs.store(attrs & ~ZERO_TERM_ATTR_INVERSE, std::memory_order_relaxed);
    }
}

void apply_sgr_fg_range_locked(ZeroTerminalContext* ctx, int32_t code) {
    if (code >= 30 && code <= 37) {
        ctx->pub.active_fg_argb.store(kAnsi16Palette[code - 30], std::memory_order_relaxed);
    } else if (code == 39) {
        ctx->pub.active_fg_argb.store(kDefaultFgArgb, std::memory_order_relaxed);
    } else if (code >= 90 && code <= 97) {
        ctx->pub.active_fg_argb.store(kAnsi16Palette[8 + (code - 90)], std::memory_order_relaxed);
    }
}

void apply_sgr_bg_range_locked(ZeroTerminalContext* ctx, int32_t code) {
    if (code >= 40 && code <= 47) {
        ctx->pub.active_bg_argb.store(kAnsi16Palette[code - 40], std::memory_order_relaxed);
    } else if (code == 49) {
        ctx->pub.active_bg_argb.store(kDefaultBgArgb, std::memory_order_relaxed);
    } else if (code >= 100 && code <= 107) {
        ctx->pub.active_bg_argb.store(kAnsi16Palette[8 + (code - 100)], std::memory_order_relaxed);
    }
}

void apply_single_sgr_color_locked(ZeroTerminalContext* ctx, int32_t code) {
    apply_sgr_fg_range_locked(ctx, code);
    apply_sgr_bg_range_locked(ctx, code);
}

void handle_sgr_locked(ZeroTerminalContext* ctx) {
    if (ctx->csi_param_count == 0) {
        apply_single_sgr_attr_locked(ctx, 0);
        return;
    }
    for (int32_t i = 0; i < ctx->csi_param_count; ++i) {
        const int32_t code = ctx->csi_params[i];
        if (code == 38 || code == 48) {
            i = apply_extended_color_locked(ctx, code == 38, i);
        } else if (code < 30) {
            apply_single_sgr_attr_locked(ctx, code);
        } else {
            apply_single_sgr_color_locked(ctx, code);
        }
    }
}

void handle_private_mode_locked(ZeroTerminalContext* ctx, uint8_t final_byte) {
    const bool enable = (final_byte == 'h');
    if (final_byte != 'h' && final_byte != 'l') return;
    const int32_t mode = (ctx->csi_param_count > 0) ? ctx->csi_params[0] : 0;
    if (mode == 25) {
        ctx->pub.cursor_visible.store(enable ? 1 : 0, std::memory_order_relaxed);
        return;
    }
    if (mode == 1049 || mode == 47 || mode == 1047) {
        if (enable) {
            ctx->alt_saved_col = ctx->pub.cursor_col.load(std::memory_order_relaxed);
            ctx->alt_saved_row = ctx->pub.cursor_row.load(std::memory_order_relaxed);
            ctx->pub.alt_screen_active.store(1, std::memory_order_relaxed);
            ctx->pub.cursor_col.store(0, std::memory_order_relaxed);
            ctx->pub.cursor_row.store(0, std::memory_order_relaxed);
            erase_in_display_locked(ctx, 2);
        } else {
            ctx->pub.alt_screen_active.store(0, std::memory_order_relaxed);
            ctx->pub.cursor_col.store(ctx->alt_saved_col, std::memory_order_relaxed);
            ctx->pub.cursor_row.store(ctx->alt_saved_row, std::memory_order_relaxed);
        }
    }
}

void dispatch_csi_cursor_locked(ZeroTerminalContext* ctx, uint8_t cmd, int32_t p0, int32_t p1) {
    const int32_t cols = ctx->pub.cols.load(std::memory_order_relaxed);
    const int32_t rows = ctx->pub.rows.load(std::memory_order_relaxed);
    const int32_t c = ctx->pub.cursor_col.load(std::memory_order_relaxed);
    const int32_t r = ctx->pub.cursor_row.load(std::memory_order_relaxed);
    const int32_t step = std::max(1, p0);

    if (cmd == 'A') ctx->pub.cursor_row.store(clamp_i32(r - step, 0, rows - 1), std::memory_order_relaxed);
    else if (cmd == 'B') ctx->pub.cursor_row.store(clamp_i32(r + step, 0, rows - 1), std::memory_order_relaxed);
    else if (cmd == 'C') ctx->pub.cursor_col.store(clamp_i32(c + step, 0, cols - 1), std::memory_order_relaxed);
    else if (cmd == 'D') ctx->pub.cursor_col.store(clamp_i32(c - step, 0, cols - 1), std::memory_order_relaxed);
    else if (cmd == 'G') ctx->pub.cursor_col.store(clamp_i32(step - 1, 0, cols - 1), std::memory_order_relaxed);
    else if (cmd == 'd') ctx->pub.cursor_row.store(clamp_i32(step - 1, 0, rows - 1), std::memory_order_relaxed);
    else if (cmd == 'H' || cmd == 'f') {
        ctx->pub.cursor_row.store(clamp_i32( std::max(1, p0) - 1, 0, rows - 1), std::memory_order_relaxed);
        ctx->pub.cursor_col.store(clamp_i32( std::max(1, p1) - 1, 0, cols - 1), std::memory_order_relaxed);
    }
}

void execute_csi_locked(ZeroTerminalContext* ctx, uint8_t final_byte) {
    ctx->pub.escape_seqs_parsed.fetch_add(1u, std::memory_order_relaxed);
    if (ctx->csi_private) {
        handle_private_mode_locked(ctx, final_byte);
        return;
    }
    const int32_t p0 = (ctx->csi_param_count > 0) ? ctx->csi_params[0] : 0;
    const int32_t p1 = (ctx->csi_param_count > 1) ? ctx->csi_params[1] : 1;

    if (final_byte == 'm') {
        handle_sgr_locked(ctx);
    } else if (final_byte == 'J') {
        erase_in_display_locked(ctx, p0);
    } else if (final_byte == 'K') {
        erase_in_line_locked(ctx, p0);
    } else if (final_byte == 's') {
        ctx->saved_cursor_col = ctx->pub.cursor_col.load(std::memory_order_relaxed);
        ctx->saved_cursor_row = ctx->pub.cursor_row.load(std::memory_order_relaxed);
    } else if (final_byte == 'u') {
        ctx->pub.cursor_col.store(ctx->saved_cursor_col, std::memory_order_relaxed);
        ctx->pub.cursor_row.store(ctx->saved_cursor_row, std::memory_order_relaxed);
    } else {
        dispatch_csi_cursor_locked(ctx, final_byte, p0, p1);
    }
}

void reset_csi_state(ZeroTerminalContext* ctx) {
    ctx->csi_private = false;
    ctx->csi_param_count = 0;
    ctx->csi_has_digit = false;
    ctx->csi_params[0] = 0;
}

void append_csi_digit_locked(ZeroTerminalContext* ctx, uint8_t b) {
    if (!ctx->csi_has_digit) {
        ctx->csi_has_digit = true;
        if (ctx->csi_param_count == 0) ctx->csi_param_count = 1;
        ctx->csi_params[ctx->csi_param_count - 1] = 0;
    }
    const int32_t idx = ctx->csi_param_count - 1;
    ctx->csi_params[idx] = clamp_i32(ctx->csi_params[idx] * 10 + (b - '0'), 0, 65535);
}

void advance_csi_separator_locked(ZeroTerminalContext* ctx) {
    if (!ctx->csi_has_digit && ctx->csi_param_count == 0) {
        ctx->csi_params[0] = 0;
        ctx->csi_param_count = 1;
    }
    if (ctx->csi_param_count < kMaxCsiParams) {
        ctx->csi_params[ctx->csi_param_count++] = 0;
    }
    ctx->csi_has_digit = false;
}

void feed_csi_byte_locked(ZeroTerminalContext* ctx, uint8_t b) {
    if (b == '?') {
        ctx->csi_private = true;
    } else if (b >= '0' && b <= '9') {
        append_csi_digit_locked(ctx, b);
    } else if (b == ';' || b == ':') {
        advance_csi_separator_locked(ctx);
    } else if (b >= 0x40 && b <= 0x7E) {
        execute_csi_locked(ctx, b);
        ctx->parser_mode = kModeNormal;
    }
}

void feed_escape_byte_locked(ZeroTerminalContext* ctx, uint8_t b) {
    if (b == '[') {
        reset_csi_state(ctx);
        ctx->parser_mode = kModeCsi;
    } else if (b == ']') {
        ctx->parser_mode = kModeOsc;
    } else if (b == 'c') {
        erase_in_display_locked(ctx, 2);
        ctx->pub.cursor_col.store(0, std::memory_order_relaxed);
        ctx->pub.cursor_row.store(0, std::memory_order_relaxed);
        ctx->parser_mode = kModeNormal;
    } else if (b == '7') {
        ctx->saved_cursor_col = ctx->pub.cursor_col.load(std::memory_order_relaxed);
        ctx->saved_cursor_row = ctx->pub.cursor_row.load(std::memory_order_relaxed);
        ctx->parser_mode = kModeNormal;
    } else if (b == '8') {
        ctx->pub.cursor_col.store(ctx->saved_cursor_col, std::memory_order_relaxed);
        ctx->pub.cursor_row.store(ctx->saved_cursor_row, std::memory_order_relaxed);
        ctx->parser_mode = kModeNormal;
    } else {
        ctx->parser_mode = kModeNormal;
    }
}

void feed_utf8_or_ascii_locked(ZeroTerminalContext* ctx, uint8_t b) {
    if (ctx->utf8_remaining > 0) {
        if ((b & 0xC0u) == 0x80u) {
            ctx->utf8_accum = (ctx->utf8_accum << 6) | (b & 0x3Fu);
            ctx->utf8_remaining--;
            if (ctx->utf8_remaining == 0) {
                put_codepoint_locked(ctx, ctx->utf8_accum);
            }
            return;
        }
        ctx->utf8_remaining = 0;
    }
    if (b < 0x20u) {
        handle_control_char_locked(ctx, b);
    } else if (b < 0x80u) {
        put_codepoint_locked(ctx, b);
    } else if ((b & 0xE0u) == 0xC0u) {
        ctx->utf8_accum = b & 0x1Fu;
        ctx->utf8_remaining = 1;
    } else if ((b & 0xF0u) == 0xE0u) {
        ctx->utf8_accum = b & 0x0Fu;
        ctx->utf8_remaining = 2;
    } else if ((b & 0xF8u) == 0xF0u) {
        ctx->utf8_accum = b & 0x07u;
        ctx->utf8_remaining = 3;
    }
}

void parse_byte_locked(ZeroTerminalContext* ctx, uint8_t b) {
    if (b == 0x1Bu) {
        if (ctx->parser_mode == kModeOsc) {
            ctx->parser_mode = kModeOscEsc;
        } else {
            ctx->parser_mode = kModeEscape;
        }
        return;
    }
    if (ctx->parser_mode == kModeNormal) {
        feed_utf8_or_ascii_locked(ctx, b);
    } else if (ctx->parser_mode == kModeCsi) {
        feed_csi_byte_locked(ctx, b);
    } else if (ctx->parser_mode == kModeEscape) {
        feed_escape_byte_locked(ctx, b);
    } else if (ctx->parser_mode == kModeOsc && b == 0x07u) {
        ctx->parser_mode = kModeNormal;
    } else if (ctx->parser_mode == kModeOscEsc) {
        ctx->parser_mode = kModeNormal;
    }
}

void parse_chunk_locked(ZeroTerminalContext* ctx, const uint8_t* bytes, int32_t length) {
    using namespace std::chrono;
    const auto t0 = steady_clock::now();
    for (int32_t i = 0; i < length; ++i) {
        parse_byte_locked(ctx, bytes[i]);
    }
    commit_viewport_locked(ctx);
    const auto t1 = steady_clock::now();
    const double elapsed_ns =
        static_cast<double>(duration_cast<nanoseconds>(t1 - t0).count());
    const double safe_ns = std::max(1.0, elapsed_ns);
    const float mb_s = static_cast<float>((static_cast<double>(length) * 1000.0) / safe_ns);
    const float ns_per_byte = static_cast<float>(safe_ns / std::max(1, length));
    ctx->pub.bytes_processed.fetch_add(static_cast<uint64_t>(length), std::memory_order_relaxed);
    ctx->pub.throughput_mb_s.store(mb_s, std::memory_order_relaxed);
    ctx->pub.parse_latency_ns.store(ns_per_byte, std::memory_order_relaxed);
}

void reset_buffers_locked(ZeroTerminalContext* ctx) {
    ctx->ring_head = 0;
    for (int32_t r = 0; r < ctx->ring_capacity; ++r) {
        clear_ring_row(ctx, r, kDefaultFgArgb, kDefaultBgArgb);
    }
    for (int32_t r = 0; r < ZERO_TERM_MAX_ROWS; ++r) {
        clear_alt_row(ctx, r, kDefaultFgArgb, kDefaultBgArgb);
    }
    ctx->pub.cursor_col.store(0, std::memory_order_relaxed);
    ctx->pub.cursor_row.store(0, std::memory_order_relaxed);
    ctx->pub.scroll_offset.store(0, std::memory_order_relaxed);
    ctx->pub.total_lines.store(ctx->pub.rows.load(std::memory_order_relaxed), std::memory_order_relaxed);
    ctx->pub.alt_screen_active.store(0, std::memory_order_relaxed);
    ctx->pub.active_fg_argb.store(kDefaultFgArgb, std::memory_order_relaxed);
    ctx->pub.active_bg_argb.store(kDefaultBgArgb, std::memory_order_relaxed);
    ctx->pub.active_attrs.store(ZERO_TERM_ATTR_NONE, std::memory_order_relaxed);
    ctx->parser_mode = kModeNormal;
    ctx->utf8_remaining = 0;
    commit_viewport_locked(ctx);
}

#if defined(__APPLE__) || defined(__linux__)
void pty_reader_loop(ZeroTerminalContext* ctx, int fd, pid_t pid) {
    uint8_t buf[16384];
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;

    while (!ctx->pty_stop_flag.load(std::memory_order_acquire)) {
        const int pr = ::poll(&pfd, 1, 25);
        if (pr > 0 && (pfd.revents & POLLIN) != 0) {
            const ssize_t n = ::read(fd, buf, sizeof(buf));
            if (n > 0) {
                std::lock_guard<std::mutex> lock(ctx->mutex);
                parse_chunk_locked(ctx, buf, static_cast<int32_t>(n));
                continue;
            }
            break;
        }
        if (pr > 0 && (pfd.revents & (POLLHUP | POLLERR | POLLNVAL)) != 0) {
            break;
        }
    }
    int status_code = 0;
    ::waitpid(pid, &status_code, WNOHANG);
    ctx->pub.exit_code.store(WIFEXITED(status_code) ? WEXITSTATUS(status_code) : 0,
                             std::memory_order_relaxed);
    if (ctx->pub.status.load(std::memory_order_relaxed) == ZERO_TERM_STATUS_PTY_RUNNING) {
        ctx->pub.status.store(ZERO_TERM_STATUS_EXITED, std::memory_order_release);
    }
}
#endif

void stop_pty_internal(ZeroTerminalContext* ctx) {
    ctx->pty_stop_flag.store(true, std::memory_order_release);
#if defined(__APPLE__) || defined(__linux__)
    const int fd = ctx->pub.pty_fd.exchange(-1, std::memory_order_acq_rel);
    const int pid = ctx->pub.child_pid.exchange(-1, std::memory_order_acq_rel);
    if (pid > 0) {
        ::kill(pid, SIGHUP);
    }
    if (fd >= 0) {
        ::close(fd);
    }
#endif
    if (ctx->pty_thread.joinable()) {
        ctx->pty_thread.join();
    }
}

struct KeySeqEntry {
    const char* seq;
    int32_t len;
};

constexpr KeySeqEntry kKeyTable[17] = {
    {"", 0},         // 0: Unused
    {"\r", 1},       // 1: ENTER
    {"\x7f", 1},     // 2: BACKSPACE
    {"\t", 1},       // 3: TAB
    {"\x1b", 1},     // 4: ESCAPE
    {"\x1b[A", 3},   // 5: UP
    {"\x1b[B", 3},   // 6: DOWN
    {"\x1b[C", 3},   // 7: RIGHT
    {"\x1b[D", 3},   // 8: LEFT
    {"\x1b[H", 3},   // 9: HOME
    {"\x1b[F", 3},   // 10: END
    {"\x1b[5~", 4},  // 11: PAGE_UP
    {"\x1b[6~", 4},  // 12: PAGE_DOWN
    {"\x1b[3~", 4},  // 13: DELETE
    {"\x03", 1},     // 14: CTRL_C
    {"\x04", 1},     // 15: CTRL_D
    {"\x0c", 1}      // 16: CTRL_L
};

} // namespace

extern "C" {

uint32_t zero_terminal_abi_version(void) {
    return 0x00010004u;
}

bool zero_terminal_is_state_valid(const ZeroTerminalState* state) {
    return is_registered_alive(state);
}

ZeroTerminalState* zero_terminal_create_state(
    int32_t cols,
    int32_t rows,
    int32_t scrollback_capacity
) {
    auto* ctx = new (std::nothrow) ZeroTerminalContext();
    if (!ctx) return nullptr;

    const int32_t safe_cols = clamp_i32(cols, 16, ZERO_TERM_MAX_COLS);
    const int32_t safe_rows = clamp_i32(rows, 4, ZERO_TERM_MAX_ROWS);
    const int32_t safe_scroll = clamp_i32(scrollback_capacity, safe_rows, ZERO_TERM_MAX_SCROLLBACK);

    ctx->ring_capacity = safe_scroll;
    const size_t total_ring_cells = static_cast<size_t>(safe_scroll) * ZERO_TERM_MAX_COLS;
    ctx->ring_codepoints.assign(total_ring_cells, 0x20u);
    ctx->ring_fg_argb.assign(total_ring_cells, kDefaultFgArgb);
    ctx->ring_bg_argb.assign(total_ring_cells, kDefaultBgArgb);
    ctx->ring_attrs.assign(total_ring_cells, 0u);
    ctx->ring_line_len.assign(static_cast<size_t>(safe_scroll), 0u);
    ctx->ring_line_color.assign(static_cast<size_t>(safe_scroll), kDefaultFgArgb);

    ctx->pub.cols.store(safe_cols, std::memory_order_relaxed);
    ctx->pub.rows.store(safe_rows, std::memory_order_relaxed);
    ctx->pub.scrollback_capacity.store(safe_scroll, std::memory_order_relaxed);
    ctx->pub.cursor_visible.store(1, std::memory_order_relaxed);
    ctx->pub.cursor_style.store(ZERO_TERM_CURSOR_BLOCK, std::memory_order_relaxed);
    ctx->pub.status.store(ZERO_TERM_STATUS_IDLE, std::memory_order_relaxed);
    ctx->pub.child_pid.store(-1, std::memory_order_relaxed);
    ctx->pub.pty_fd.store(-1, std::memory_order_relaxed);
    ctx->pub.exit_code.store(0, std::memory_order_relaxed);
    ctx->pub.seq.store(0u, std::memory_order_relaxed);
    ctx->pub.bytes_processed.store(0u, std::memory_order_relaxed);
    ctx->pub.frames_committed.store(0u, std::memory_order_relaxed);
    ctx->pub.escape_seqs_parsed.store(0u, std::memory_order_relaxed);
    ctx->pub.throughput_mb_s.store(0.0f, std::memory_order_relaxed);
    ctx->pub.parse_latency_ns.store(0.0f, std::memory_order_relaxed);
    ctx->pub.reserved_pad = 0u;
    ctx->pub.magic_guard.store(ZERO_TERM_MAGIC_ALIVE, std::memory_order_release);

    reset_buffers_locked(ctx);
    {
        std::lock_guard<std::mutex> lock(g_live_mutex);
        g_live_contexts.insert(reinterpret_cast<uintptr_t>(&ctx->pub));
    }
    return &ctx->pub;
}

void zero_terminal_destroy_state(ZeroTerminalState* state) {
    if (!state) return;
    const uintptr_t addr = reinterpret_cast<uintptr_t>(state);
    if ((addr & 63u) != 0u) return;
    {
        std::lock_guard<std::mutex> lock(g_live_mutex);
        auto it = g_live_contexts.find(addr);
        if (it == g_live_contexts.end()) return;
        g_live_contexts.erase(it);
    }
    auto* ctx = reinterpret_cast<ZeroTerminalContext*>(state);
    ctx->pub.magic_guard.store(ZERO_TERM_MAGIC_FREED, std::memory_order_release);
    stop_pty_internal(ctx);
    delete ctx;
}

void zero_terminal_reset(ZeroTerminalState* state) {
    auto* ctx = as_context(state);
    if (!ctx) return;
    std::lock_guard<std::mutex> lock(ctx->mutex);
    reset_buffers_locked(ctx);
}

void zero_terminal_clear_screen(ZeroTerminalState* state) {
    auto* ctx = as_context(state);
    if (!ctx) return;
    std::lock_guard<std::mutex> lock(ctx->mutex);
    erase_in_display_locked(ctx, 2);
    ctx->pub.cursor_col.store(0, std::memory_order_relaxed);
    ctx->pub.cursor_row.store(0, std::memory_order_relaxed);
    commit_viewport_locked(ctx);
}

void zero_terminal_resize(ZeroTerminalState* state, int32_t cols, int32_t rows) {
    auto* ctx = as_context(state);
    if (!ctx) return;
    const int32_t safe_cols = clamp_i32(cols, 16, ZERO_TERM_MAX_COLS);
    const int32_t safe_rows = clamp_i32(rows, 4, std::min(ZERO_TERM_MAX_ROWS, ctx->ring_capacity));
    {
        std::lock_guard<std::mutex> lock(ctx->mutex);
        ctx->pub.cols.store(safe_cols, std::memory_order_relaxed);
        ctx->pub.rows.store(safe_rows, std::memory_order_relaxed);
        ctx->pub.cursor_col.store(
            clamp_i32(ctx->pub.cursor_col.load(std::memory_order_relaxed), 0, safe_cols - 1),
            std::memory_order_relaxed);
        ctx->pub.cursor_row.store(
            clamp_i32(ctx->pub.cursor_row.load(std::memory_order_relaxed), 0, safe_rows - 1),
            std::memory_order_relaxed);
        if (ctx->pub.total_lines.load(std::memory_order_relaxed) < safe_rows) {
            ctx->pub.total_lines.store(safe_rows, std::memory_order_relaxed);
        }
        commit_viewport_locked(ctx);
    }
#if defined(__APPLE__) || defined(__linux__)
    const int fd = ctx->pub.pty_fd.load(std::memory_order_acquire);
    if (fd >= 0) {
        struct winsize ws {};
        ws.ws_col = static_cast<unsigned short>(safe_cols);
        ws.ws_row = static_cast<unsigned short>(safe_rows);
        ::ioctl(fd, TIOCSWINSZ, &ws);
    }
#endif
}

void zero_terminal_set_scroll_offset(ZeroTerminalState* state, int32_t offset) {
    auto* ctx = as_context(state);
    if (!ctx) return;
    std::lock_guard<std::mutex> lock(ctx->mutex);
    ctx->pub.scroll_offset.store(std::max(0, offset), std::memory_order_relaxed);
    commit_viewport_locked(ctx);
}

void zero_terminal_scroll_by(ZeroTerminalState* state, int32_t delta_lines) {
    auto* ctx = as_context(state);
    if (!ctx) return;
    std::lock_guard<std::mutex> lock(ctx->mutex);
    const int32_t cur = ctx->pub.scroll_offset.load(std::memory_order_relaxed);
    ctx->pub.scroll_offset.store(std::max(0, cur + delta_lines), std::memory_order_relaxed);
    commit_viewport_locked(ctx);
}

void zero_terminal_set_cursor_style(ZeroTerminalState* state, int32_t style, int32_t visible) {
    auto* ctx = as_context(state);
    if (!ctx) return;
    ctx->pub.cursor_style.store(clamp_i32(style, 0, 2), std::memory_order_relaxed);
    ctx->pub.cursor_visible.store(visible != 0 ? 1 : 0, std::memory_order_relaxed);
    mark_row_dirty(&ctx->pub, ctx->pub.cursor_row.load(std::memory_order_relaxed));
}

void zero_terminal_clear_dirty_mask(ZeroTerminalState* state) {
    if (!is_registered_alive(state)) return;
    state->dirty_row_mask_lo.store(0ULL, std::memory_order_relaxed);
    state->dirty_row_mask_hi.store(0ULL, std::memory_order_relaxed);
}

int32_t zero_terminal_feed_bytes(
    ZeroTerminalState* state,
    const uint8_t* bytes,
    int32_t length
) {
    auto* ctx = as_context(state);
    if (!ctx || !bytes || length <= 0) return 0;
    std::lock_guard<std::mutex> lock(ctx->mutex);
    if (ctx->pub.status.load(std::memory_order_relaxed) == ZERO_TERM_STATUS_IDLE) {
        ctx->pub.status.store(ZERO_TERM_STATUS_STREAM_ONLY, std::memory_order_relaxed);
    }
    parse_chunk_locked(ctx, bytes, length);
    return length;
}

#if defined(__APPLE__) || defined(__linux__)
void exec_child_shell(const char* shell_path, const char* working_dir) {
    if (working_dir && working_dir[0] != '\0') {
        ::chdir(working_dir);
    }
    ::setenv("TERM", "xterm-256color", 1);
    ::setenv("COLORTERM", "truecolor", 1);
    ::setenv("LANG", "en_US.UTF-8", 1);
    const char* sh = (shell_path && shell_path[0] != '\0') ? shell_path : "/bin/zsh";
    char* const argv[] = {const_cast<char*>(sh), const_cast<char*>("-i"), nullptr};
    ::execvp(sh, argv);
    char* const fallback_argv[] = {const_cast<char*>("/bin/sh"), nullptr};
    ::execvp("/bin/sh", fallback_argv);
    ::_exit(127);
}
#endif

int32_t zero_terminal_spawn_pty(
    ZeroTerminalState* state,
    const char* shell_path,
    const char* working_dir
) {
    auto* ctx = as_context(state);
    if (!ctx) return -1;
    stop_pty_internal(ctx);

#if defined(__APPLE__) || defined(__linux__)
    struct winsize ws {};
    ws.ws_col = static_cast<unsigned short>(ctx->pub.cols.load(std::memory_order_relaxed));
    ws.ws_row = static_cast<unsigned short>(ctx->pub.rows.load(std::memory_order_relaxed));

    int master_fd = -1;
    const pid_t pid = ::forkpty(&master_fd, nullptr, nullptr, &ws);
    if (pid < 0) {
        ctx->pub.status.store(ZERO_TERM_STATUS_ERROR, std::memory_order_release);
        return -1;
    }
    if (pid == 0) {
        exec_child_shell(shell_path, working_dir);
    }
    const int flags = ::fcntl(master_fd, F_GETFL, 0);
    ::fcntl(master_fd, F_SETFL, flags | O_NONBLOCK);
    ctx->pty_stop_flag.store(false, std::memory_order_release);
    ctx->pub.pty_fd.store(master_fd, std::memory_order_release);
    ctx->pub.child_pid.store(static_cast<int32_t>(pid), std::memory_order_release);
    ctx->pub.status.store(ZERO_TERM_STATUS_PTY_RUNNING, std::memory_order_release);
    ctx->pty_thread = std::thread(pty_reader_loop, ctx, master_fd, pid);
    return static_cast<int32_t>(pid);
#else
    (void)shell_path;
    (void)working_dir;
    ctx->pub.status.store(ZERO_TERM_STATUS_STREAM_ONLY, std::memory_order_release);
    return 0;
#endif
}

int32_t zero_terminal_write_input(
    ZeroTerminalState* state,
    const uint8_t* bytes,
    int32_t length
) {
    auto* ctx = as_context(state);
    if (!ctx || !bytes || length <= 0) return 0;
#if defined(__APPLE__) || defined(__linux__)
    const int fd = ctx->pub.pty_fd.load(std::memory_order_acquire);
    if (fd >= 0) {
        const ssize_t written = ::write(fd, bytes, static_cast<size_t>(length));
        return written > 0 ? static_cast<int32_t>(written) : 0;
    }
#endif
    std::lock_guard<std::mutex> lock(ctx->mutex);
    parse_chunk_locked(ctx, bytes, length);
    return length;
}

int32_t zero_terminal_send_key_code(
    ZeroTerminalState* state,
    int32_t key_code,
    int32_t modifiers
) {
    (void)modifiers;
    if (key_code <= 0 || key_code > 16) return 0;
    const KeySeqEntry entry = kKeyTable[key_code];
    return zero_terminal_write_input(
        state,
        reinterpret_cast<const uint8_t*>(entry.seq),
        entry.len
    );
}

void zero_terminal_stop_pty(ZeroTerminalState* state) {
    auto* ctx = as_context(state);
    if (!ctx) return;
    stop_pty_internal(ctx);
    ctx->pub.status.store(ZERO_TERM_STATUS_EXITED, std::memory_order_release);
}

int32_t zero_terminal_generate_stress_burst(
    ZeroTerminalState* state,
    int32_t line_count,
    uint32_t seed
) {
    auto* ctx = as_context(state);
    if (!ctx || line_count <= 0) return 0;
    const int32_t clamped_lines = clamp_i32(line_count, 1, 4096);
    std::vector<uint8_t> burst;
    burst.reserve(static_cast<size_t>(clamped_lines) * 96u);

    char line_buf[160];
    uint32_t rng = seed == 0u ? 0x9E3779B9u : seed;
    for (int32_t i = 0; i < clamped_lines; ++i) {
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        const int r = static_cast<int>(80u + (rng & 0xAFu));
        const int g = static_cast<int>(90u + ((rng >> 8) & 0x9Fu));
        const int b = static_cast<int>(120u + ((rng >> 16) & 0x7Fu));
        const int n = std::snprintf(
            line_buf,
            sizeof(line_buf),
            "\x1b[38;2;%d;%d;%dm[D-ZERO::PTY] seq=%06u hash=0x%08X \x1b[1;32mOK\x1b[0m latency=0.0ns\r\n",
            r, g, b, static_cast<unsigned>(i), rng
        );
        if (n > 0) {
            burst.insert(burst.end(), line_buf, line_buf + n);
        }
    }
    return zero_terminal_feed_bytes(state, burst.data(), static_cast<int32_t>(burst.size()));
}

const uint32_t* zero_terminal_get_viewport_codepoints(const ZeroTerminalState* state) {
    const auto* ctx = as_const_context(state);
    return ctx ? ctx->viewport_codepoints : nullptr;
}

const uint32_t* zero_terminal_get_viewport_fg_argb(const ZeroTerminalState* state) {
    const auto* ctx = as_const_context(state);
    return ctx ? ctx->viewport_fg_argb : nullptr;
}

const uint32_t* zero_terminal_get_viewport_bg_argb(const ZeroTerminalState* state) {
    const auto* ctx = as_const_context(state);
    return ctx ? ctx->viewport_bg_argb : nullptr;
}

const uint8_t* zero_terminal_get_viewport_attrs(const ZeroTerminalState* state) {
    const auto* ctx = as_const_context(state);
    return ctx ? ctx->viewport_attrs : nullptr;
}

const uint32_t* zero_terminal_get_minimap_colors(const ZeroTerminalState* state) {
    const auto* ctx = as_const_context(state);
    return ctx ? ctx->minimap_colors : nullptr;
}

const uint8_t* zero_terminal_get_minimap_fill(const ZeroTerminalState* state) {
    const auto* ctx = as_const_context(state);
    return ctx ? ctx->minimap_fill : nullptr;
}

} // extern "C"

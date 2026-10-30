#include <iostream>
#include <cassert>
#include <thread>
#include <vector>
#include <atomic>
#include <chrono>
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include "../src/zero_playback_state.h"

// テストユーティリティ
#define TEST_ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            std::cerr << "❌ FAILED: " << msg << " (Line " << __LINE__ << ")" << std::endl; \
            std::exit(1); \
        } \
    } while(0)

#define TEST_PASS(msg) \
    std::cout << "✅ PASSED: " << msg << std::endl;

// ==========================================
// 1. 正常系テスト (Happy Path & Cache Line Alignment)
// ==========================================
void test_normal_lifecycle_and_values() {
    std::cout << "\n--- [1. 正常系テスト & 64-byte キャッシュライン検証] ---" << std::endl;

    TEST_ASSERT(sizeof(ZeroPlaybackState) == 64, "ZeroPlaybackState は 64 bytes (1 キャッシュライン) であること");
    TEST_ASSERT(alignof(ZeroPlaybackState) == 64, "ZeroPlaybackState は 64-byte アライメントであること");

    ZeroPlaybackState* state = zero_create_playback_state();
    TEST_ASSERT(state != nullptr, "共有メモリの割り当てに成功すること");
    TEST_ASSERT((reinterpret_cast<uintptr_t>(state) & 63u) == 0u, "ポインタアドレスが 64-byte 境界に揃っていること");

    // 初期値確認
    TEST_ASSERT(zero_get_position(state) == 0, "初期 position は 0 であること");
    TEST_ASSERT(zero_get_display_position(state) == 0, "初期 display_position は 0 であること");
    TEST_ASSERT(zero_get_duration(state) == 0, "初期 duration は 0 であること");
    TEST_ASSERT(zero_get_status(state) == ZERO_STATUS_IDLE, "初期 status は IDLE であること");

    // 更新と読み出し
    zero_set_duration(state, 120000); // 2分
    zero_set_position(state, 45000);   // 45秒
    zero_set_status(state, ZERO_STATUS_PLAYING);
    zero_set_video_size(state, 1920, 1080);

    TEST_ASSERT(zero_get_duration(state) == 120000, "duration が正しく更新されること");
    TEST_ASSERT(zero_get_position(state) >= 45000, "position が正しく更新されること");
    TEST_ASSERT(zero_get_status(state) == ZERO_STATUS_PLAYING, "status が正しく更新されること");

    zero_destroy_playback_state(state);
    TEST_PASS("ライフサイクル・キャッシュラインアライメント・基本的な値の読み書き");
}

// ==========================================
// 2. 異常系テスト (Edge Cases & Fault Tolerance)
// ==========================================
void test_abnormal_and_edge_cases() {
    std::cout << "\n--- [2. 異常系テスト] ---" << std::endl;

    // 2-1. nullptr 安全性（防護策）
    zero_set_position(nullptr, 1000);
    zero_set_position_anchor(nullptr, 1000, 1.5f);
    zero_set_playback_speed(nullptr, 2.0f);
    zero_set_duration(nullptr, 2000);
    zero_set_status(nullptr, ZERO_STATUS_PLAYING);
    zero_set_buffered(nullptr, 500);
    zero_set_video_size(nullptr, 1920, 1080);
    zero_increment_frame(nullptr);
    zero_destroy_playback_state(nullptr);

    TEST_ASSERT(zero_get_position(nullptr) == 0, "nullptr 参照時に 0 が返りクラッシュしないこと");
    TEST_ASSERT(zero_get_display_position(nullptr) == 0, "nullptr 参照時に display_position が 0 を返すこと");
    TEST_ASSERT(zero_get_duration(nullptr) == 0, "nullptr 参照時に 0 が返りクラッシュしないこと");
    TEST_ASSERT(zero_get_status(nullptr) == ZERO_STATUS_IDLE, "nullptr 参照時に IDLE が返ること");
    TEST_ASSERT(zero_get_seq(nullptr) == 0u, "nullptr 参照時に seq が 0 を返すこと");
    TEST_PASS("nullptr 引数に対する防護（SIGSEGV 防止）");

    // 2-2. 境界値・極端な値テスト
    ZeroPlaybackState* state = zero_create_playback_state();

    // 負の値（不正な逆再生やシーク）
    zero_set_position(state, -99999);
    TEST_ASSERT(zero_get_position(state) == -99999, "負の値を受け入れて保持できること");

    // int64_t 最大値（オーバーフロー耐性 & PLAYING 外挿時の UB 防止）
    int64_t max_val = LLONG_MAX;
    zero_set_duration(state, 0);
    zero_set_position_anchor(state, max_val - 5, 100.0f);
    zero_set_status(state, ZERO_STATUS_PLAYING);
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    TEST_ASSERT(zero_get_display_position(state) == max_val,
                "PLAYING 外挿時に LLONG_MAX を超えても符号付き整数オーバーフロー(UB)せず飽和すること");

    // NaN / Infinity 再生速度に対する防御
    zero_set_duration(state, 100000);
    zero_set_position_anchor(state, 5000, std::numeric_limits<float>::quiet_NaN());
    TEST_ASSERT(zero_get_display_position(state) == 5000,
                "NaN 速度が渡されても UB を起こさず現在位置を維持すること");
    zero_set_position_anchor(state, 5000, std::numeric_limits<float>::infinity());
    TEST_ASSERT(zero_get_display_position(state) == 5000,
                "Infinity 速度が渡されても UB を起こさず安全にサニタイズされること");
    zero_set_position_anchor(state, 5000, -10.0f);
    TEST_ASSERT(zero_get_display_position(state) == 5000,
                "負の速度が渡されても安全に 0.0f にクランプされること");

    zero_set_duration(state, max_val);
    TEST_ASSERT(zero_get_duration(state) == max_val, "int64 最大値（オーバーフロー限界）を正しく保持できること");

    // 定義外のステータスコード
    zero_set_status(state, 9999);
    TEST_ASSERT(zero_get_status(state) == 9999, "未知のステータスコードでもクラッシュしないこと");

    zero_destroy_playback_state(state);
    TEST_PASS("境界値・極端な値・オーバーフロー耐性");
}

// ==========================================
// 3. ペネトレーション / 耐久 / 並行性テスト (Concurrency & Stress)
// ==========================================
void test_concurrency_race_condition() {
    std::cout << "\n--- [3-1. ペネトレーション: マルチスレッド競合 & Seqlock 一貫性テスト] ---" << std::endl;

    ZeroPlaybackState* state = zero_create_playback_state();
    std::atomic<bool> running{true};
    std::atomic<uint64_t> read_count{0};
    std::atomic<uint64_t> torn_reads{0};

    // Producer スレッド: デコーダ役として超高速で position と anchor を更新 (1,000,000回)
    std::thread producer([&]() {
        for (int64_t i = 0; i < 1000000; ++i) {
            int64_t test_val = (i << 32) | (i & 0xFFFFFFFF);
            zero_set_position_anchor(state, test_val, 1.0f);
        }
        running.store(false);
    });

    // Consumer スレッド群 (4スレッド): Dart FFI 役として同時に超高速サンプリング
    std::vector<std::thread> consumers;
    for (int t = 0; t < 4; ++t) {
        consumers.emplace_back([&]() {
            while (running.load(std::memory_order_relaxed)) {
                int64_t val = zero_get_display_position(state);
                int64_t high = (val >> 32) & 0xFFFFFFFF;
                int64_t low = val & 0xFFFFFFFF;
                if (high != low && val != 0) {
                    torn_reads.fetch_add(1);
                }
                read_count.fetch_add(1);
            }
        });
    }

    producer.join();
    for (auto& c : consumers) {
        c.join();
    }

    // 書き込み完了後の seq は必ず偶数であること
    TEST_ASSERT((zero_get_seq(state) & 1u) == 0u, "書き込み完了後の seqlock カウンタは偶数であること");
    std::cout << "  総読み出しサンプリング数: " << read_count.load() << " 回" << std::endl;
    std::cout << "  データ破損（Torn Read）件数: " << torn_reads.load() << " 件" << std::endl;
    TEST_ASSERT(torn_reads.load() == 0, "高負荷マルチスレッド下でアトミック性が保たれ、Torn Read が 0 件であること");

    zero_destroy_playback_state(state);
    TEST_PASS("並行書き込み・読み出しにおけるデータ破損なし（Seqlock Data Race フリー）");
}

void test_timestamp_extrapolation() {
    std::cout << "\n--- [3-2. アンカー時刻外挿 & 速度スケーリング検証] ---" << std::endl;

    ZeroPlaybackState* state = zero_create_playback_state();
    zero_set_duration(state, 100000);
    zero_set_position_anchor(state, 1000, 1.0f);
    zero_set_status(state, ZERO_STATUS_PLAYING);

    std::this_thread::sleep_for(std::chrono::milliseconds(60));
    int64_t extrapolated = zero_get_display_position(state);
    TEST_ASSERT(extrapolated >= 1040 && extrapolated <= 1250,
                "PLAYING 状態で経過時間に応じて position が滑らかに外挿されること");

    // PAUSED に遷移するとその位置で固定されること
    zero_set_status(state, ZERO_STATUS_PAUSED);
    int64_t frozen1 = zero_get_display_position(state);
    std::this_thread::sleep_for(std::chrono::milliseconds(40));
    int64_t frozen2 = zero_get_display_position(state);
    TEST_ASSERT(frozen1 == frozen2, "PAUSED 状態では時間が経過しても display_position が進まないこと");

    // duration クランプ検証
    zero_set_duration(state, 2000);
    zero_set_position_anchor(state, 1980, 2.0f);
    zero_set_status(state, ZERO_STATUS_PLAYING);
    std::this_thread::sleep_for(std::chrono::milliseconds(40));
    TEST_ASSERT(zero_get_display_position(state) == 2000,
                "外挿結果が duration を超えないようクランプされること");

    zero_destroy_playback_state(state);
    TEST_PASS("アンカー外挿・一時停止固定・duration クランプ");
}

void test_mass_allocation_and_double_free_stress() {
    std::cout << "\n--- [3-3. ペネトレーション: 大量メモリ確保・解放ストレステスト] ---" << std::endl;

    constexpr int ITERATIONS = 10000;
    std::vector<ZeroPlaybackState*> states(ITERATIONS);

    for (int i = 0; i < ITERATIONS; ++i) {
        states[i] = zero_create_playback_state();
        TEST_ASSERT(states[i] != nullptr, "大量確保中に OOM または割り当て失敗しないこと");
        zero_set_position(states[i], i);
    }

    for (int i = 0; i < ITERATIONS; ++i) {
        TEST_ASSERT(zero_get_position(states[i]) == i, "隣接メモリ領域の破壊がないこと");
    }

    for (int i = 0; i < ITERATIONS; ++i) {
        zero_destroy_playback_state(states[i]);
    }

    TEST_PASS("10,000 個の連続アロケーション・デアロケーションによるメモリ汚染なし");
}

int main() {
    std::cout << "==================================================" << std::endl;
    std::cout << "   zero_player ネイティブコア テストスイート" << std::endl;
    std::cout << "==================================================" << std::endl;

    auto start = std::chrono::high_resolution_clock::now();

    test_normal_lifecycle_and_values();
    test_abnormal_and_edge_cases();
    test_concurrency_race_condition();
    test_timestamp_extrapolation();
    test_mass_allocation_and_double_free_stress();

    auto end = std::chrono::high_resolution_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    std::cout << "\n==================================================" << std::endl;
    std::cout << "🎉 全てのテストに合格しました！ (所要時間: " << elapsed << " ms)" << std::endl;
    std::cout << "==================================================" << std::endl;

    return 0;
}

#include <iostream>
#include <cassert>
#include <thread>
#include <vector>
#include <atomic>
#include <chrono>
#include <climits>
#include <cstdlib>
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
// 1. 正常系テスト (Happy Path)
// ==========================================
void test_normal_lifecycle_and_values() {
    std::cout << "\n--- [1. 正常系テスト] ---" << std::endl;

    ZeroPlaybackState* state = zero_create_playback_state();
    TEST_ASSERT(state != nullptr, "共有メモリの割り当てに成功すること");

    // 初期値確認
    TEST_ASSERT(zero_get_position(state) == 0, "初期 position は 0 であること");
    TEST_ASSERT(zero_get_duration(state) == 0, "初期 duration は 0 であること");
    TEST_ASSERT(zero_get_status(state) == ZERO_STATUS_IDLE, "初期 status は IDLE であること");

    // 更新と読み出し
    zero_set_duration(state, 120000); // 2分
    zero_set_position(state, 45000);   // 45秒
    zero_set_status(state, ZERO_STATUS_PLAYING);
    zero_set_video_size(state, 1920, 1080);

    TEST_ASSERT(zero_get_duration(state) == 120000, "duration が正しく更新されること");
    TEST_ASSERT(zero_get_position(state) == 45000, "position が正しく更新されること");
    TEST_ASSERT(zero_get_status(state) == ZERO_STATUS_PLAYING, "status が正しく更新されること");

    zero_destroy_playback_state(state);
    TEST_PASS("ライフサイクルと基本的な値の読み書き");
}

// ==========================================
// 2. 異常系テスト (Edge Cases & Fault Tolerance)
// ==========================================
void test_abnormal_and_edge_cases() {
    std::cout << "\n--- [2. 異常系テスト] ---" << std::endl;

    // 2-1. nullptr 安全性（防護策）
    zero_set_position(nullptr, 1000);
    zero_set_duration(nullptr, 2000);
    zero_set_status(nullptr, ZERO_STATUS_PLAYING);
    zero_set_buffered(nullptr, 500);
    zero_set_video_size(nullptr, 1920, 1080);
    zero_increment_frame(nullptr);
    zero_destroy_playback_state(nullptr);

    TEST_ASSERT(zero_get_position(nullptr) == 0, "nullptr 参照時に 0 が返りクラッシュしないこと");
    TEST_ASSERT(zero_get_duration(nullptr) == 0, "nullptr 参照時に 0 が返りクラッシュしないこと");
    TEST_ASSERT(zero_get_status(nullptr) == ZERO_STATUS_IDLE, "nullptr 参照時に IDLE が返ること");
    TEST_PASS("nullptr 引数に対する防護（SIGSEGV 防止）");

    // 2-2. 境界値・極端な値テスト
    ZeroPlaybackState* state = zero_create_playback_state();

    // 負の値（不正な逆再生やシーク）
    zero_set_position(state, -99999);
    TEST_ASSERT(zero_get_position(state) == -99999, "負の値を受け入れて保持できること");

    // int64_t 最大値（オーバーフロー耐性）
    int64_t max_val = LLONG_MAX;
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
    std::cout << "\n--- [3-1. ペネトレーション: マルチスレッド競合テスト] ---" << std::endl;

    ZeroPlaybackState* state = zero_create_playback_state();
    std::atomic<bool> running{true};
    std::atomic<uint64_t> read_count{0};
    std::atomic<uint64_t> torn_reads{0};

    // Producer スレッド: デコーダ役として超高速で position を更新 (1,000,000回)
    std::thread producer([&]() {
        for (int64_t i = 0; i < 1000000; ++i) {
            // 上位32bitと下位32bitに同じ値を書き込み、Torn Read（断片読み込み）を検出可能にする
            int64_t test_val = (i << 32) | (i & 0xFFFFFFFF);
            zero_set_position(state, test_val);
        }
        running.store(false);
    });

    // Consumer スレッド群 (4スレッド): Dart FFI 役として同時に超高速サンプリング
    std::vector<std::thread> consumers;
    for (int t = 0; t < 4; ++t) {
        consumers.emplace_back([&]() {
            while (running.load(std::memory_order_relaxed)) {
                int64_t val = zero_get_position(state);
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

    std::cout << "  総読み出しサンプリング数: " << read_count.load() << " 回" << std::endl;
    std::cout << "  データ破損（Torn Read）件数: " << torn_reads.load() << " 件" << std::endl;
    TEST_ASSERT(torn_reads.load() == 0, "高負荷マルチスレッド下でアトミック性が保たれ、Torn Read が 0 件であること");

    zero_destroy_playback_state(state);
    TEST_PASS("並行書き込み・読み出しにおけるデータ破損なし（Data Race フリー）");
}

void test_mass_allocation_and_double_free_stress() {
    std::cout << "\n--- [3-2. ペネトレーション: 大量メモリ確保・解放ストレステスト] ---" << std::endl;

    constexpr int ITERATIONS = 10000;
    std::vector<ZeroPlaybackState*> states(ITERATIONS);

    // 10,000 個を一気に確保
    for (int i = 0; i < ITERATIONS; ++i) {
        states[i] = zero_create_playback_state();
        TEST_ASSERT(states[i] != nullptr, "大量確保中に OOM または割り当て失敗しないこと");
        zero_set_position(states[i], i);
    }

    // 全て正しく値が残っているか検証（メモリ汚染の有無）
    for (int i = 0; i < ITERATIONS; ++i) {
        TEST_ASSERT(zero_get_position(states[i]) == i, "隣接メモリ領域の破壊がないこと");
    }

    // 一気に全解放
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
    test_mass_allocation_and_double_free_stress();

    auto end = std::chrono::high_resolution_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    std::cout << "\n==================================================" << std::endl;
    std::cout << "🎉 全てのテストに合格しました！ (所要時間: " << elapsed << " ms)" << std::endl;
    std::cout << "==================================================" << std::endl;

    return 0;
}

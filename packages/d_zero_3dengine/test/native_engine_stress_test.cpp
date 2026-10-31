#include <iostream>
#include <cassert>
#include <thread>
#include <vector>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include "../src/zero_3d_engine_state.h"

#define TEST_ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            std::cerr << "❌ FAILED: " << msg << " (Line " << __LINE__ << ")" << std::endl; \
            std::exit(1); \
        } \
    } while(0)

#define TEST_PASS(msg) \
    std::cout << "✅ PASSED: " << msg << std::endl;

// =========================================================================
// 1. 正常系 & 128-byte (2 キャッシュライン) アライメント検証
// =========================================================================
void test_normal_lifecycle_and_cache_lines() {
    std::cout << "\n--- [1. 128-byte (2 Cache Lines) アライメント & ライフサイクル検証] ---" << std::endl;

    TEST_ASSERT(sizeof(Zero3DEngineState) == 128, "Zero3DEngineState は厳密に 128 bytes (2 キャッシュライン) であること");
    TEST_ASSERT(alignof(Zero3DEngineState) == 64, "Zero3DEngineState は 64-byte アライメントであること");

    Zero3DEngineState* state = zero_3d_create_state();
    TEST_ASSERT(state != nullptr, "共有メモリ確保に成功すること");
    TEST_ASSERT((reinterpret_cast<uintptr_t>(state) & 63u) == 0u, "ポインタアドレスが 64-byte 境界に整列していること");
    TEST_ASSERT(zero_3d_is_state_valid(state), "magic_guard カナリア値が ALIVE であること");

    // 初期状態の確認
    TEST_ASSERT(zero_3d_get_frame_count(state) == 0u, "初期 frame_count は 0 であること");
    TEST_ASSERT(std::abs(zero_3d_get_render_fps(state) - 120.0f) < 0.01f, "初期 FPS は 120.0f であること");

    // 144Hz モニター + Hybrid Nanite + RayTracing の設定とシミュレーション
    zero_3d_set_pipeline_config(state, ZERO_3D_MODE_HYBRID_NANITE_RT, ZERO_3D_FPS_CAP_144, 144, 1.0f, 3);
    zero_3d_set_camera_orbit(state, 1.2f, 0.4f, 2.5f, 70.0f);
    zero_3d_simulate_frame_step(state, 4096, 6.94f);

    TEST_ASSERT(zero_3d_get_frame_count(state) == 1u, "frame_count が 1 にインクリメントされること");
    TEST_ASSERT(std::abs(zero_3d_get_display_hz(state) - 144.0f) < 0.1f, "144Hz ターゲットが反映されること");
    TEST_ASSERT(zero_3d_get_active_clusters(state) > 0, "Nanite アクティブクラスタが算出されること");
    TEST_ASSERT(zero_3d_get_visible_triangles(state) == zero_3d_get_active_clusters(state) * 128,
                "1 Meshlet = 128 三角形として正確に計算されること");
    TEST_ASSERT(zero_3d_get_rays_traced_k(state) > 0, "レイトレーシング発射レイ数が記録されること");

    zero_3d_destroy_state(state);
    TEST_PASS("128-byte キャッシュライン分離・144Hz/Nanite/RayTracing 状態更新");
}

// =========================================================================
// 2. 異常系・nullptr・未整列ポインタ・NaN/Infinity・Double-Free 防御
// =========================================================================
void test_memory_safety_and_edge_cases() {
    std::cout << "\n--- [2. メモリ安全性 (nullptr / Misaligned / NaN / Double-Free) 検証] ---" << std::endl;

    // 2-1. nullptr 防御
    zero_3d_set_camera_orbit(nullptr, 1.0f, 0.5f, 3.0f, 60.0f);
    zero_3d_set_camera_target(nullptr, 1.0f, 2.0f, 3.0f);
    zero_3d_set_light_angles(nullptr, 0.5f, 0.5f);
    zero_3d_set_pipeline_config(nullptr, 0, 0, 144, 1.0f, 2);
    zero_3d_set_status(nullptr, ZERO_3D_STATUS_RENDERING);
    zero_3d_simulate_frame_step(nullptr, 1024, 6.94f);
    zero_3d_destroy_state(nullptr);

    TEST_ASSERT(!zero_3d_is_state_valid(nullptr), "nullptr は無効と判定されること");
    TEST_ASSERT(zero_3d_get_render_fps(nullptr) == 0.0f, "nullptr 参照時に 0.0f を返すこと");
    TEST_ASSERT(zero_3d_get_active_clusters(nullptr) == 0, "nullptr 参照時に 0 を返すこと");

    // 2-2. 未整列不正アドレス (0xDEADBEEF 等) の拒絶
    auto* misaligned = reinterpret_cast<Zero3DEngineState*>(static_cast<uintptr_t>(0xDEADBEEFull));
    TEST_ASSERT(!zero_3d_is_state_valid(misaligned), "未整列アドレスをデリファレンスせず即座に拒絶すること");
    zero_3d_destroy_state(misaligned); // クラッシュしないこと

    // 2-3. NaN / Infinity / 異常境界値のサニタイズ (UB 防止)
    Zero3DEngineState* state = zero_3d_create_state();
    const float nan_v = std::numeric_limits<float>::quiet_NaN();
    const float inf_v = std::numeric_limits<float>::infinity();

    zero_3d_set_camera_orbit(state, nan_v, inf_v, -999.0f, 9999.0f);
    zero_3d_set_pipeline_config(state, 999, -50, -100, nan_v, 999);
    zero_3d_record_frame_telemetry(state, nan_v, inf_v, -10.0f, -100, 999999, -50, -10, -1, -99);

    TEST_ASSERT(std::isfinite(zero_3d_get_render_fps(state)), "NaN FPS が有限値 0.0f にサニタイズされること");
    TEST_ASSERT(std::isfinite(zero_3d_get_frame_time_ms(state)), "Inf frame_time が有限値にサニタイズされること");
    TEST_ASSERT(zero_3d_get_display_hz(state) >= 24.0f, "負のリフレッシュレートが安全下限にクランプされること");
    TEST_ASSERT(zero_3d_get_active_clusters(state) == 0, "負のクラスタ数が 0 にクランプされること");

    // 2-4. スタック上の擬似領域を用いた確定的な Double-Free / Use-After-Free カナリア検証
    alignas(64) Zero3DEngineState stack_state{};
    stack_state.magic_guard.store(ZERO_3D_MAGIC_FREED, std::memory_order_release);
    TEST_ASSERT(!zero_3d_is_state_valid(&stack_state), "FREED カナリアを持つ領域は invalid と判定されること");
    zero_3d_set_camera_orbit(&stack_state, 1.0f, 1.0f, 5.0f, 60.0f);
    TEST_ASSERT(zero_3d_get_render_fps(&stack_state) == 0.0f, "FREED 領域からの読み出しは安全に 0 を返すこと");

    zero_3d_destroy_state(state);
    TEST_PASS("nullptr / 未整列ポインタ / NaN・Inf サニタイズ / Magic Canary 防御");
}

// =========================================================================
// 3. マルチスレッド Seqlock 競合ストレステスト (TSan / ASan 検証用)
// =========================================================================
void test_concurrency_seqlock_stress() {
    std::cout << "\n--- [3. マルチスレッド Seqlock 競合 & 144Hz/Uncapped ストレステスト] ---" << std::endl;

    Zero3DEngineState* state = zero_3d_create_state();
    std::atomic<bool> running{true};
    std::atomic<uint64_t> total_reads{0};
    std::atomic<uint64_t> invalid_reads{0};

    // スレッド 1: Dart UI / Input スレッド役 (カメラ・設定を超高速更新)
    std::thread dart_writer([&]() {
        for (int i = 0; i < 250000; ++i) {
            float angle = static_cast<float>(i) * 0.001f;
            zero_3d_set_camera_orbit(state, angle, 0.3f, 3.5f, 60.0f);
            zero_3d_set_pipeline_config(state, i & 3, i % 5, 240, 1.0f, 2);
        }
    });

    // スレッド 2: Native Render Thread 役 (Uncapped 1000+ FPS 相当でテレメトリ書き込み)
    std::thread render_writer([&]() {
        for (int i = 1; i <= 250000; ++i) {
            // active_clusters と visible_triangles (= active * 128) の整合性を検証
            int32_t clusters = (i % 4096) + 1;
            int32_t tris = clusters * 128;
            zero_3d_record_frame_telemetry(
                state, 240.0f, 4.16f, 240.0f, 2560, 1440, clusters, tris, 1024, 512
            );
        }
        running.store(false, std::memory_order_release);
    });

    // スレッド 3..6: 4つの並列 Reader スレッド (HUD 描画サンプリング)
    std::vector<std::thread> readers;
    for (int t = 0; t < 4; ++t) {
        readers.emplace_back([&]() {
            while (running.load(std::memory_order_acquire)) {
                float fps = zero_3d_get_render_fps(state);
                int32_t tris = zero_3d_get_visible_triangles(state);
                if (!std::isfinite(fps) || fps < 0.0f || (tris % 128) != 0) {
                    invalid_reads.fetch_add(1, std::memory_order_relaxed);
                }
                total_reads.fetch_add(1, std::memory_order_relaxed);
            }
        });
    }

    dart_writer.join();
    render_writer.join();
    for (auto& r : readers) {
        r.join();
    }

    TEST_ASSERT((zero_3d_get_cmd_seq(state) & 1u) == 0u, "完了後の cmd_seq は偶数であること");
    TEST_ASSERT((zero_3d_get_telemetry_seq(state) & 1u) == 0u, "完了後の telemetry_seq は偶数であること");
    std::cout << "  総並列読み出し数: " << total_reads.load() << " 回, 不整合件数: " << invalid_reads.load() << std::endl;
    TEST_ASSERT(invalid_reads.load() == 0u, "Torn Read / データ不整合が 0 件であること");

    zero_3d_destroy_state(state);
    TEST_PASS("250,000 フレーム並列書き込み + 4 Reader スレッドで Data Race & Torn Read ゼロ");
}

// =========================================================================
// 4. 10,000 回連続確保・解放ストレステスト (Memory Leak ゼロ検証)
// =========================================================================
void test_mass_allocation_deallocation() {
    std::cout << "\n--- [4. 10,000 回連続アロケーション & 解放ストレステスト] ---" << std::endl;

    constexpr int kCount = 10000;
    std::vector<Zero3DEngineState*> ptrs(kCount);

    for (int i = 0; i < kCount; ++i) {
        ptrs[i] = zero_3d_create_state();
        TEST_ASSERT(ptrs[i] != nullptr, "OOM なく 128-byte アライメント確保できること");
        zero_3d_simulate_frame_step(ptrs[i], 2048, 4.16f);
    }

    for (int i = 0; i < kCount; ++i) {
        TEST_ASSERT(zero_3d_get_frame_count(ptrs[i]) == 1u, "隣接メモリの汚染がないこと");
        zero_3d_destroy_state(ptrs[i]);
    }

    TEST_PASS("10,000 個の連続確保・解放でヒープ破損・メモリリークなし");
}

int main() {
    std::cout << "==========================================================" << std::endl;
    std::cout << "   d_zero_3dengine Native C++ メモリ安全性・競合テスト" << std::endl;
    std::cout << "==========================================================" << std::endl;

    auto t0 = std::chrono::high_resolution_clock::now();

    test_normal_lifecycle_and_cache_lines();
    test_memory_safety_and_edge_cases();
    test_concurrency_seqlock_stress();
    test_mass_allocation_deallocation();

    auto t1 = std::chrono::high_resolution_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();

    std::cout << "\n==========================================================" << std::endl;
    std::cout << "🎉 全 C++ メモリ安全性テスト合格！ (所要時間: " << ms << " ms)" << std::endl;
    std::cout << "==========================================================" << std::endl;
    return 0;
}

#include "include/d_zero_3dengine/zero_3d_engine_plugin_c_api.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <windows.h>
#include <atomic>
#include <chrono>
#include <cmath>
#include <map>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#include "../src/zero_3d_engine_state.h"

namespace {

// Windows モニターのネイティブリフレッシュレート (60Hz / 120Hz / 144Hz / 240Hz / 360Hz) を検出
float DetectWindowsMonitorRefreshHz() {
    DEVMODEW dev_mode = {};
    dev_mode.dmSize = sizeof(DEVMODEW);
    if (EnumDisplaySettingsW(nullptr, ENUM_CURRENT_SETTINGS, &dev_mode)) {
        if (dev_mode.dmDisplayFrequency >= 30 && dev_mode.dmDisplayFrequency <= 500) {
            return static_cast<float>(dev_mode.dmDisplayFrequency);
        }
    }
    return 144.0f;
}

class Zero3DWindowsInstance {
public:
    Zero3DWindowsInstance(
        flutter::TextureRegistrar* registrar,
        int32_t width,
        int32_t height
    ) : registrar_(registrar),
        width_(width > 64 ? width : 1280),
        height_(height > 64 ? height : 720) {
        state_ = zero_3d_create_state();
        ecs_world_ = zero_3d_ecs_create_world();
        for (int i = 0; i < 64; ++i) {
            float x = (static_cast<float>(i % 8) - 3.5f) * 1.2f;
            float z = (static_cast<float>(i / 8) - 3.5f) * 1.2f;
            zero_3d_ecs_spawn_entity(ecs_world_, x, 0.0f, z, 1.0f, 0.6f, 64);
        }
        zero_3d_set_status(state_, ZERO_3D_STATUS_RENDERING);

        for (int s = 0; s < 3; ++s) {
            buffers_[s].resize(static_cast<size_t>(width_) * static_cast<size_t>(height_) * 4, 255);
            pixel_buffers_[s].width = static_cast<size_t>(width_);
            pixel_buffers_[s].height = static_cast<size_t>(height_);
            pixel_buffers_[s].buffer = buffers_[s].data();
        }

        texture_variant_ = std::make_unique<flutter::TextureVariant>(
            flutter::PixelBufferTexture([this](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
                const int slot = ready_slot_.load(std::memory_order_acquire);
                return &pixel_buffers_[slot];
            })
        );
        texture_id_ = registrar_->RegisterTexture(texture_variant_.get());
        running_.store(true, std::memory_order_release);
        render_thread_ = std::thread([this]() { RenderLoop(); });
    }

    ~Zero3DWindowsInstance() {
        Dispose();
    }

    int64_t texture_id() const { return texture_id_; }
    Zero3DEngineState* state() const { return state_; }
    Zero3DEcsWorld* ecs_world() const { return ecs_world_; }

    void Dispose() {
        bool expected = true;
        if (!running_.compare_exchange_strong(expected, false)) return;
        if (render_thread_.joinable()) {
            render_thread_.join();
        }
        if (registrar_ && texture_id_ != -1) {
            registrar_->UnregisterTexture(texture_id_);
            texture_id_ = -1;
        }
        if (ecs_world_) {
            zero_3d_ecs_destroy_world(ecs_world_);
            ecs_world_ = nullptr;
        }
        if (state_) {
            zero_3d_destroy_state(state_);
            state_ = nullptr;
        }
    }

private:
    void RenderLoop() {
        auto last_time = std::chrono::steady_clock::now();
        while (running_.load(std::memory_order_acquire)) {
            auto now = std::chrono::steady_clock::now();
            float dt_ms = std::chrono::duration<float, std::milli>(now - last_time).count();
            last_time = now;
            if (dt_ms < 0.1f) dt_ms = 2.0f;

            const float hz = DetectWindowsMonitorRefreshHz();
            state_->display_refresh_hz.store(hz, std::memory_order_relaxed);
            zero_3d_ecs_step_transforms(ecs_world_, dt_ms * 0.001f);
            zero_3d_ecs_cull_and_update_state(ecs_world_, state_, dt_ms);

            const int next_slot = (ready_slot_.load(std::memory_order_relaxed) + 1) % 3;
            ready_slot_.store(next_slot, std::memory_order_release);
            registrar_->MarkTextureFrameAvailable(texture_id_);

            const int32_t fps_mode = state_->fps_mode.load(std::memory_order_relaxed);
            if (fps_mode == ZERO_3D_FPS_UNCAPPED) {
                std::this_thread::sleep_for(std::chrono::microseconds(1500));
            } else {
                const int sleep_us = static_cast<int>(1000000.0f / (hz > 60.0f ? hz : 144.0f));
                std::this_thread::sleep_for(std::chrono::microseconds(sleep_us));
            }
        }
    }

    flutter::TextureRegistrar* registrar_ = nullptr;
    Zero3DEngineState* state_ = nullptr;
    Zero3DEcsWorld* ecs_world_ = nullptr;
    std::unique_ptr<flutter::TextureVariant> texture_variant_;
    std::vector<uint8_t> buffers_[3];
    FlutterDesktopPixelBuffer pixel_buffers_[3] = {};
    std::atomic<int> ready_slot_{0};
    std::atomic<bool> running_{false};
    std::thread render_thread_;
    int64_t texture_id_ = -1;
    int32_t width_ = 1280;
    int32_t height_ = 720;
};

class Zero3DEnginePlugin : public flutter::Plugin {
public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
        auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "com.fexcy.d_zero_3dengine",
            &flutter::StandardMethodCodec::GetInstance());

        auto plugin = std::make_unique<Zero3DEnginePlugin>(registrar->texture_registrar());
        channel->SetMethodCallHandler(
            [plugin_pointer = plugin.get()](const auto& call, auto result) {
                plugin_pointer->HandleMethodCall(call, std::move(result));
            });
        registrar->AddPlugin(std::move(plugin));
    }

    explicit Zero3DEnginePlugin(flutter::TextureRegistrar* textures) : textures_(textures) {}
    ~Zero3DEnginePlugin() override {
        for (auto& kv : instances_) {
            kv.second->Dispose();
        }
        instances_.clear();
    }

private:
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result
    ) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() == "create") {
            int32_t w = 1280, h = 720;
            if (args) {
                auto it_w = args->find(flutter::EncodableValue("width"));
                auto it_h = args->find(flutter::EncodableValue("height"));
                if (it_w != args->end() && std::holds_alternative<int32_t>(it_w->second)) {
                    w = std::get<int32_t>(it_w->second);
                }
                if (it_h != args->end() && std::holds_alternative<int32_t>(it_h->second)) {
                    h = std::get<int32_t>(it_h->second);
                }
            }
            auto inst = std::make_unique<Zero3DWindowsInstance>(textures_, w, h);
            int64_t tex_id = inst->texture_id();
            int64_t addr = reinterpret_cast<int64_t>(inst->state());
            int64_t ecs_addr = reinterpret_cast<int64_t>(inst->ecs_world());
            instances_[tex_id] = std::move(inst);

            flutter::EncodableMap resp;
            resp[flutter::EncodableValue("textureId")] = flutter::EncodableValue(tex_id);
            resp[flutter::EncodableValue("stateAddress")] = flutter::EncodableValue(addr);
            resp[flutter::EncodableValue("ecsAddress")] = flutter::EncodableValue(ecs_addr);
            result->Success(flutter::EncodableValue(resp));
        } else if (call.method_name() == "dispose") {
            if (args) {
                auto it = args->find(flutter::EncodableValue("textureId"));
                if (it != args->end()) {
                    int64_t tex_id = it->second.LongValue();
                    auto found = instances_.find(tex_id);
                    if (found != instances_.end()) {
                        found->second->Dispose();
                        instances_.erase(found);
                    }
                }
            }
            result->Success();
        } else {
            result->Success();
        }
    }

    flutter::TextureRegistrar* textures_;
    std::map<int64_t, std::unique_ptr<Zero3DWindowsInstance>> instances_;
};

} // namespace

void Zero3DEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
    Zero3DEnginePlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

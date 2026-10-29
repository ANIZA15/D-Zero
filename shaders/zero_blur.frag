#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) out vec4 fragColor;

// 入力動画テクスチャ
layout(binding = 0) uniform sampler2D uVideoTexture;

// シェーダーパラメータ
layout(location = 0) uniform vec2 uResolution;
layout(location = 1) uniform float uBlurRadius;
layout(location = 2) uniform float uOpacity;

// シングルパス・Kawase風 9タップ サンプリング
// BackdropFilter のような重いマルチパス・オフスクリーンレンダーターゲットを回避し、
// Impeller の 1 回の Draw Call で動画にすりガラス風ブラーを適用する
void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;

    if (uBlurRadius <= 0.0) {
        vec4 color = texture(uVideoTexture, uv);
        fragColor = color * uOpacity;
        return;
    }

    vec2 step = (uBlurRadius / uResolution);

    vec4 sum = vec4(0.0);
    sum += texture(uVideoTexture, uv) * 4.0;
    sum += texture(uVideoTexture, uv + vec2(-step.x, -step.y));
    sum += texture(uVideoTexture, uv + vec2(0.0, -step.y)) * 2.0;
    sum += texture(uVideoTexture, uv + vec2(step.x, -step.y));
    sum += texture(uVideoTexture, uv + vec2(-step.x, 0.0)) * 2.0;
    sum += texture(uVideoTexture, uv + vec2(step.x, 0.0)) * 2.0;
    sum += texture(uVideoTexture, uv + vec2(-step.x, step.y));
    sum += texture(uVideoTexture, uv + vec2(0.0, step.y)) * 2.0;
    sum += texture(uVideoTexture, uv + vec2(step.x, step.y));

    vec4 blurredColor = sum / 16.0;
    fragColor = blurredColor * uOpacity;
}

#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) out vec4 fragColor;

// Uniforms:
// 0..1: uResolution (width, height)
// 2:    uTime (seconds)
// 3..4: uPointer (normalized x, y in 0..1)
// 5:    uSmoothness (smooth-union k factor)
// 6..8: uPrimaryColor (r, g, b)
// 9..11: uAccentColor (r, g, b)
layout(location = 0) uniform vec2 uResolution;
layout(location = 1) uniform float uTime;
layout(location = 2) uniform vec2 uPointer;
layout(location = 3) uniform float uSmoothness;
layout(location = 4) uniform vec3 uPrimaryColor;
layout(location = 5) uniform vec3 uAccentColor;

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.001), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float sceneSDF(vec3 p) {
    float t = uTime;
    vec3 c0 = vec3(sin(t * 1.1) * 0.75, cos(t * 0.9) * 0.45, sin(t * 0.7) * 0.3);
    vec3 c1 = vec3(cos(t * 0.8) * -0.7, sin(t * 1.3) * 0.5, cos(t * 1.1) * 0.25);
    vec3 c2 = vec3((uPointer.x - 0.5) * 1.6, (0.5 - uPointer.y) * 1.1, 0.15);
    vec3 c3 = vec3(sin(t * 1.5 + 2.0) * 0.5, cos(t * 1.2 + 1.0) * -0.5, -0.2);

    float d0 = length(p - c0) - 0.42;
    float d1 = length(p - c1) - 0.38;
    float d2 = length(p - c2) - 0.40;
    float d3 = length(p - c3) - 0.34;

    float k = max(uSmoothness, 0.08);
    float d = smin(d0, d1, k);
    d = smin(d, d2, k);
    d = smin(d, d3, k);
    return d;
}

vec3 calcNormal(vec3 p) {
    const vec2 e = vec2(0.002, -0.002);
    return normalize(
        e.xyy * sceneSDF(p + e.xyy) +
        e.yyx * sceneSDF(p + e.yyx) +
        e.yxy * sceneSDF(p + e.yxy) +
        e.xxx * sceneSDF(p + e.xxx)
    );
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = (fragCoord - 0.5 * uResolution) / max(min(uResolution.x, uResolution.y), 1.0);
    uv.y = -uv.y;

    vec3 ro = vec3(0.0, 0.0, 2.6);
    vec3 rd = normalize(vec3(uv, -1.5));

    float t = 0.0;
    bool hit = false;
    vec3 p = ro;
    for (int i = 0; i < 36; i++) {
        p = ro + rd * t;
        float d = sceneSDF(p);
        if (d < 0.003) {
            hit = true;
            break;
        }
        t += d;
        if (t > 5.0) break;
    }

    vec3 bg = mix(vec3(0.04, 0.06, 0.12), vec3(0.08, 0.11, 0.22), uv.y + 0.5);
    if (!hit) {
        fragColor = vec4(bg, 1.0);
        return;
    }

    vec3 n = calcNormal(p);
    vec3 lightDir = normalize(vec3(0.6, 0.8, 1.0));
    vec3 viewDir = -rd;
    vec3 halfVec = normalize(lightDir + viewDir);

    float diff = max(dot(n, lightDir), 0.0);
    float spec = pow(max(dot(n, halfVec), 0.0), 32.0);
    float fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

    vec3 baseCol = mix(uPrimaryColor, uAccentColor, 0.5 + 0.5 * n.y);
    vec3 col = baseCol * (0.22 + 0.78 * diff) + vec3(0.95) * spec * 0.65 + uAccentColor * fresnel * 0.55;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}

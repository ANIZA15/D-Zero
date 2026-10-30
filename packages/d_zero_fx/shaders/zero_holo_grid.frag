#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) out vec4 fragColor;

layout(location = 0) uniform vec2 uResolution;
layout(location = 1) uniform float uTime;
layout(location = 2) uniform vec2 uPointer;
layout(location = 3) uniform float uIntensity;
layout(location = 4) uniform vec3 uGridColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = (fragCoord - 0.5 * uResolution) / max(uResolution.y, 1.0);

    // 3D perspective plane projection
    float horizon = 0.15 + (uPointer.y - 0.5) * 0.25;
    float dy = uv.y - horizon;
    vec3 bg = vec3(0.03, 0.05, 0.10);

    if (dy <= 0.01) {
        float glow = exp(-abs(dy) * 14.0) * 0.6 * uIntensity;
        fragColor = vec4(bg + uGridColor * glow, 1.0);
        return;
    }

    float z = 1.0 / dy;
    float x = (uv.x + (uPointer.x - 0.5) * 0.5) * z;
    float scrollZ = z + uTime * 2.5;

    vec2 grid = abs(fract(vec2(x, scrollZ) * 1.5 - 0.5) - 0.5) / fwidth(vec2(x, scrollZ) * 1.5);
    float line = min(grid.x, grid.y);
    float gridMask = 1.0 - min(line, 1.0);
    float fog = exp(-z * 0.14);

    vec3 col = bg + uGridColor * gridMask * fog * uIntensity;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}

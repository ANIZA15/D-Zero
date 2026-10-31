#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) out vec4 fragColor;

layout(location = 0) uniform vec2 uResolution;
layout(location = 1) uniform float uTime;
layout(location = 2) uniform vec3 uCameraOrbit; // x: yaw, y: pitch, z: distance
layout(location = 3) uniform vec2 uLightAngles; // x: azimuth, y: elevation
layout(location = 4) uniform float uMode;       // 0: Hybrid, 1: RayTracing GI, 2: Nanite Clusters, 3: Wireframe

float sdOctahedron(vec3 p, float s) {
    p = abs(p);
    return (p.x + p.y + p.z - s) * 0.57735027;
}

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

vec2 mapScene(vec3 p, float t) {
    float dFloor = p.y + 1.05;
    vec2 res = vec2(dFloor, 1.0);

    vec3 q = p - vec3(0.0, 0.1 * sin(t * 1.4), 0.0);
    float dCore = sdTorus(q, vec2(0.82, 0.26));
    if (dCore < res.x) res = vec2(dCore, 2.0);

    float dOct = sdOctahedron(p - vec3(0.0, 0.25, 0.0), 0.55);
    if (dOct < res.x) res = vec2(dOct, 3.0);

    for (int i = 0; i < 4; i++) {
        float ang = t * 0.7 + float(i) * 1.5707963;
        vec3 sp = p - vec3(cos(ang) * 1.45, -0.15 + 0.2 * sin(t * 2.0 + float(i)), sin(ang) * 1.45);
        float ds = length(sp) - 0.30;
        if (ds < res.x) res = vec2(ds, 4.0 + float(i));
    }
    return res;
}

vec3 calcNormal(vec3 p, float t) {
    const vec2 e = vec2(0.002, -0.002);
    return normalize(
        e.xyy * mapScene(p + e.xyy, t).x +
        e.yyx * mapScene(p + e.yyx, t).x +
        e.yxy * mapScene(p + e.yxy, t).x +
        e.xxx * mapScene(p + e.xxx, t).x
    );
}

vec3 clusterHashColor(vec3 p) {
    vec3 cell = floor(p * 6.0);
    float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
    return 0.35 + 0.65 * cos(6.28318 * (h + vec3(0.0, 0.33, 0.67)));
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = (fragCoord - 0.5 * uResolution) / max(uResolution.y, 1.0);
    uv.y = -uv.y;

    float cy = cos(uCameraOrbit.x), sy = sin(uCameraOrbit.x);
    float cp = cos(uCameraOrbit.y), sp = sin(uCameraOrbit.y);
    vec3 ro = vec3(sy * cp, sp, cy * cp) * max(uCameraOrbit.z, 1.2);
    vec3 fwd = normalize(-ro);
    vec3 right = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, fwd);
    vec3 rd = normalize(fwd + (uv.x * right + uv.y * up) * 0.577);

    float t = 0.0;
    float matId = -1.0;
    for (int i = 0; i < 48; i++) {
        vec2 h = mapScene(ro + rd * t, uTime);
        if (h.x < 0.0025) {
            matId = h.y;
            break;
        }
        t += h.x;
        if (t > 14.0) break;
    }

    vec3 sky = mix(vec3(0.03, 0.05, 0.10), vec3(0.07, 0.14, 0.26), clamp(uv.y + 0.5, 0.0, 1.0));
    if (matId < 0.0) {
        fragColor = vec4(sky, 1.0);
        return;
    }

    vec3 pos = ro + rd * t;
    vec3 nor = calcNormal(pos, uTime);
    vec3 lightDir = normalize(vec3(
        cos(uLightAngles.y) * sin(uLightAngles.x),
        sin(uLightAngles.y),
        cos(uLightAngles.y) * cos(uLightAngles.x)
    ));

    float diff = max(dot(nor, lightDir), 0.0);
    vec3 baseCol = vec3(0.15, 0.65, 0.95);
    if (matId == 1.0) baseCol = vec3(0.06, 0.14, 0.22);
    else if (matId == 3.0) baseCol = vec3(0.95, 0.38, 0.18);
    else if (matId >= 4.0) baseCol = vec3(0.55, 0.25, 0.92);

    if (uMode > 1.5 && uMode < 2.5) {
        baseCol = clusterHashColor(pos);
    }

    vec3 halfV = normalize(lightDir - rd);
    float spec = pow(max(dot(nor, halfV), 0.0), 36.0);
    vec3 col = baseCol * (0.20 + 0.80 * diff) + vec3(0.95) * spec * 0.6;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}

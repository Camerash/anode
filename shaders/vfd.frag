#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

layout(location = 0)  uniform vec2  uSize;
layout(location = 1)  uniform float uTime;
layout(location = 2)  uniform float uTilt;
layout(location = 3)  uniform vec3  uPhosphor;
layout(location = 4)  uniform vec4  uLayers;
layout(location = 5)  uniform float uGrain;
layout(location = 6)  uniform float uBar;
layout(location = 7)  uniform vec4  uSegA;
layout(location = 8)  uniform vec4  uSegB;
layout(location = 9)  uniform vec4  uSegC;
layout(location = 10) uniform vec4  uSegD;
layout(location = 11) uniform vec4  uSegE;
layout(location = 12) uniform vec4  uSegF;

out vec4 fragColor;

const float DS = 0.42;
const float SEG_R = 0.055;
const float EDGE_OUT = 0.0035;
const float EDGE_IN = -0.0030;

float sdSeg(vec2 p, vec2 a, vec2 b, float r) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

float sdBox(vec2 p, vec2 b) {
  vec2 d = abs(p) - b;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float halo(float d) {
  float e = max(d, 0.0);
  return exp(-e * 20.0) * 0.42 + exp(-e * 90.0) * 0.58;
}

void addSeg(vec2 lp, vec2 a, vec2 b, float br,
            inout float glow, inout float core, inout float dim) {
  float d = sdSeg(lp, a, b, SEG_R) * DS;
  float f = smoothstep(EDGE_OUT, EDGE_IN, d);
  glow += br * halo(d);
  core = max(core, br * f);
  dim = max(dim, f * (1.0 - br));
}

void addDigit(vec2 q, vec2 c, vec4 s0, vec4 s1,
              inout float glow, inout float core, inout float dim) {
  vec2 lp = (q - c) / DS;
  if (sdBox(lp, vec2(0.34, 0.70)) > 1.9) return;
  addSeg(lp, vec2(-0.20,  0.60), vec2( 0.20,  0.60), s0.x, glow, core, dim);
  addSeg(lp, vec2( 0.27,  0.54), vec2( 0.27,  0.06), s0.y, glow, core, dim);
  addSeg(lp, vec2( 0.27, -0.06), vec2( 0.27, -0.54), s0.z, glow, core, dim);
  addSeg(lp, vec2(-0.20, -0.60), vec2( 0.20, -0.60), s0.w, glow, core, dim);
  addSeg(lp, vec2(-0.27, -0.06), vec2(-0.27, -0.54), s1.x, glow, core, dim);
  addSeg(lp, vec2(-0.27,  0.54), vec2(-0.27,  0.06), s1.y, glow, core, dim);
  addSeg(lp, vec2(-0.20,  0.00), vec2( 0.20,  0.00), s1.z, glow, core, dim);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 flipped = vec2(fc.x, uSize.y - fc.y);
  vec2 uv = (flipped - 0.5 * uSize) / uSize.y;

  float lBloom = uLayers.x;
  float lUnlit = uLayers.y;
  float lGrid = uLayers.z;
  float lFilament = uLayers.w;

  vec2 q = uv + vec2(uTilt * 0.012, 0.0);

  float glow = 0.0;
  float core = 0.0;
  float dim = 0.0;

  addDigit(q, vec2(-0.345, 0.11), uSegA, uSegB, glow, core, dim);
  addDigit(q, vec2( 0.000, 0.11), uSegC, uSegD, glow, core, dim);
  addDigit(q, vec2( 0.345, 0.11), uSegE, uSegF, glow, core, dim);

  vec2 bp = q - vec2(0.0, -0.33);
  float cell = 0.098;
  float n = 20.0;
  float bx = bp.x + n * cell * 0.5;
  float idx = floor(bx / cell);
  float lx = mod(bx, cell) - cell * 0.5;
  float inRange = step(0.0, idx) * step(idx, n - 1.0);
  float lit = inRange * step(idx + 0.5, uBar * n);
  float dBar = sdBox(vec2(lx, bp.y), vec2(cell * 0.29, 0.042));
  float fBar = smoothstep(EDGE_OUT, EDGE_IN, dBar);
  glow += lit * halo(dBar);
  core = max(core, lit * fBar);
  dim = max(dim, inRange * fBar * (1.0 - lit));

  vec3 col = vec3(0.013, 0.017, 0.016) + uPhosphor * 0.010;

  vec3 unlitCol = mix(vec3(0.085, 0.095, 0.090), uPhosphor * 0.13, 0.40);
  col = mix(col, unlitCol, dim * lUnlit);

  float mesh = (0.55 + 0.45 * sin(q.x * 560.0)) * (0.55 + 0.45 * sin(q.y * 560.0));
  float meshF = mix(1.0, 0.70 + 0.30 * mesh, lGrid);
  float mux = 0.985 + 0.015 * sin(uTime * 240.0);

  vec3 em = uPhosphor * glow * lBloom * 1.15
          + mix(uPhosphor, vec3(1.0), 0.55) * core * 1.30;
  col += em * meshF * mux;

  float fil = 0.0;
  for (int k = 0; k < 3; k++) {
    float fy = 0.11 + (float(k) - 1.0) * 0.215;
    fil = max(fil, 1.0 - smoothstep(0.0, 0.0024, abs(q.y - fy)));
  }
  fil *= step(abs(q.x), 0.62) * lFilament;
  col = mix(col, col * 0.50 + vec3(0.040, 0.024, 0.010), fil);

  float sheen = smoothstep(0.85, 0.0, abs(uv.x - uTilt * 0.85 + uv.y * 0.55));
  col += vec3(0.026, 0.032, 0.036) * sheen * 0.40;

  float g = hash(flipped + fract(uTime * 3.0) * vec2(37.0, 91.0));
  col *= 1.0 + (g - 0.5) * 0.075 * uGrain;
  col += (g - 0.5) * 0.022 * uGrain;

  col = col / (1.0 + col * 0.55);
  col = pow(max(col, 0.0), vec3(0.86));

  fragColor = vec4(col, 1.0);
}

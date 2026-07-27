#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

layout(location = 0)  uniform vec2  uSize;
layout(location = 1)  uniform float uTime;
layout(location = 2)  uniform float uTilt;
layout(location = 3)  uniform vec3  uPhosphor;
layout(location = 4)  uniform vec4  uLayers;
layout(location = 5)  uniform float uGrain;
layout(location = 6)  uniform vec2  uSafeMin;
layout(location = 7)  uniform vec2  uSafeMax;
layout(location = 8)  uniform float uAspect;
layout(location = 9)  uniform float uCount;
layout(location = 10) uniform vec2  uDataSize;

// Per-component parameters. Four gauges would exhaust the uniform budget, so
// component data is packed into a small texture instead. Sampled at exact texel
// centres, which returns the stored value under either filter mode.
uniform sampler2D uData;

out vec4 fragColor;

const int MAX_COMPONENTS = 16;

// Only RGB carries data; alpha is always 1. Image formats are premultiplied, so
// a payload value stored in alpha comes back scaled, or zeroed when it happens
// to be 0. Mirrored in component_data.dart.
const float HEADER_TEXELS = 3.0;
const float TEXELS_PER_DIGIT = 3.0;

// The data texture is range-clamped to [0, 1] even though it holds floats, so
// everything outside that range is stored normalised. Mirrored in
// component_data.dart.
const float POSITION_RANGE = 4.0;
const float SIZE_SCALE = 8.0;
const float TYPE_SCALE = 8.0;
const float COUNT_SCALE = 64.0;

float decodePosition(float s) { return (s - 0.5) * 2.0 * POSITION_RANGE; }
vec2 decodePosition(vec2 s) { return (s - 0.5) * 2.0 * POSITION_RANGE; }

// Component type ids, mirrored in component_data.dart.
const float TYPE_DIGITS = 1.0;
const float TYPE_BAR = 2.0;
const float TYPE_LEGEND = 3.0;

const float SEG_R = 0.055;
const float EDGE_OUT = 0.0035;
const float EDGE_IN = -0.0030;

// A seven-segment glyph spans 1.4 units in its local space, so a component of
// height h renders at this scale. At the authored height this recovers the
// tuned 0.42 exactly.
const float DIGIT_LOCAL_HEIGHT = 1.4;

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

vec4 fetch(float row, float col) {
  return texture(uData, (vec2(col, row) + 0.5) / uDataSize);
}

void addSeg(vec2 lp, vec2 a, vec2 b, float br, float ds,
            inout float glow, inout float core, inout float dim) {
  float d = sdSeg(lp, a, b, SEG_R) * ds;
  float f = smoothstep(EDGE_OUT, EDGE_IN, d);
  glow += br * halo(d);
  core = max(core, br * f);
  dim = max(dim, f * (1.0 - br));
}

void addDigit(vec2 q, vec2 c, float ds, vec3 sA, vec3 sB, float sG,
              inout float glow, inout float core, inout float dim) {
  vec2 lp = (q - c) / ds;
  if (sdBox(lp, vec2(0.34, 0.70)) > 1.9) return;
  addSeg(lp, vec2(-0.20,  0.60), vec2( 0.20,  0.60), sA.x, ds, glow, core, dim);
  addSeg(lp, vec2( 0.27,  0.54), vec2( 0.27,  0.06), sA.y, ds, glow, core, dim);
  addSeg(lp, vec2( 0.27, -0.06), vec2( 0.27, -0.54), sA.z, ds, glow, core, dim);
  addSeg(lp, vec2(-0.20, -0.60), vec2( 0.20, -0.60), sB.x, ds, glow, core, dim);
  addSeg(lp, vec2(-0.27, -0.06), vec2(-0.27, -0.54), sB.y, ds, glow, core, dim);
  addSeg(lp, vec2(-0.27,  0.54), vec2(-0.27,  0.06), sB.z, ds, glow, core, dim);
  addSeg(lp, vec2(-0.20,  0.00), vec2( 0.20,  0.00), sG,   ds, glow, core, dim);
}

// Legend glyphs. Etched anode shapes rather than seven-segment, stroked with the
// same sdSeg primitive so they inherit the halo maths. Glyph-local space is a
// unit cap height centred on the origin; the baked SDF atlas replaces this.
const float LEG_R = 0.13;
const float LEG_ADV = 0.82;
const float LEG_GLOW = 0.45;

// Halo falloff scales with feature size. Legend strokes are roughly a third of a
// digit segment's width and packed far tighter, so reusing halo() would sum a
// dozen digit-sized lobes into one blown-out blob.
float legHalo(float d) {
  float e = max(d, 0.0);
  return exp(-e * 70.0) * 0.42 + exp(-e * 260.0) * 0.58;
}

void legSeg(vec2 g, vec2 a, vec2 b, float br, float legH,
            inout float glow, inout float core, inout float dim) {
  float d = sdSeg(g, a, b, LEG_R) * legH;
  float f = smoothstep(EDGE_OUT, EDGE_IN, d);
  glow += br * legHalo(d) * LEG_GLOW;
  core = max(core, br * f);
  dim = max(dim, f * (1.0 - br));
}

void glyphK(vec2 g, float br, float lh, inout float glow, inout float core, inout float dim) {
  legSeg(g, vec2(-0.26, -0.50), vec2(-0.26, 0.50), br, lh, glow, core, dim);
  legSeg(g, vec2(-0.26,  0.00), vec2( 0.26, 0.50), br, lh, glow, core, dim);
  legSeg(g, vec2(-0.26,  0.00), vec2( 0.26, -0.50), br, lh, glow, core, dim);
}

void glyphM(vec2 g, float br, float lh, inout float glow, inout float core, inout float dim) {
  legSeg(g, vec2(-0.28, -0.50), vec2(-0.28, 0.50), br, lh, glow, core, dim);
  legSeg(g, vec2( 0.28, -0.50), vec2( 0.28, 0.50), br, lh, glow, core, dim);
  legSeg(g, vec2(-0.28,  0.50), vec2( 0.00, 0.02), br, lh, glow, core, dim);
  legSeg(g, vec2( 0.28,  0.50), vec2( 0.00, 0.02), br, lh, glow, core, dim);
}

void glyphH(vec2 g, float br, float lh, inout float glow, inout float core, inout float dim) {
  legSeg(g, vec2(-0.26, -0.50), vec2(-0.26, 0.50), br, lh, glow, core, dim);
  legSeg(g, vec2( 0.26, -0.50), vec2( 0.26, 0.50), br, lh, glow, core, dim);
  legSeg(g, vec2(-0.26,  0.00), vec2( 0.26, 0.00), br, lh, glow, core, dim);
}

void glyphP(vec2 g, float br, float lh, inout float glow, inout float core, inout float dim) {
  legSeg(g, vec2(-0.26, -0.50), vec2(-0.26, 0.50), br, lh, glow, core, dim);
  legSeg(g, vec2(-0.26,  0.50), vec2( 0.16, 0.50), br, lh, glow, core, dim);
  legSeg(g, vec2( 0.22,  0.43), vec2( 0.22, 0.14), br, lh, glow, core, dim);
  legSeg(g, vec2(-0.26,  0.07), vec2( 0.16, 0.07), br, lh, glow, core, dim);
}

void glyphSlash(vec2 g, float br, float lh, inout float glow, inout float core, inout float dim) {
  legSeg(g, vec2(-0.20, -0.50), vec2(0.20, 0.50), br, lh, glow, core, dim);
}

void addKmh(vec2 q, float left, float cy, float br, float lh,
            inout float glow, inout float core, inout float dim) {
  vec2 g = (q - vec2(left, cy)) / lh;
  if (sdBox(g - vec2(4.0 * LEG_ADV * 0.5, 0.0),
            vec2(4.0 * LEG_ADV * 0.5, 0.5)) > 2.6) return;
  glyphK(g - vec2(0.5 * LEG_ADV, 0.0), br, lh, glow, core, dim);
  glyphM(g - vec2(1.5 * LEG_ADV, 0.0), br, lh, glow, core, dim);
  glyphSlash(g - vec2(2.5 * LEG_ADV, 0.0), br, lh, glow, core, dim);
  glyphH(g - vec2(3.5 * LEG_ADV, 0.0), br, lh, glow, core, dim);
}

void addMph(vec2 q, float left, float cy, float br, float lh,
            inout float glow, inout float core, inout float dim) {
  vec2 g = (q - vec2(left, cy)) / lh;
  if (sdBox(g - vec2(3.0 * LEG_ADV * 0.5, 0.0),
            vec2(3.0 * LEG_ADV * 0.5, 0.5)) > 2.6) return;
  glyphM(g - vec2(0.5 * LEG_ADV, 0.0), br, lh, glow, core, dim);
  glyphP(g - vec2(1.5 * LEG_ADV, 0.0), br, lh, glow, core, dim);
  glyphH(g - vec2(2.5 * LEG_ADV, 0.0), br, lh, glow, core, dim);
}

void addDigitsComponent(vec2 q, vec2 c, vec2 sz, float count, float row,
                        inout float glow, inout float core, inout float dim) {
  float ds = sz.y / DIGIT_LOCAL_HEIGHT;
  float adv = sz.x / max(count, 1.0);
  for (int k = 0; k < 4; k++) {
    // Compared against the rounded count. The count survives a round trip
    // through the texture as very slightly more than it went in, and a bare
    // `>=` then draws one digit too many.
    if (float(k) > count - 0.5) continue;
    float cx = c.x - sz.x * 0.5 + (float(k) + 0.5) * adv;
    float t = HEADER_TEXELS + float(k) * TEXELS_PER_DIGIT;
    vec3 sA = fetch(row, t).rgb;
    vec3 sB = fetch(row, t + 1.0).rgb;
    float sG = fetch(row, t + 2.0).r;
    addDigit(q, vec2(cx, c.y), ds, sA, sB, sG, glow, core, dim);
  }
}

void addBarComponent(vec2 q, vec2 c, vec2 sz, float cells, float frac,
                     inout float glow, inout float core, inout float dim) {
  vec2 bp = q - c;
  float cell = sz.x / max(cells, 1.0);
  float bx = bp.x + sz.x * 0.5;
  // Each cell is evaluated against its own centre rather than a mod() cell-local
  // coordinate, and neighbours are accumulated, so halos bleed across cell
  // boundaries and past the ends of the strip instead of being capped per cell.
  // inRange still gates every derived term, or phantom unlit cells appear.
  float base = floor(bx / cell);
  for (int k = -3; k <= 3; k++) {
    float idx = base + float(k);
    float inRange = step(0.0, idx) * step(idx, cells - 1.0);
    float lit = inRange * step(idx + 0.5, frac * cells);
    float lx = bx - (idx + 0.5) * cell;
    float dBar = sdBox(vec2(lx, bp.y), vec2(cell * 0.29, sz.y * 0.5));
    float fBar = smoothstep(EDGE_OUT, EDGE_IN, dBar);
    glow += lit * halo(dBar);
    core = max(core, lit * fBar);
    dim = max(dim, inRange * fBar * (1.0 - lit));
  }
}

void addLegendComponent(vec2 q, vec2 c, vec2 sz, float unit,
                        inout float glow, inout float core, inout float dim) {
  // Two stacked lines inside the component box: one cap height plus the gap.
  float lh = sz.y / 3.9;
  float sep = sz.y * 0.744;
  float left = c.x - sz.x * 0.5;
  addKmh(q, left, c.y + sep * 0.5, 1.0 - unit, lh, glow, core, dim);
  addMph(q, left, c.y - sep * 0.5, unit, lh, glow, core, dim);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 flipped = vec2(fc.x, uSize.y - fc.y);

  // Contain-fit the authored frame inside the safe rect. Placement only — no
  // mask and no clamp, so halo, sheen and grain still spill past it.
  vec2 safeSize = uSafeMax - uSafeMin;
  vec2 safeCenter = 0.5 * (uSafeMin + uSafeMax);
  float fitScale = min(safeSize.x / uAspect, safeSize.y);
  vec2 uv = (flipped - safeCenter) / fitScale;

  float lBloom = uLayers.x;
  float lUnlit = uLayers.y;
  float lGrid = uLayers.z;
  float lFilament = uLayers.w;

  vec2 q = uv + vec2(uTilt * 0.012, 0.0);

  // Every component accumulates into the same three values. This is what makes
  // halos compound across component boundaries: there is one pass and one
  // surface, so adjacent gauges bleed into each other with no seam.
  float glow = 0.0;
  float core = 0.0;
  float dim = 0.0;

  for (int i = 0; i < MAX_COMPONENTS; i++) {
    if (float(i) >= uCount) continue;
    float row = float(i);
    vec3 head = fetch(row, 0.0).rgb;
    vec3 body = fetch(row, 1.0).rgb;
    float type = head.x * TYPE_SCALE;
    vec2 c = decodePosition(head.yz);
    vec2 sz = body.xy * SIZE_SCALE;
    float count = body.z * COUNT_SCALE;

    if (type < TYPE_DIGITS + 0.5) {
      addDigitsComponent(q, c, sz, count, row, glow, core, dim);
    } else if (type < TYPE_BAR + 0.5) {
      addBarComponent(q, c, sz, count, fetch(row, 2.0).r, glow, core, dim);
    } else if (type < TYPE_LEGEND + 0.5) {
      addLegendComponent(q, c, sz, count, glow, core, dim);
    }
  }

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

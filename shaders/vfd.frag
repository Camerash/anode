#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

layout(location = 0)  uniform vec2  uSize;
layout(location = 1)  uniform float uTime;
layout(location = 2)  uniform float uTilt;
layout(location = 3)  uniform vec3  uPhosphor;
layout(location = 4)  uniform vec4  uLayers;
layout(location = 5)  uniform float uGrain;
layout(location = 6)  uniform vec2  uFitMin;
layout(location = 7)  uniform vec2  uFitMax;
// The authored frame extent in design units. A design unit is frame-independent
// — every optical constant below is expressed in them, so the unit must not
// change meaning when the frame's shape does.
layout(location = 8)  uniform vec2  uFrame;
layout(location = 9)  uniform float uCount;
layout(location = 10) uniform vec2  uDataSize;
layout(location = 11) uniform float uPreviewOnly;

// Per-component parameters. Four gauges would exhaust the uniform budget, so
// component data is packed into a small texture instead. Sampled at exact texel
// centres, which returns the stored value under either filter mode.
uniform sampler2D uData;
uniform sampler2D uPrismGlyphs;

out vec4 fragColor;

const int MAX_COMPONENTS = 16;

// Only RGB carries data; alpha is always 1. Image formats are premultiplied, so
// a payload value stored in alpha comes back scaled, or zeroed when it happens
// to be 0. Mirrored in component_data.dart.
const float HEADER_TEXELS = 10.0;
const float TEXELS_PER_DIGIT = 3.0;

// The image path samples normalised 8-bit channels even though Dart uploads an
// rgbaFloat32 buffer. Everything is stored in [0, 1]; geometry combines high
// and low byte lanes below. Mirrored in component_data.dart.
const float POSITION_RANGE = 16.0;
const float SIZE_SCALE = 32.0;
const float TYPE_POSITION_SIGN_SCALE = 32.0;
const float COUNT_SCALE = 64.0;
const float EFFECT_SCALE = 2.0;
const float MODULE_FLAG_SCALE = 8.0;
// The reference tube height the filament layout was measured against. New
// constant, not a rescaled one: the main module used to be hardcoded one unit
// tall on the Dart side, so this preserves that geometry now that its size is
// the authored frame extent.
const float MAIN_TUBE_HEIGHT = 1.0;
const float PRISM_GLYPH_COUNT = 43.0;
const vec2 PRISM_ATLAS_GRID = vec2(8.0, 6.0);

float decodePackedScalar(float highByte, float lowByte) {
  float high = round(highByte * 255.0);
  float low = round(lowByte * 255.0);
  return (high * 256.0 + low) / 65535.0;
}

vec2 decodePackedScalar(vec2 highByte, vec2 lowByte) {
  return vec2(
    decodePackedScalar(highByte.x, lowByte.x),
    decodePackedScalar(highByte.y, lowByte.y)
  );
}

vec2 decodePosition(vec2 highByte, vec2 lowByte, float signBits) {
  vec2 signs = vec2(
    1.0 - 2.0 * step(0.5, mod(signBits, 2.0)),
    1.0 - 2.0 * step(1.5, signBits)
  );
  return decodePackedScalar(highByte, lowByte) * POSITION_RANGE * signs;
}

// Component type ids, mirrored in component_data.dart.
const float TYPE_DIGITS = 1.0;
const float TYPE_BAR = 2.0;
const float TYPE_LEGEND = 3.0;
const float TYPE_PRISM = 4.0;

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

float prismGlyphSample(float row, float glyphIndex, vec2 cellUv) {
  float payloadTexel = HEADER_TEXELS + floor(glyphIndex / 3.0);
  vec3 packed = fetch(row, payloadTexel).rgb;
  float channel = mod(glyphIndex, 3.0);
  float encoded = channel < 0.5
      ? packed.r
      : (channel < 1.5 ? packed.g : packed.b);
  float atlasIndex = floor(encoded * (PRISM_GLYPH_COUNT - 1.0) + 0.5);
  vec2 atlasCell = vec2(
    mod(atlasIndex, PRISM_ATLAS_GRID.x),
    floor(atlasIndex / PRISM_ATLAS_GRID.x)
  );
  return texture(
    uPrismGlyphs,
    (atlasCell + clamp(cellUv, 0.0, 1.0)) / PRISM_ATLAS_GRID
  ).r;
}

void addPrismComponent(
  vec2 q, vec2 c, vec2 sz, float glyphCount, float row,
  float lit, float pressed, vec3 style,
  inout float glow, inout float core,
  inout vec3 prismSurface, inout float prismSurfaceCoverage,
  inout float prismOcclusion
) {
  vec2 halfSize = sz * 0.5;
  float depthScale = clamp(style.x / 0.12, 0.55, 1.45);
  float opticalDensity = clamp(style.y, 0.60, 0.95);
  float bevelDensity = min(opticalDensity + 0.10, 1.0);
  float inactiveScale = clamp(style.z / 0.18, 0.0, 2.8);
  vec2 pressOffset = vec2(0.0, -sz.y * 0.07 * pressed);

  vec2 socketP = q - c;
  float socketD = sdBox(socketP, halfSize);
  float socketFill = smoothstep(EDGE_OUT, EDGE_IN, socketD);
  float gasketOuterD = sdBox(socketP, halfSize * vec2(0.94, 0.88));
  float gasketOuterFill = smoothstep(EDGE_OUT, EDGE_IN, gasketOuterD);
  float gasketInnerD = sdBox(socketP, halfSize * vec2(0.89, 0.79));
  float gasketInnerFill = smoothstep(EDGE_OUT, EDGE_IN, gasketInnerD);
  float skirtFill = max(socketFill - gasketOuterFill, 0.0);
  float gasketFill = max(gasketOuterFill - gasketInnerFill, 0.0);

  vec2 capP = q - c - pressOffset;
  vec2 capHalf = halfSize * vec2(0.88, 0.78);
  float capD = sdBox(capP, capHalf);
  float capFill = smoothstep(EDGE_OUT, EDGE_IN, capD);
  vec2 faceHalf = capHalf * vec2(
    0.88 - 0.035 * depthScale,
    0.68 - 0.055 * depthScale
  );
  float faceD = sdBox(capP - vec2(0.0, sz.y * 0.015), faceHalf);
  float faceFill = smoothstep(EDGE_OUT, EDGE_IN, faceD);
  float bevelFill = max(capFill - faceFill, 0.0);

  vec3 surface = vec3(0.0);
  surface = mix(surface, vec3(0.115, 0.130, 0.122), skirtFill);
  surface = mix(surface, vec3(0.004, 0.006, 0.005), gasketFill);
  vec3 sideColour = mix(
    vec3(0.115, 0.130, 0.123),
    vec3(0.018, 0.023, 0.021),
    clamp((capP.y / max(capHalf.y, 0.001) + 1.0) * 0.5, 0.0, 1.0)
  );
  surface = mix(surface, sideColour, bevelFill);
  vec3 faceColour = mix(
    vec3(0.034, 0.041, 0.038),
    vec3(0.008, 0.011, 0.010),
    opticalDensity
  );
  surface = mix(surface, faceColour, faceFill);

  float topEdge = (1.0 - smoothstep(0.0, 0.0032, abs(capP.y - faceHalf.y)))
                * step(abs(capP.x), faceHalf.x);
  float leftEdge = (1.0 - smoothstep(0.0, 0.0022, abs(capP.x + faceHalf.x)))
                 * step(abs(capP.y), faceHalf.y);
  float bottomEdge =
      (1.0 - smoothstep(0.0, 0.0028, abs(capP.y + faceHalf.y)))
      * step(abs(capP.x), faceHalf.x);
  float rightEdge =
      (1.0 - smoothstep(0.0, 0.0022, abs(capP.x - faceHalf.x)))
      * step(abs(capP.y), faceHalf.y);
  surface += vec3(0.34, 0.37, 0.35)
           * topEdge * mix(0.45, 0.26, pressed);
  surface += vec3(0.20, 0.23, 0.21) * leftEdge * 0.22;
  surface = mix(
    surface,
    vec3(0.002, 0.003, 0.003),
    max(bottomEdge, rightEdge * 0.72) * mix(0.30, 0.56, pressed)
  );

  float count = clamp(floor(glyphCount + 0.5), 0.0, 24.0);
  float advance = min(
    faceHalf.x * 2.0 / max(count, 1.0),
    faceHalf.y * 0.92
  );
  float glyphHeight = min(faceHalf.y * 1.58, advance * 1.85);
  float textWidth = count * advance;
  float textIndex = floor((capP.x + textWidth * 0.5) / max(advance, 0.001));
  float inTextX = step(0.0, textIndex) * step(textIndex, count - 1.0);
  float inTextY = step(abs(capP.y), glyphHeight * 0.5);
  vec2 cellUv = vec2(
    (capP.x + textWidth * 0.5 - textIndex * advance) / max(advance, 0.001),
    0.5 - capP.y / max(glyphHeight, 0.001)
  );
  float sdf = prismGlyphSample(row, max(textIndex, 0.0), cellUv);
  float glyphCore = smoothstep(0.48, 0.56, sdf) * inTextX * inTextY;
  float glyphHalo = smoothstep(0.36, 0.50, sdf) * inTextX * inTextY;

  float isActive = step(0.001, lit);
  surface += vec3(0.30, 0.32, 0.31)
           * glyphCore * (1.0 - isActive) * inactiveScale;
  glow += glyphHalo * lit * 0.68;
  core = max(core, glyphCore * lit * 0.88);
  core = max(core, faceFill * lit * 0.025);

  float surfaceCoverage = max(
    max(skirtFill * 0.48, gasketFill * 0.84),
    max(bevelFill * bevelDensity, faceFill * opticalDensity)
  );
  prismSurface += surface;
  prismSurfaceCoverage = max(prismSurfaceCoverage, surfaceCoverage);
  prismOcclusion = max(prismOcclusion, surfaceCoverage);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 flipped = vec2(fc.x, uSize.y - fc.y);

  // Contain-fit the authored frame inside the fit rect. Placement only — no
  // mask and no clamp, so halo, sheen and grain still spill past it.
  vec2 fitSize = uFitMax - uFitMin;
  vec2 fitCenter = 0.5 * (uFitMin + uFitMax);
  float fitScale = min(fitSize.x / uFrame.x, fitSize.y / uFrame.y);
  vec2 uv = (flipped - fitCenter) / fitScale;

  vec2 q = uv + vec2(uTilt * 0.012, 0.0);

  // Every component accumulates into the same three values. This is what makes
  // halos compound across component boundaries: there is one pass and one
  // surface, so adjacent gauges bleed into each other with no seam.
  vec3 substrate = vec3(0.013, 0.017, 0.016) + uPhosphor * 0.010;
  // Keep the compatibility uniform active until the Dart-side uniform layout
  // is deliberately versioned. This is optically invisible.
  substrate += uPhosphor * (uLayers.x + uLayers.y + uLayers.z) * 0.000000001;

  vec3 emission = vec3(0.0);
  vec3 prismEmission = vec3(0.0);
  vec3 unlitDelta = vec3(0.0);
  vec3 prismSurface = vec3(0.0);
  float prismSurfaceCoverage = 0.0;
  float prismOcclusion = 0.0;
  float filamentMask = 0.0;
  float grainStrength = uGrain * (1.0 - step(0.5, uCount));
  float previewCoverage = 0.0;

  for (int i = 0; i < MAX_COMPONENTS; i++) {
    if (float(i) >= uCount) continue;
    float row = float(i);
    vec3 head = fetch(row, 0.0).rgb;
    vec3 body = fetch(row, 1.0).rgb;
    float typeAndSigns = round(head.x * TYPE_POSITION_SIGN_SCALE);
    float type = floor(typeAndSigns / 4.0);
    vec4 componentGeometryLow;
    vec4 moduleGeometryLow;
    if (type < TYPE_PRISM - 0.5) {
      vec3 low0 = fetch(row, HEADER_TEXELS + 2.0).rgb;
      vec3 low1 = fetch(row, HEADER_TEXELS + 5.0).rgb;
      vec3 low2 = fetch(row, HEADER_TEXELS + 8.0).rgb;
      vec3 low3 = fetch(row, HEADER_TEXELS + 11.0).rgb;
      componentGeometryLow = vec4(low0.gb, low1.gb);
      moduleGeometryLow = vec4(low2.gb, low3.gb);
    } else {
      vec3 low0 = fetch(row, HEADER_TEXELS + 8.0).rgb;
      vec3 low1 = fetch(row, HEADER_TEXELS + 9.0).rgb;
      vec3 low2 = fetch(row, HEADER_TEXELS + 10.0).rgb;
      componentGeometryLow = vec4(low0.rgb, low1.r);
      moduleGeometryLow = vec4(low1.gb, low2.rg);
    }
    vec2 c = decodePosition(
      head.yz,
      componentGeometryLow.xy,
      mod(typeAndSigns, 4.0)
    );
    vec2 sz = decodePackedScalar(body.xy, componentGeometryLow.zw) * SIZE_SCALE;
    float count = body.z * COUNT_SCALE;
    vec3 params = fetch(row, 2.0).rgb;
    vec3 phosphor = fetch(row, 3.0).rgb;
    vec3 opticalA = fetch(row, 4.0).rgb * EFFECT_SCALE;
    vec3 opticalB = fetch(row, 5.0).rgb * EFFECT_SCALE;
    vec3 moduleA = fetch(row, 6.0).rgb;
    vec3 moduleB = fetch(row, 7.0).rgb;
    vec3 interaction = fetch(row, 8.0).rgb;
    vec3 prismStyle = fetch(row, 9.0).rgb;
    float pressed = interaction.r;

    float glow = 0.0;
    float core = 0.0;
    float dim = 0.0;

    if (type < TYPE_DIGITS + 0.5) {
      addDigitsComponent(q, c, sz, count, row, glow, core, dim);
    } else if (type < TYPE_BAR + 0.5) {
      addBarComponent(q, c, sz, count, params.r, glow, core, dim);
    } else if (type < TYPE_LEGEND + 0.5) {
      addLegendComponent(q, c, sz, count, glow, core, dim);
    } else if (type < TYPE_PRISM + 0.5) {
      addPrismComponent(
        q, c, sz, count, row, params.b * EFFECT_SCALE, pressed, prismStyle,
        glow, core, prismSurface, prismSurfaceCoverage, prismOcclusion
      );
    }

    previewCoverage = max(previewCoverage, core);
    previewCoverage = max(previewCoverage, dim * 0.38);
    previewCoverage = max(previewCoverage, min(1.0, glow * 0.42));
    previewCoverage = max(previewCoverage, prismSurfaceCoverage * 0.22);

    float mesh = (0.55 + 0.45 * sin(q.x * 560.0)) * (0.55 + 0.45 * sin(q.y * 560.0));
    float meshF = mix(1.0, 0.70 + 0.30 * mesh, clamp(opticalB.x, 0.0, 1.0));
    float mux = 0.985 + 0.015 * sin(uTime * 240.0);
    float coating = 1.0 + (hash(q * 173.0 + row * 19.0) - 0.5)
                          * 0.10 * opticalA.z;

    vec3 em = phosphor * glow * opticalA.y * 1.15
            + mix(phosphor, vec3(1.0), 0.55) * core * 1.30;
    if (type < TYPE_PRISM - 0.5) {
      emission += em * meshF * mux * opticalA.x * coating;
    } else {
      prismEmission += em * mux * opticalA.x;
    }

    vec3 unlitCol = mix(vec3(0.085, 0.095, 0.090), phosphor * 0.13, 0.40);
    unlitDelta += (unlitCol - substrate) * dim * opticalB.y;

    float moduleFlags = round(interaction.b * MODULE_FLAG_SCALE);
    vec2 moduleCenter = decodePosition(
      moduleA.xy,
      moduleGeometryLow.xy,
      floor(moduleFlags / 2.0)
    );
    vec2 moduleSize = vec2(
      decodePackedScalar(moduleA.z, moduleGeometryLow.z),
      decodePackedScalar(moduleB.x, moduleGeometryLow.w)
    ) * SIZE_SCALE;
    vec2 mq = q - moduleCenter;
    float inModule = step(abs(mq.x), moduleSize.x * 0.5)
                   * step(abs(mq.y), moduleSize.y * 0.5);
    // Packed explicitly. The main module's size now equals the frame extent, so
    // comparing geometry would also match an authored sub-module a user sized
    // to the whole frame.
    float mainModule = mod(moduleFlags, 2.0);
    grainStrength = max(
      grainStrength,
      moduleB.y * EFFECT_SCALE * mix(inModule, 1.0, mainModule)
    );

    // Cathode spacing is a property of the physical tube, not of the envelope
    // drawn around it. The main module spans whatever frame it is given, so it
    // references the tube height directly rather than its own extent; an
    // authored sub-module still lays its wires out relative to itself.
    float filRef = mix(moduleSize.y, MAIN_TUBE_HEIGHT, mainModule);
    float fil = 0.0;
    for (int k = 0; k < 3; k++) {
      float fy = moduleCenter.y
               + (0.11 + (float(k) - 1.0) * 0.215) * filRef;
      fil = max(fil, 1.0 - smoothstep(0.0, 0.0024, abs(q.y - fy)));
    }
    float filamentHalfWidth = 0.62 * moduleSize.x / max(uFrame.x, 0.001);
    fil *= step(abs(mq.x), filamentHalfWidth)
         * inModule
         * moduleB.z * EFFECT_SCALE;
    filamentMask = max(filamentMask, fil);
  }

  vec3 col = substrate + unlitDelta + emission;
  col = mix(col, prismSurface, clamp(prismSurfaceCoverage, 0.0, 1.0));
  col += prismEmission;
  filamentMask *= 1.0 - clamp(prismOcclusion, 0.0, 1.0);
  col = mix(col, col * 0.50 + vec3(0.040, 0.024, 0.010), filamentMask);

  float sheen = smoothstep(0.85, 0.0, abs(uv.x - uTilt * 0.85 + uv.y * 0.55));
  col += vec3(0.026, 0.032, 0.036) * sheen * 0.40;

  float g = hash(flipped + fract(uTime * 3.0) * vec2(37.0, 91.0));
  col *= 1.0 + (g - 0.5) * 0.075 * grainStrength;
  col += (g - 0.5) * 0.022 * grainStrength;

  col = col / (1.0 + col * 0.55);
  col = pow(max(col, 0.0), vec3(0.86));

  if (uPreviewOnly > 0.5) {
    vec3 preview = emission + prismEmission;
    preview = preview / (1.0 + preview * 0.55);
    preview = pow(max(preview, 0.0), vec3(0.86));
    float alpha = clamp(previewCoverage, 0.0, 1.0);
    fragColor = vec4(preview * alpha, alpha);
    return;
  }

  fragColor = vec4(col, 1.0);
}

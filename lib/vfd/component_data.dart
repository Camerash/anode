import 'dart:typed_data';
import 'dart:ui' as ui;

import 'prism_glyphs.dart';

/// Shader-side component type ids, mirrored in `vfd.frag`.
abstract final class ShaderType {
  static const double none = 0;
  static const double digits = 1;
  static const double bar = 2;
  static const double legend = 3;
  static const double prism = 4;
}

/// One component's data for one frame, already flattened to what the shader
/// needs. The model layer knows nothing about this; the renderer builds it.
class ComponentFrame {
  ComponentFrame({
    required this.type,
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    this.paramA = 0,
    this.paramB = 0,
    this.variantCode = 0,
    this.phosphorR = 0.30,
    this.phosphorG = 1.00,
    this.phosphorB = 0.72,
    this.emission = 1,
    this.bloom = 1,
    this.phosphorTexture = 0,
    this.grid = 1,
    this.unlit = 1,
    this.decay = 1,
    this.moduleCenterX = 0,
    this.moduleCenterY = 0,
    this.moduleWidth = 2.6,
    this.moduleHeight = 1,
    this.glassGrain = 1,
    this.filament = 1,
    this.prismLit = 0,
    this.prismPressed = 0,
    this.filamentVariantCode = 0,
    this.prismBevelDepth = 0.12,
    this.prismFaceOpacity = 0.78,
    this.prismInactiveLuminosity = 0.18,
    List<double>? prismGlyphs,
    List<double>? segments,
  }) : prismGlyphs = prismGlyphs ?? const <double>[],
       segments = segments ?? const <double>[];

  final double type;
  final double centerX;
  final double centerY;
  final double width;
  final double height;

  /// Type-specific: digit count, cell count, or the lit unit index.
  final double paramA;

  /// Type-specific: the bar's fill fraction.
  final double paramB;
  final double variantCode;
  final double phosphorR;
  final double phosphorG;
  final double phosphorB;
  final double emission;
  final double bloom;
  final double phosphorTexture;
  final double grid;
  final double unlit;
  final double decay;
  final double moduleCenterX;
  final double moduleCenterY;
  final double moduleWidth;
  final double moduleHeight;
  final double glassGrain;
  final double filament;
  final double prismLit;
  final double prismPressed;
  final double filamentVariantCode;
  final double prismBevelDepth;
  final double prismFaceOpacity;
  final double prismInactiveLuminosity;

  /// Normalised indices into the shared Prism glyph atlas.
  final List<double> prismGlyphs;

  /// Seven-segment brightness with a stride of eight — seven segments plus one
  /// spare for a future decimal point.
  final List<double> segments;
}

/// Packs component data into a small floating point texture.
///
/// Per-component parameters cannot be individual uniforms: four gauges would
/// exhaust the uniform budget. The shader samples this at exact texel centres,
/// which returns the stored value under either filter mode.
///
/// **Only RGB carries data. Alpha is always 1.** Image pixel formats are
/// premultiplied, so a texel storing a payload value in alpha comes back
/// scaled — or zeroed, when that value happens to be 0. Three floats per texel
/// is the price of using an image as a data buffer.
abstract final class ComponentData {
  static const int maxComponents = 16;
  static const int maxDigits = 4;

  /// **Everything stored must lie in [0, 1].** The texture keeps full float
  /// precision but is range-clamped, so a raw design-unit value above 1 comes
  /// back as exactly 1 and a negative one as 0. Unclamped, a component width of
  /// 1.035 read back as 1.0 and the bar's type id of 2 read back as 1, which
  /// rendered every gauge as a one-digit speed readout.
  ///
  /// Values already in [0, 1] — segment brightness, fill fractions — are stored
  /// raw so they keep every bit of precision. Mirrored in `vfd.frag`.
  static const double positionRange = 4.0;
  static const double sizeScale = 8.0;
  static const double typeScale = 8.0;
  static const double countScale = 64.0;
  static const double effectScale = 2.0;

  /// Signed, so it needs an offset as well as a scale.
  static double encodePosition(double v) =>
      _store(v / (2 * positionRange) + 0.5);

  static double encodeSize(double v) => _store(v / sizeScale);
  static double encodeType(double v) => _store(v / typeScale);
  static double encodeCount(double v) => _store(v / countScale);
  static double encodeEffect(double v) => _store(v / effectScale);

  /// Clamped so a component placed absurdly far out degrades to the edge of the
  /// representable range rather than wrapping into another field's value.
  static double _store(double v) => v.clamp(0.0, 1.0);

  /// texel 0: type, cx, cy
  /// texel 1: w, h, paramA
  /// texel 2: paramB, variant code, prism lit
  /// texel 3: phosphor r, g, b
  /// texel 4: emission, bloom, phosphor texture
  /// texel 5: grid, unlit phosphor, decay
  /// texel 6: module cx, cy, width
  /// texel 7: module height, glass grain, filament
  /// texel 8: prism pressed, filament variant code, spare
  /// texel 9: prism bevel, face opacity, inactive luminosity
  /// texel 10..21: digit segment payload, or up to 24 Prism glyph indices
  static const int headerTexels = 10;
  static const int texelsPerDigit = 3;
  static const int texelsPerComponent =
      headerTexels + maxDigits * texelsPerDigit;

  static const int floatsPerComponent = texelsPerComponent * 4;

  /// Stride of the segment brightness buffer, seven segments plus a spare.
  static const int segmentStride = 8;

  /// Builds the pixel buffer. Kept separate from [encode] so it can be asserted
  /// on directly in tests without an engine.
  static Float32List pack(List<ComponentFrame> frames) {
    final out = Float32List(maxComponents * floatsPerComponent);

    // Opaque everywhere, including unused rows, so nothing is ever scaled by a
    // premultiplied alpha on the way to the sampler.
    for (var i = 3; i < out.length; i += 4) {
      out[i] = 1.0;
    }

    final count = frames.length < maxComponents ? frames.length : maxComponents;
    for (var i = 0; i < count; i++) {
      final f = frames[i];
      final base = i * floatsPerComponent;
      final prismGlyphCount = f.prismGlyphs.length.clamp(
        0,
        PrismGlyphs.maxVisibleGlyphs,
      );

      out[base + 0] = encodeType(f.type);
      out[base + 1] = encodePosition(f.centerX);
      out[base + 2] = encodePosition(f.centerY);

      out[base + 4] = encodeSize(f.width);
      out[base + 5] = encodeSize(f.height);
      out[base + 6] = encodeCount(
        f.type == ShaderType.prism ? prismGlyphCount.toDouble() : f.paramA,
      );

      // Already a fraction in [0, 1]; stored raw.
      out[base + 8] = f.paramB;
      out[base + 9] = encodeCount(f.variantCode);
      out[base + 10] = encodeEffect(f.prismLit);

      out[base + 12] = _store(f.phosphorR);
      out[base + 13] = _store(f.phosphorG);
      out[base + 14] = _store(f.phosphorB);

      out[base + 16] = encodeEffect(f.emission);
      out[base + 17] = encodeEffect(f.bloom);
      out[base + 18] = encodeEffect(f.phosphorTexture);

      out[base + 20] = encodeEffect(f.grid);
      out[base + 21] = encodeEffect(f.unlit);
      out[base + 22] = encodeEffect(f.decay);

      out[base + 24] = encodePosition(f.moduleCenterX);
      out[base + 25] = encodePosition(f.moduleCenterY);
      out[base + 26] = encodeSize(f.moduleWidth);

      out[base + 28] = encodeSize(f.moduleHeight);
      out[base + 29] = encodeEffect(f.glassGrain);
      out[base + 30] = encodeEffect(f.filament);

      out[base + 32] = _store(f.prismPressed);
      out[base + 33] = encodeCount(f.filamentVariantCode);

      out[base + 36] = _store(f.prismBevelDepth);
      out[base + 37] = _store(f.prismFaceOpacity);
      out[base + 38] = _store(f.prismInactiveLuminosity);

      if (f.type == ShaderType.prism) {
        for (var glyph = 0; glyph < prismGlyphCount; glyph++) {
          final texel = base + (headerTexels + glyph ~/ 3) * 4;
          out[texel + glyph % 3] = _store(f.prismGlyphs[glyph]);
        }
      } else {
        for (var d = 0; d < maxDigits; d++) {
          final texel = base + (headerTexels + d * texelsPerDigit) * 4;
          for (var s = 0; s < 7; s++) {
            final source = d * segmentStride + s;
            final value = source < f.segments.length ? f.segments[source] : 0.0;
            // Three data slots per texel, so segment s lands in texel s ~/ 3.
            out[texel + (s ~/ 3) * 4 + (s % 3)] = value;
          }
        }
      }
    }
    return out;
  }

  /// Synchronous so the texture can be rebuilt inside the tick without async
  /// plumbing. Impeller only — Skia does not implement the sync path, which is
  /// why the precision probe is a device test rather than a headless one.
  static ui.Image encode(List<ComponentFrame> frames) {
    final floats = pack(frames);
    return ui.decodeImageFromPixelsSync(
      floats.buffer.asUint8List(),
      texelsPerComponent,
      maxComponents,
      ui.PixelFormat.rgbaFloat32,
    );
  }
}

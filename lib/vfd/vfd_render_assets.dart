import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Immutable GPU inputs shared by every cluster preview and runtime surface.
///
/// Loading once avoids decoding a glyph atlas for every editor or Library
/// preview. The owning app disposes the decoded image at shutdown.
class VfdRenderAssets {
  VfdRenderAssets({required this.program, required this.prismGlyphAtlas});

  final ui.FragmentProgram program;
  final ui.Image prismGlyphAtlas;

  static Future<VfdRenderAssets> load() async {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(<String>[
        'Barlow Condensed',
      ], await rootBundle.loadString('assets/fonts/OFL-Barlow.txt'));
    });
    final program = await ui.FragmentProgram.fromAsset('shaders/vfd.frag');
    final bytes = await rootBundle.load('assets/shaders/prism_glyph_sdf.png');
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return VfdRenderAssets(program: program, prismGlyphAtlas: frame.image);
  }

  void dispose() => prismGlyphAtlas.dispose();
}

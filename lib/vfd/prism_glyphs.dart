/// Glyph contract shared by Flutter controls, component packing, and vfd.frag.
///
/// Persisted labels are never rewritten. This codec only defines their
/// deterministic visual fallback in the two Prism renderers.
abstract final class PrismGlyphs {
  static const String characters =
      ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/.-+%?';
  static const int maxVisibleGlyphs = 24;
  static const int atlasColumns = 8;
  static const int atlasRows = 6;

  static String displayText(String source) {
    final upper = source.trim().toUpperCase().runes.toList(growable: false);
    final truncated = upper.length <= maxVisibleGlyphs
        ? upper
        : <int>[...upper.take(maxVisibleGlyphs - 3), ...'...'.runes];
    return String.fromCharCodes(
      truncated.map((rune) {
        final character = String.fromCharCode(rune);
        return characters.contains(character) ? rune : '?'.codeUnitAt(0);
      }),
    );
  }

  static List<double> encode(String source) {
    final display = displayText(source);
    final divisor = characters.length - 1;
    return <double>[
      for (final rune in display.runes)
        characters.indexOf(String.fromCharCode(rune)) / divisor,
    ];
  }
}

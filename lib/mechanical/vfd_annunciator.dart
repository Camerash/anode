import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';

class VfdAnnunciator extends StatelessWidget {
  const VfdAnnunciator({
    super.key,
    required this.message,
    required this.palette,
    required this.onAcknowledge,
    this.prismStyle = const PrismStyle(),
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final String message;
  final VfdPalette palette;
  final VoidCallback onAcknowledge;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF07100C),
        border: Border.all(color: palette.lit.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: VfdLegend(message, palette: palette, lit: true, size: 10),
            ),
            const SizedBox(width: 8),
            PrismButton(
              label: 'ACK',
              palette: palette,
              role: PrismRole.compact,
              style: prismStyle,
              onPressed: onAcknowledge,
            ),
          ],
        ),
      ),
    ),
  );
}

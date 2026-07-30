import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';

/// Indexed automotive channel selector.
///
/// Previous and next labels remain visible around the active channel so a
/// service control is discoverable without a grid or kinetic scrolling.
class MechanicalChannelDrum extends StatelessWidget {
  const MechanicalChannelDrum({
    super.key,
    required this.labels,
    required this.index,
    required this.palette,
    required this.prismStyle,
    required this.onChanged,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.semanticLabel = 'Channel selector',
  }) : assert(labels.length > 0),
       assert(index >= 0),
       assert(index < labels.length);

  final List<String> labels;
  final int index;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final ValueChanged<int> onChanged;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final String semanticLabel;

  bool get _canPrevious => index > 0;
  bool get _canNext => index + 1 < labels.length;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    value: '${index + 1} of ${labels.length}, ${labels[index]}',
    increasedValue: _canNext ? labels[index + 1] : null,
    decreasedValue: _canPrevious ? labels[index - 1] : null,
    onIncrease: _canNext ? () => onChanged(index + 1) : null,
    onDecrease: _canPrevious ? () => onChanged(index - 1) : null,
    child: FocusableActionDetector(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            if (intent.direction == TraversalDirection.left ||
                intent.direction == TraversalDirection.up) {
              if (_canPrevious) onChanged(index - 1);
            } else if (intent.direction == TraversalDirection.right ||
                intent.direction == TraversalDirection.down) {
              if (_canNext) onChanged(index + 1);
            }
            return null;
          },
        ),
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          if (event.scrollDelta.dy > 0 && _canNext) {
            onChanged(index + 1);
          } else if (event.scrollDelta.dy < 0 && _canPrevious) {
            onChanged(index - 1);
          }
        },
        child: SizedBox(
          height: 76,
          child: Row(
            children: <Widget>[
              _stepButton(
                key: const ValueKey('service-effect-previous'),
                label: 'Previous',
                enabled: _canPrevious,
                onPressed: () => onChanged(index - 1),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF030504),
                    border: Border.all(
                      color: palette.unlit.withValues(alpha: 0.52),
                    ),
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DrumFacePainter(palette: palette),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _label(index - 1, size: 8),
                            const SizedBox(height: 2),
                            _label(index, lit: true, size: 13),
                            const SizedBox(height: 2),
                            _label(index + 1, size: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),
              _stepButton(
                key: const ValueKey('service-effect-next'),
                label: 'Next',
                enabled: _canNext,
                onPressed: () => onChanged(index + 1),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _label(int labelIndex, {bool lit = false, required double size}) {
    final text = labelIndex >= 0 && labelIndex < labels.length
        ? labels[labelIndex]
        : '—';
    return VfdLegend(text, palette: palette, lit: lit, size: size);
  }

  Widget _stepButton({
    required Key key,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) => PrismButton(
    key: key,
    label: label,
    palette: palette,
    enabled: enabled,
    role: PrismRole.compact,
    style: prismStyle,
    soundEnabled: soundEnabled,
    hapticsEnabled: hapticsEnabled,
    onPressed: enabled ? onPressed : null,
  );
}

class _DrumFacePainter extends CustomPainter {
  const _DrumFacePainter({required this.palette});

  final VfdPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF77817C).withValues(alpha: 0.22)
      ..strokeWidth = 1;
    canvas
      ..drawLine(
        Offset(4, size.height / 3),
        Offset(size.width - 4, size.height / 3),
        paint,
      )
      ..drawLine(
        Offset(4, size.height * 2 / 3),
        Offset(size.width - 4, size.height * 2 / 3),
        paint,
      );
    final active = Paint()
      ..color = palette.lit.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTRB(
        3,
        size.height / 3 + 1,
        size.width - 3,
        size.height * 2 / 3 - 1,
      ),
      active,
    );
  }

  @override
  bool shouldRepaint(covariant _DrumFacePainter oldDelegate) =>
      oldDelegate.palette != palette;
}

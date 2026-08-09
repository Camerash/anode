import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';

typedef MechanicalCarouselLabel<T> = String Function(T item);
typedef MechanicalCarouselItemBuilder<T> =
    Widget Function(BuildContext context, T item, bool selected, double size);

/// Reusable indexed mechanical carousel with visible neighbouring detents.
class MechanicalCarousel<T> extends StatefulWidget {
  const MechanicalCarousel({
    super.key,
    required this.items,
    required this.index,
    required this.labelFor,
    required this.palette,
    required this.prismStyle,
    required this.onChanged,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.semanticLabel = 'Carousel selector',
    this.duration = const Duration(milliseconds: 180),
    this.previousKey = const ValueKey('mechanical-carousel-previous'),
    this.nextKey = const ValueKey('mechanical-carousel-next'),
    this.itemBuilder,
  }) : assert(items.length > 0),
       assert(index >= 0),
       assert(index < items.length);

  final List<T> items;
  final int index;
  final MechanicalCarouselLabel<T> labelFor;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final ValueChanged<int> onChanged;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final String semanticLabel;
  final Duration duration;
  final Key previousKey;
  final Key nextKey;
  final MechanicalCarouselItemBuilder<T>? itemBuilder;

  @override
  State<MechanicalCarousel<T>> createState() => _MechanicalCarouselState<T>();
}

class _MechanicalCarouselState<T> extends State<MechanicalCarousel<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  )..addListener(_tick);

  late double _from = widget.index.toDouble();
  late double _to = widget.index.toDouble();

  bool get _canPrevious => widget.index > 0;
  bool get _canNext => widget.index + 1 < widget.items.length;

  double get _position => lerpDouble(_from, _to, _controller.value) ?? _to;

  @override
  void didUpdateWidget(covariant MechanicalCarousel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.index != widget.index) {
      _from = _position;
      _to = widget.index.toDouble();
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if ((MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        _controller.value != 1) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    value:
        '${widget.index + 1} of ${widget.items.length}, '
        '${widget.labelFor(widget.items[widget.index])}',
    increasedValue: _canNext
        ? widget.labelFor(widget.items[widget.index + 1])
        : null,
    decreasedValue: _canPrevious
        ? widget.labelFor(widget.items[widget.index - 1])
        : null,
    onIncrease: _canNext ? () => widget.onChanged(widget.index + 1) : null,
    onDecrease: _canPrevious ? () => widget.onChanged(widget.index - 1) : null,
    child: FocusableActionDetector(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            if (intent.direction == TraversalDirection.left ||
                intent.direction == TraversalDirection.up) {
              if (_canPrevious) widget.onChanged(widget.index - 1);
            } else if (intent.direction == TraversalDirection.right ||
                intent.direction == TraversalDirection.down) {
              if (_canNext) widget.onChanged(widget.index + 1);
            }
            return null;
          },
        ),
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          if (event.scrollDelta.dy > 0 && _canNext) {
            widget.onChanged(widget.index + 1);
          } else if (event.scrollDelta.dy < 0 && _canPrevious) {
            widget.onChanged(widget.index - 1);
          }
        },
        child: SizedBox(
          height: 76,
          child: Row(
            children: <Widget>[
              Expanded(child: _face()),
              const SizedBox(width: 5),
              SizedBox(
                width: PrismMetrics.height(PrismRole.micro),
                height: 76,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _stepButton(
                      key: widget.previousKey,
                      label: 'Previous',
                      shape: PrismShape.triangleUp,
                      enabled: _canPrevious,
                      onPressed: () => widget.onChanged(widget.index - 1),
                    ),
                    _stepButton(
                      key: widget.nextKey,
                      label: 'Next',
                      shape: PrismShape.triangleDown,
                      enabled: _canNext,
                      onPressed: () => widget.onChanged(widget.index + 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _face() => DecoratedBox(
    key: const ValueKey('mechanical-carousel-face'),
    decoration: BoxDecoration(
      color: const Color(0xFF030504),
      border: Border.all(color: widget.palette.unlit.withValues(alpha: 0.52)),
    ),
    child: Stack(
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _CarouselFacePainter(palette: widget.palette),
          ),
        ),
        Positioned.fill(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                for (var index = 0; index < widget.items.length; index++)
                  if ((index - _position).abs() < 1.8) _carouselLabel(index),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _carouselLabel(int index) {
    final distance = index - _position;
    final absolute = distance.abs();
    final opacity = (1 - absolute * 0.68).clamp(0.0, 1.0);
    final size = lerpDouble(13, 8, math.min(1, absolute))!;
    final item = widget.items[index];
    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(0, distance * 22),
        child: Opacity(
          key: ValueKey('mechanical-carousel-item-$index'),
          opacity: opacity,
          child:
              widget.itemBuilder?.call(
                context,
                item,
                index == widget.index,
                size,
              ) ??
              Center(
                child: VfdLegend(
                  widget.labelFor(item),
                  palette: widget.palette,
                  lit: index == widget.index,
                  size: size,
                ),
              ),
        ),
      ),
    );
  }

  Widget _stepButton({
    required Key key,
    required String label,
    required PrismShape shape,
    required bool enabled,
    required VoidCallback onPressed,
  }) => PrismButton(
    key: key,
    label: label,
    face: const SizedBox.shrink(),
    shape: shape,
    square: true,
    palette: widget.palette,
    enabled: enabled,
    role: PrismRole.micro,
    style: widget.prismStyle,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    onPressed: enabled ? onPressed : null,
  );

  void _tick() {
    if (mounted) setState(() {});
  }
}

/// Effect-channel compatibility surface with stable test and semantics keys.
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

  @override
  Widget build(BuildContext context) => MechanicalCarousel<String>(
    items: labels,
    index: index,
    labelFor: (label) => label,
    palette: palette,
    prismStyle: prismStyle,
    soundEnabled: soundEnabled,
    hapticsEnabled: hapticsEnabled,
    semanticLabel: semanticLabel,
    previousKey: const ValueKey('service-effect-previous'),
    nextKey: const ValueKey('service-effect-next'),
    onChanged: onChanged,
  );
}

class _CarouselFacePainter extends CustomPainter {
  const _CarouselFacePainter({required this.palette});

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
  bool shouldRepaint(covariant _CarouselFacePainter oldDelegate) =>
      oldDelegate.palette != palette;
}

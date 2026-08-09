import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';
import 'mechanical_feedback.dart';

class MechanicalPagerController extends ChangeNotifier {
  MechanicalPagerController({int initialPage = 0}) : _page = initialPage;

  int _page;
  int get page => _page;

  void jumpTo(int value) {
    if (_page == value) return;
    _page = value;
    notifyListeners();
  }
}

/// Fixed indexed content plus a detented rail. No Scrollable participates.
class MechanicalPager extends StatefulWidget {
  const MechanicalPager({
    super.key,
    required this.pages,
    required this.palette,
    required this.prismStyle,
    this.controller,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.semanticLabel = 'Page',
    this.showButtons = true,
  });

  final List<Widget> pages;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final MechanicalPagerController? controller;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final String semanticLabel;
  final bool showButtons;

  @override
  State<MechanicalPager> createState() => _MechanicalPagerState();
}

class _MechanicalPagerState extends State<MechanicalPager> {
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _page = _bounded(widget.controller?.page ?? 0);
    widget.controller?.addListener(_readController);
  }

  @override
  void didUpdateWidget(covariant MechanicalPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_readController);
      widget.controller?.addListener(_readController);
    }
    final bounded = _bounded(_page);
    if (bounded != _page) _page = bounded;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_readController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    return Row(
      children: <Widget>[
        Expanded(
          child: IndexedStack(
            key: const ValueKey('mechanical-pages'),
            index: _page,
            sizing: StackFit.expand,
            children: widget.pages,
          ),
        ),
        if (widget.pages.length > 1) ...<Widget>[
          const SizedBox(width: 8),
          SizedBox(width: 54, child: _controls(context)),
        ],
      ],
    );
  }

  Widget _controls(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final buttons = widget.showButtons && constraints.maxHeight >= 112;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (buttons)
            Transform.scale(
              scale: 0.78,
              child: PrismButton(
                key: const ValueKey('pager-previous'),
                label: 'Previous page',
                face: const SizedBox.shrink(),
                shape: PrismShape.triangleUp,
                square: true,
                palette: widget.palette,
                role: PrismRole.micro,
                style: widget.prismStyle,
                enabled: _page > 0,
                soundEnabled: false,
                hapticsEnabled: false,
                onPressed: _page > 0 ? () => _setPage(_page - 1) : null,
              ),
            ),
          Expanded(child: _rail(context)),
          if (buttons)
            Transform.scale(
              scale: 0.78,
              child: PrismButton(
                key: const ValueKey('pager-next'),
                label: 'Next page',
                face: const SizedBox.shrink(),
                shape: PrismShape.triangleDown,
                square: true,
                palette: widget.palette,
                role: PrismRole.micro,
                style: widget.prismStyle,
                enabled: _page < widget.pages.length - 1,
                soundEnabled: false,
                hapticsEnabled: false,
                onPressed: _page < widget.pages.length - 1
                    ? () => _setPage(_page + 1)
                    : null,
              ),
            ),
        ],
      );
    },
  );

  Widget _rail(BuildContext context) => Semantics(
    slider: true,
    label: widget.semanticLabel,
    value: '${_page + 1} of ${widget.pages.length}',
    increasedValue: _page < widget.pages.length - 1
        ? '${_page + 2} of ${widget.pages.length}'
        : null,
    decreasedValue: _page > 0 ? '$_page of ${widget.pages.length}' : null,
    onIncrease: _page < widget.pages.length - 1
        ? () => _setPage(_page + 1)
        : null,
    onDecrease: _page > 0 ? () => _setPage(_page - 1) : null,
    child: FocusableActionDetector(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            if (intent.direction == TraversalDirection.up) {
              _setPage(_page - 1);
            } else if (intent.direction == TraversalDirection.down) {
              _setPage(_page + 1);
            }
            return null;
          },
        ),
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Listener(
          key: const ValueKey('pager-detent-rail'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) =>
              _setFromRail(event.localPosition.dy, constraints.maxHeight),
          onPointerMove: (event) =>
              _setFromRail(event.localPosition.dy, constraints.maxHeight),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _page.toDouble()),
            duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
                ? Duration.zero
                : const Duration(milliseconds: 60),
            builder: (context, position, _) => CustomPaint(
              painter: _DetentRailPainter(
                palette: widget.palette,
                position: position,
                count: widget.pages.length,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _setFromRail(double dy, double height) {
    final fraction = height <= 0 ? 0.0 : (dy / height).clamp(0.0, 1.0);
    _setPage((fraction * (widget.pages.length - 1)).round());
  }

  void _setPage(int value, {bool feedback = true}) {
    final next = _bounded(value);
    if (next == _page) return;
    setState(() => _page = next);
    widget.controller?.jumpTo(next);
    if (feedback) {
      actuateMechanicalFeedback(
        soundEnabled: widget.soundEnabled,
        hapticsEnabled: widget.hapticsEnabled,
      );
    }
  }

  int _bounded(int value) =>
      value.clamp(0, math.max(0, widget.pages.length - 1));

  void _readController() {
    final next = _bounded(widget.controller!.page);
    if (next != _page && mounted) setState(() => _page = next);
  }
}

class _DetentRailPainter extends CustomPainter {
  const _DetentRailPainter({
    required this.palette,
    required this.position,
    required this.count,
  });

  final VfdPalette palette;
  final double position;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = Paint()
      ..color = palette.unlit.withValues(alpha: 0.28)
      ..strokeWidth = 2;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 7), Offset(x, size.height - 7), rail);
    for (var i = 0; i < count; i++) {
      final y = count == 1
          ? size.height / 2
          : 7 + i * (size.height - 14) / (count - 1);
      canvas.drawLine(Offset(x - 7, y), Offset(x + 7, y), rail);
    }
    final y = count == 1
        ? size.height / 2
        : 7 + position * (size.height - 14) / (count - 1);
    final carriage = Paint()
      ..color = palette.lit
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(x, y), width: 20, height: 12),
      carriage,
    );
  }

  @override
  bool shouldRepaint(covariant _DetentRailPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.count != count ||
      oldDelegate.palette != palette;
}

List<List<T>> paginateCompleteRows<T>(
  List<T> items, {
  required int columns,
  required int rows,
}) {
  final capacity = math.max(1, columns * rows);
  return <List<T>>[
    for (var start = 0; start < items.length; start += capacity)
      items.sublist(start, math.min(start + capacity, items.length)),
  ];
}

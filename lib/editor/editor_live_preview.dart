import 'package:flutter/widgets.dart';

import '../model/dashboard.dart';
import '../model/placement.dart';
import '../vfd/vfd_cluster.dart';
import '../vfd/vfd_render_assets.dart';

/// One shared live renderer for editor previews.
///
/// Catalogue screens must reuse one cradle instead of creating a fragment pass
/// and animation controller for every row.
class EditorLiveVfdPreview extends StatefulWidget {
  const EditorLiveVfdPreview({
    super.key,
    required this.renderAssets,
    required this.dashboard,
    required this.orientation,
    this.frameInsets = EdgeInsets.zero,
    this.clipRect,
    this.transparentBackground = false,
  });

  final VfdRenderAssets renderAssets;
  final Dashboard dashboard;
  final DesignOrientation orientation;
  final EdgeInsets frameInsets;

  /// Optional local viewport for an otherwise full-size VFD render.
  final Rect? clipRect;
  final bool transparentBackground;

  @override
  State<EditorLiveVfdPreview> createState() => _EditorLiveVfdPreviewState();
}

class _EditorLiveVfdPreviewState extends State<EditorLiveVfdPreview>
    with SingleTickerProviderStateMixin {
  late final VfdController _controller = VfdController(
    vsync: this,
    design: widget.dashboard,
    orientation: widget.orientation,
  )..speedKph = 95;

  @override
  void didUpdateWidget(covariant EditorLiveVfdPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..design = widget.dashboard
      ..orientation = widget.orientation;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VfdCluster(
    renderAssets: widget.renderAssets,
    controller: _controller,
    frameInsets: widget.frameInsets,
    clipRect: widget.clipRect,
    transparentBackground: widget.transparentBackground,
  );
}

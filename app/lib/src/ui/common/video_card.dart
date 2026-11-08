import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../features/youtube/youtube_results.dart' show VideoTile;
import '../../theme.dart';
import '../desktop/focus_ring.dart';
import '../tv/focus_card.dart';
import 'dims.dart';
import 'glass.dart';
import 'motion_kit.dart';
import 'tokens.dart';

/// The line under a video's title: channel and views, whichever are known.
/// (YouTube's lists carry no upload date in the fields Chithram keeps.)
String videoMeta(VideoItem v, {String separator = '  ·  '}) =>
    [v.author, v.viewsText].where((s) => s.isNotEmpty).join(separator);

/// The corner badge on a thumbnail: a red LIVE with a dot, else the length.
/// Nothing for a video of unknown length.
class VideoBadge extends StatelessWidget {
  const VideoBadge({super.key, required this.item});

  final VideoItem item;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final duration = item.duration;
    if (!item.isLive && duration == null) return const SizedBox.shrink();
    final style = TextStyle(
      color: Colors.white,
      fontSize: d.t(12),
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: item.isLive ? 0.6 : 0,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        // YouTube's own live red: it reads as "live" in any theme.
        color: item.isLive ? const Color(0xFFE5252A) : Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(Space.s4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.isLive) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(item.isLive ? 'LIVE' : VideoTile.clock(duration!), style: style),
        ],
      ),
    );
  }
}

/// A video's thumbnail, cropped to fill, fading in as it arrives; the
/// YouTube glyph when there is none or it fails.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({super.key, required this.item, this.cacheWidth = 640, this.iconSize = 40});

  final VideoItem item;
  final int cacheWidth;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final url = VideoTile.thumbnailUrl(item.thumbnails);
    final glyph = Center(
      child: Icon(Icons.smart_display_rounded, size: iconSize, color: c.textDim),
    );
    if (url == null) return glyph;
    final fade = Motion.of(context).expandTime;
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      // A cached image shows at once; a downloaded one fades in rather than popping.
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: fade,
              curve: Motion.curve,
              child: child,
            ),
      errorBuilder: (_, _, _) => glyph,
    );
  }
}

/// A desktop video card: 16:9 thumbnail with the length or LIVE, title, then
/// channel and views. Hover (or keyboard focus) lifts the card with a soft
/// shadow, slowly zooms the frame, shades it and brings up a Play glyph and,
/// with [onDetails], a details button: a hint of what pressing will do.
class VideoCard extends StatefulWidget {
  const VideoCard({
    super.key,
    required this.item,
    required this.onOpen,
    this.progress,
    this.focus,
    this.onDetails,
    this.focusNode,
  });

  final VideoItem item;
  final VoidCallback onOpen;

  /// How far it was watched (0 to 1); Continue watching only.
  final double? progress;
  final SectionFocus? focus;

  /// Opens the details sheet; no details button when null.
  final VoidCallback? onDetails;
  final FocusNode? focusNode;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  FocusNode? _own;
  bool _hovered = false;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'video card'));

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _onFocus(bool f) {
    if (!mounted) return;
    setState(() => _focused = f);
    if (f) {
      widget.focus?.remember(_node);
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: Motion.of(context).focusTime,
        curve: Motion.curve,
      );
    }
  }

  void _open() {
    _node.requestFocus();
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final d = Dims.of(context);
    final type = d.type;
    final motion = Motion.of(context);
    final item = widget.item;
    final active = _hovered || _focused;
    final radius = Radii.card(d.form);
    final meta = videoMeta(item);
    final progress = widget.progress;
    return Semantics(
      button: true,
      label: item.title,
      onTap: _open,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: _node,
        onFocusChange: _onFocus,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onOpen();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _open,
            child: FocusRing(
              focused: _focused,
              radius: radius,
              child: AnimatedContainer(
                duration: motion.expandTime,
                curve: Motion.curve,
                // Lifts 4 dp, and the surface lightens 4%, on hover.
                transform: Matrix4.translationValues(0, active ? -4 : 0, 0),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(Colors.white.withValues(alpha: active ? 0.04 : 0), c.surface),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: active ? c.text.withValues(alpha: 0.16) : c.hairline),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: active ? 0.38 : 0),
                      blurRadius: active ? 28 : 0,
                      offset: Offset(0, active ? 12 : 0),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(radius - 1)),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(color: c.surfaceHigh),
                            // A slow push-in while pointed at: the preview feel.
                            AnimatedScale(
                              scale: active ? 1.07 : 1,
                              duration: active ? const Duration(milliseconds: 1600) : motion.expandTime,
                              curve: Curves.easeOutCubic,
                              child: VideoThumbnail(item: item),
                            ),
                            // Shade so the glyph and badge stand out of any frame.
                            AnimatedOpacity(
                              opacity: active ? 1 : 0,
                              duration: motion.focusTime,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.05),
                                      Colors.black.withValues(alpha: 0.55),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: AnimatedOpacity(
                                opacity: active ? 1 : 0,
                                duration: motion.focusTime,
                                child: AnimatedScale(
                                  scale: active ? 1 : 0.7,
                                  duration: motion.focusTime,
                                  curve: Curves.easeOutBack,
                                  child: Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: c.accent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(color: c.accent.withValues(alpha: 0.45), blurRadius: 20),
                                      ],
                                    ),
                                    child: Icon(Icons.play_arrow_rounded, size: 32, color: c.onAccent),
                                  ),
                                ),
                              ),
                            ),
                            if (widget.onDetails != null)
                              Positioned(
                                top: Space.s8,
                                right: Space.s8,
                                child: AnimatedOpacity(
                                  opacity: active ? 1 : 0,
                                  duration: motion.focusTime,
                                  child: IgnorePointer(
                                    ignoring: !active,
                                    child: _DetailsButton(onPressed: widget.onDetails!),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: Space.s8,
                              bottom: progress == null ? Space.s8 : Space.s12,
                              child: VideoBadge(item: item),
                            ),
                            if (progress != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: WatchProgress(fraction: progress, height: 4),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Space.s12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: type.card.copyWith(height: 1.3),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: Space.s4),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.meta.copyWith(color: c.textDim),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailsButton extends StatelessWidget {
  const _DetailsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Details',
    onTap: onPressed,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.info_outline_rounded, size: 18, color: Colors.white),
      ),
    ),
  );
}

/// The skeleton of a [VideoCard] (or a TV tile) while a list loads: a 16:9
/// block and two text lines.
class VideoCardSkeleton extends StatelessWidget {
  const VideoCardSkeleton({super.key, this.thumbnailHeight});

  /// Fixed thumbnail height; 16:9 of the width when null.
  final double? thumbnailHeight;

  @override
  Widget build(BuildContext context) {
    final radius = Radii.card(Dims.of(context).form);
    final thumb = SkeletonBox(radius: radius);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (thumbnailHeight != null)
          SizedBox(height: thumbnailHeight, width: double.infinity, child: thumb)
        else
          AspectRatio(aspectRatio: 16 / 9, child: thumb),
        const SizedBox(height: Space.s12),
        const FractionallySizedBox(widthFactor: 0.9, child: SkeletonBox(height: 14, radius: 6)),
        const SizedBox(height: Space.s8),
        const FractionallySizedBox(widthFactor: 0.55, child: SkeletonBox(height: 12, radius: 6)),
      ],
    );
  }
}

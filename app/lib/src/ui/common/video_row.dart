import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../features/youtube/feed/youtube_feed.dart';
import '../../theme.dart';
import '../desktop/focus_ring.dart';
import '../tv/focus_card.dart';
import 'dims.dart';
import 'tokens.dart';
import 'video_card.dart';

// A paged row of video cards for the desktop (Home, the YouTube section):
// a title, VIEW ALL, and chevrons that page through the rail [perRow] at a
// time. The new page slides in from the side it was paged toward.

/// A titled row of [VideoCard]s that pages [perRow] at a time.
class VideoRow extends StatefulWidget {
  const VideoRow({
    super.key,
    required this.rail,
    required this.perRow,
    required this.focus,
    required this.onOpen,
    this.onViewAll,
    this.onDetails,
  });

  final FeedRail rail;
  final int perRow;
  final SectionFocus focus;
  final void Function(VideoItem) onOpen;

  /// VIEW ALL; not shown when null.
  final VoidCallback? onViewAll;

  /// Each card's details button; none when null.
  final void Function(VideoItem)? onDetails;

  @override
  State<VideoRow> createState() => _VideoRowState();
}

class _VideoRowState extends State<VideoRow> {
  int _page = 0;

  /// +1 after paging forward, -1 after paging back: where the new page enters.
  int _direction = 1;

  int get _pages => math.max(1, (widget.rail.items.length / widget.perRow).ceil());

  void _turn(int to) => setState(() {
    _direction = to > _page ? 1 : -1;
    _page = to;
  });

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final type = Dims.of(context).type;
    final items = widget.rail.items;
    final page = math.min(_page, _pages - 1);
    final first = page * widget.perRow;
    final shown = items.skip(first).take(widget.perRow).toList();
    final onDetails = widget.onDetails;
    final pageKey = ValueKey('${widget.rail.id}-$page-${widget.perRow}');
    return Padding(
      padding: const EdgeInsets.only(top: Space.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.rail.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: type.row),
              ),
              if (widget.onViewAll != null) ...[
                _TextLink(label: 'VIEW ALL ›', onPressed: widget.onViewAll!),
                const SizedBox(width: Space.s12),
              ],
              _Chevron(
                key: ValueKey('row-prev-${widget.rail.id}'),
                label: 'Previous videos',
                icon: Icons.chevron_left_rounded,
                onPressed: page > 0 ? () => _turn(page - 1) : null,
              ),
              const SizedBox(width: Space.s8),
              _Chevron(
                key: ValueKey('row-next-${widget.rail.id}'),
                label: 'Next videos',
                icon: Icons.chevron_right_rounded,
                onPressed: page < _pages - 1 ? () => _turn(page + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: Space.s16),
          AnimatedSwitcher(
            duration: Motion.of(context).expandTime,
            switchInCurve: Motion.curve,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
            transitionBuilder: (child, a) {
              // The incoming page enters from the paging side; the old one
              // leaves toward the other. Both carry their key, so compare.
              final incoming = child.key == pageKey;
              final dx = 0.06 * _direction * (incoming ? 1 : -1);
              return FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a),
                  child: child,
                ),
              );
            },
            child: Row(
              key: pageKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.perRow; i++) ...[
                  if (i > 0) const SizedBox(width: Space.s16),
                  Expanded(
                    child: i < shown.length
                        ? VideoCard(
                            item: shown[i],
                            progress: widget.rail.progress[shown[i].videoId],
                            focus: widget.focus,
                            onOpen: () => widget.onOpen(shown[i]),
                            onDetails: onDetails == null ? null : () => onDetails(shown[i]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
          if (_pages > 1)
            Padding(
              padding: const EdgeInsets.only(top: Space.s8),
              child: Text('${page + 1} / $_pages', style: type.meta.copyWith(color: c.textDim)),
            ),
        ],
      ),
    );
  }
}

class _TextLink extends StatefulWidget {
  const _TextLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<_TextLink> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    return Semantics(
      button: true,
      label: 'View all',
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: FocusableActionDetector(
        onFocusChange: (f) => setState(() => _focused = f),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: FocusRing(
              focused: _focused,
              radius: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s8, vertical: Space.s4),
                child: Text(
                  widget.label,
                  style: Dims.of(context).type.overline.copyWith(color: _hovered ? c.text : c.textDim),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chevron extends StatefulWidget {
  const _Chevron({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_Chevron> createState() => _ChevronState();
}

class _ChevronState extends State<_Chevron> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        onFocusChange: (f) => setState(() => _focused = f),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: FocusRing(
              focused: _focused,
              radius: 16,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hovered && enabled ? c.text.withValues(alpha: 0.08) : Colors.transparent,
                  border: Border.all(color: c.text.withValues(alpha: enabled ? 0.28 : 0.12)),
                ),
                child: Icon(widget.icon, size: 20, color: c.text.withValues(alpha: enabled ? 1 : 0.3)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../core/services.dart';
import '../../features/youtube/feed/youtube_feed.dart';
import '../../features/youtube/youtube_results.dart';
import '../../theme.dart';
import '../common/dims.dart';
import '../common/glass.dart';
import '../common/sections.dart';
import '../common/tokens.dart';
import '../tv/focus_card.dart';
import 'focus_ring.dart';

/// How many cards a row shows at this window width: 4 from 1440, 3 from 1100.
int cardsPerRow(double width) => width >= 1440 ? 4 : (width >= 1100 ? 3 : 2);

/// How long the hero stays on a slide.
const heroAutoAdvance = Duration(seconds: 8);

/// Desktop Home: a hero billboard and rows of videos from the same feed the
/// TV and phone Home use (popular now, and, as Chithram learns, continue
/// watching and suggestions).
class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key, required this.focus, required this.onOpenSection});

  final SectionFocus focus;

  /// "Browse YouTube" and "View all" go to a section.
  final void Function(Section) onOpenSection;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  @override
  void initState() {
    super.initState();
    // After the first frame: nothing on the startup path reads the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppServices.of(context).feed.open());
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = AppServices.of(context).feed;
    final d = Dims.of(context);
    final perRow = cardsPerRow(MediaQuery.sizeOf(context).width);
    return ValueListenableBuilder<FeedState>(
      valueListenable: feed.state,
      builder: (context, state, _) => SingleChildScrollView(
        key: const PageStorageKey<String>('desktop-home-scroll'),
        padding: EdgeInsets.fromLTRB(d.gutter, Space.s24, d.gutter, Space.s32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Hero(
              focus: widget.focus,
              state: state,
              onRetry: () => feed.refresh(force: true),
              onBrowse: () => widget.onOpenSection(Section.youtube),
            ),
            for (final rail in state.rails)
              _Row(
                key: ValueKey('home-${rail.id}'),
                rail: rail,
                perRow: perRow,
                focus: widget.focus,
                onViewAll: () => widget.onOpenSection(Section.youtube),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- hero

class _Hero extends StatefulWidget {
  const _Hero({required this.focus, required this.state, required this.onRetry, required this.onBrowse});

  final SectionFocus focus;
  final FeedState state;
  final VoidCallback onRetry;
  final VoidCallback onBrowse;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  int _page = 0;
  bool _hovered = false;
  bool _focusWithin = false;
  bool _reduced = false;
  Timer? _timer;

  List<VideoItem> get _items => widget.state.hero.take(5).toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = Motion.of(context).reduced;
    _schedule();
  }

  @override
  void didUpdateWidget(_Hero old) {
    super.didUpdateWidget(old);
    if (_page >= _items.length) _page = 0;
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Advances every [heroAutoAdvance]; paused while the pointer or focus is on
  /// the hero, and off when the system asks for no animation.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_items.length < 2 || _hovered || _focusWithin || _reduced) return;
    _timer = Timer.periodic(heroAutoAdvance, (_) {
      if (mounted) setState(() => _page = (_page + 1) % _items.length);
    });
  }

  void _go(int i) {
    setState(() => _page = i);
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final type = d.type;
    final items = _items;
    final VideoItem? video = items.isEmpty ? null : items[math.min(_page, items.length - 1)];
    final suggested = widget.state.rails.any((r) => r.id == 'for-you');
    final error = widget.state.error;
    final height = (MediaQuery.sizeOf(context).height * 0.42).clamp(300.0, 440.0);

    final String label, title;
    final facts = <String>[];
    if (video != null) {
      label = suggested ? 'Recommended for you' : 'Popular on YouTube';
      title = video.title;
      final duration = video.duration;
      facts.addAll([
        video.author,
        video.viewsText,
        if (duration != null) VideoTile.clock(duration),
      ].where((s) => s.isNotEmpty));
    } else if (error != null) {
      (label, title) = ('YouTube', error);
      facts.add('Check the connection, then retry.');
    } else {
      (label, title) = ('YouTube', 'Loading what is popular…');
    }

    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _schedule();
      },
      onExit: (_) {
        _hovered = false;
        _schedule();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (has) {
          _focusWithin = has;
          _schedule();
        },
        child: Container(
          key: const ValueKey('desktop-hero'),
          width: double.infinity,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.hero),
            border: Border.all(color: c.glassEdge),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [c.heroTint, c.surface, c.background],
            ),
          ),
          child: Stack(
            children: [
              if (video != null) ...[
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: Motion.of(context).heroTime,
                    child: KeyedSubtree(
                      key: ValueKey(video.videoId),
                      child: SizedBox.expand(child: HeroImage(videoId: video.videoId)),
                    ),
                  ),
                ),
                // Keeps the text readable over any frame.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [c.background.withAlpha(0x33), c.background.withAlpha(0xF0)],
                      ),
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(Space.s32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (video != null)
                      MetaPill(
                        text: label,
                        icon: suggested ? Icons.auto_awesome_rounded : Icons.local_fire_department_rounded,
                        filled: true,
                      )
                    else
                      Text(label, style: type.row.copyWith(color: c.accent)),
                    const SizedBox(height: Space.s12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.hero.copyWith(height: 1.12, letterSpacing: -0.5),
                      ),
                    ),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: Space.s8),
                      Text(
                        facts.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.body.copyWith(color: c.textDim),
                      ),
                    ],
                    const SizedBox(height: Space.s24),
                    Row(
                      children: [
                        DesktopPill(
                          key: const ValueKey('home-hero-action'),
                          focusNode: widget.focus.entry,
                          primary: true,
                          icon: video != null ? Icons.play_arrow_rounded : Icons.refresh_rounded,
                          label: video != null ? 'Play' : (error != null ? 'Retry' : 'Loading'),
                          onPressed: video != null
                              ? () => playVideo(context, video, source: suggested ? 'for-you' : null)
                              : (error != null ? widget.onRetry : null),
                          onFocused: () => widget.focus.remember(widget.focus.entry),
                        ),
                        if (video != null) ...[
                          const SizedBox(width: Space.s12),
                          DesktopPill(
                            key: const ValueKey('home-hero-browse'),
                            label: 'Browse YouTube',
                            trailingIcon: Icons.arrow_forward_rounded,
                            onPressed: widget.onBrowse,
                          ),
                        ],
                        const Spacer(),
                        if (items.length > 1) _Dots(count: items.length, current: _page, onSelect: _go),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current, required this.onSelect});

  final int count;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final motion = Motion.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == current,
            label: 'Slide ${i + 1} of $count',
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('hero-dot-$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: AnimatedContainer(
                    duration: motion.focusTime,
                    curve: Motion.curve,
                    width: i == current ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == current ? c.accent : c.text.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A pill button: lime ([primary]) or outlined; [icon] leads, [trailingIcon]
/// follows the label. [onPressed] null disables it.
class DesktopPill extends StatefulWidget {
  const DesktopPill({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.primary = false,
    this.onPressed,
    this.focusNode,
    this.onFocused,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool primary;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onFocused;

  @override
  State<DesktopPill> createState() => _DesktopPillState();
}

class _DesktopPillState extends State<DesktopPill> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final type = Dims.of(context).type;
    final enabled = widget.onPressed != null;
    final fg = widget.primary ? c.onAccent : c.text;
    final fill = widget.primary
        ? Color.lerp(c.accent, Colors.white, _hovered ? 0.12 : 0)!
        : c.background.withValues(alpha: _hovered ? 0.65 : 0.4);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: enabled,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) widget.onFocused?.call();
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          }),
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: FocusRing(
              focused: _focused,
              radius: Radii.pill,
              child: AnimatedContainer(
                duration: Motion.of(context).hoverPressTime,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: Space.s24),
                decoration: BoxDecoration(
                  color: enabled ? fill : fill.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: widget.primary ? null : Border.all(color: c.text.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 22, color: fg),
                      const SizedBox(width: Space.s8),
                    ],
                    Text(widget.label, style: type.card.copyWith(color: fg)),
                    if (widget.trailingIcon != null) ...[
                      const SizedBox(width: Space.s8),
                      Icon(widget.trailingIcon, size: 18, color: fg),
                    ],
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

// ---------------------------------------------------------------- rows

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.rail,
    required this.perRow,
    required this.focus,
    required this.onViewAll,
  });

  final FeedRail rail;
  final int perRow;
  final SectionFocus focus;
  final VoidCallback onViewAll;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  int _page = 0;

  int get _pages => math.max(1, (widget.rail.items.length / widget.perRow).ceil());

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final type = Dims.of(context).type;
    final items = widget.rail.items;
    final page = math.min(_page, _pages - 1);
    final first = page * widget.perRow;
    final shown = items.skip(first).take(widget.perRow).toList();
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
              _TextLink(label: 'VIEW ALL ›', onPressed: widget.onViewAll),
              const SizedBox(width: Space.s12),
              _Chevron(
                key: ValueKey('row-prev-${widget.rail.id}'),
                label: 'Previous videos',
                icon: Icons.chevron_left_rounded,
                onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
              ),
              const SizedBox(width: Space.s8),
              _Chevron(
                key: ValueKey('row-next-${widget.rail.id}'),
                label: 'Next videos',
                icon: Icons.chevron_right_rounded,
                onPressed: page < _pages - 1 ? () => setState(() => _page = page + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: Space.s16),
          AnimatedSwitcher(
            duration: Motion.of(context).expandTime,
            child: Row(
              key: ValueKey('${widget.rail.id}-$page-${widget.perRow}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.perRow; i++) ...[
                  if (i > 0) const SizedBox(width: Space.s16),
                  Expanded(
                    child: i < shown.length
                        ? _VideoCard(
                            item: shown[i],
                            progress: widget.rail.progress[shown[i].videoId],
                            focus: widget.focus,
                            onOpen: () => playVideo(context, shown[i], source: widget.rail.id),
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
              child: Text(
                '${page + 1} / $_pages',
                style: type.meta.copyWith(color: c.textDim),
              ),
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
      excludeSemantics: true,
      child: FocusableActionDetector(
        onFocusChange: (f) => setState(() => _focused = f),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onPressed();
            return null;
          }),
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
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        onFocusChange: (f) => setState(() => _focused = f),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          }),
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

// ---------------------------------------------------------------- card

class _VideoCard extends StatefulWidget {
  const _VideoCard({required this.item, required this.progress, required this.focus, required this.onOpen});

  final VideoItem item;

  /// How far it was watched (0 to 1); Continue watching only.
  final double? progress;
  final SectionFocus focus;
  final VoidCallback onOpen;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  final _node = FocusNode(debugLabel: 'desktop video card');
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _onFocus(bool f) {
    if (!mounted) return;
    setState(() => _focused = f);
    if (f) {
      widget.focus.remember(_node);
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: Motion.of(context).focusTime,
        curve: Motion.curve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final d = Dims.of(context);
    final type = d.type;
    final motion = Motion.of(context);
    final item = widget.item;
    final url = VideoTile.thumbnailUrl(item.thumbnails);
    final duration = item.duration;
    final badge = item.isLive ? 'LIVE' : (duration == null ? null : VideoTile.clock(duration));
    final active = _hovered || _focused;
    final radius = Radii.card(d.form);
    final meta = [item.author, item.viewsText].where((s) => s.isNotEmpty).join('  ·  ');
    final progress = widget.progress;
    return Semantics(
      button: true,
      label: item.title,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: _node,
        onFocusChange: _onFocus,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onOpen();
            return null;
          }),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () {
              _node.requestFocus();
              widget.onOpen();
            },
            child: FocusRing(
              focused: _focused,
              radius: radius,
              child: AnimatedContainer(
                duration: motion.hoverPressTime,
                curve: Motion.curve,
                // Lifts 2 dp and the surface lightens 4% on hover.
                transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(Colors.white.withValues(alpha: _hovered ? 0.04 : 0), c.surface),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: c.hairline),
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
                            AnimatedScale(
                              scale: active ? 1.03 : 1,
                              duration: motion.expandTime,
                              curve: Motion.curve,
                              child: url == null
                                  ? Icon(Icons.smart_display_rounded, size: 40, color: c.textDim)
                                  : Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      cacheWidth: 640,
                                      errorBuilder: (_, _, _) =>
                                          Icon(Icons.smart_display_rounded, size: 40, color: c.textDim),
                                    ),
                            ),
                            // The play glyph fades in on hover or focus.
                            Center(
                              child: AnimatedOpacity(
                                opacity: active ? 1 : 0,
                                duration: motion.hoverPressTime,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                                  child: Icon(Icons.play_arrow_rounded, size: 30, color: c.onAccent),
                                ),
                              ),
                            ),
                            if (badge != null)
                              Positioned(
                                right: 8,
                                bottom: progress == null ? 8 : 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(badge, style: type.meta.copyWith(color: Colors.white)),
                                ),
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
                      padding: const EdgeInsets.fromLTRB(Space.s12, Space.s12, Space.s12, Space.s12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: type.card),
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

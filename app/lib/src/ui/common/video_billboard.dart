import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../features/youtube/youtube_results.dart' show HeroImage, VideoTile;
import '../../theme.dart';
import '../tv/focus_card.dart';
import '../tv/home_page.dart' show ActionLabel;
import 'dims.dart';
import 'glass.dart';
import 'pill_button.dart';
import 'tokens.dart';
import 'video_card.dart' show videoMeta;

// The billboards at the top of Home and of the YouTube section, one per form
// factor, shared by both pages. Desktop and phone get the motion (a slow
// Ken Burns push on the frame, pointer or swipe parallax, crossfades); the
// TV gets crossfades only, as a 2 GB box should.

/// How long the desktop billboard stays on a slide.
const heroAutoAdvance = Duration(seconds: 8);

/// How long the Ken Burns push lasts on a slide. Shorter than
/// [heroAutoAdvance], so the frame is still before the next slide comes (and
/// a test's pumpAndSettle ends between slides).
const kenBurnsTime = Duration(seconds: 7);

/// The facts line of a video: channel, views and length (or LIVE).
List<String> videoFacts(VideoItem v) {
  final duration = v.duration;
  return [
    v.author,
    v.viewsText,
    if (v.isLive) 'LIVE' else if (duration != null) VideoTile.clock(duration),
  ].where((s) => s.isNotEmpty).toList();
}

/// A slow push into [child] (8% over [kenBurnsTime]) drifting toward
/// [drift], once per key; still when animations are off.
class KenBurns extends StatefulWidget {
  const KenBurns({super.key, required this.child, this.drift = const Offset(-0.02, -0.015)});

  final Widget child;

  /// Where the frame drifts, as a fraction of its size.
  final Offset drift;

  @override
  State<KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<KenBurns> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: kenBurnsTime);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.of(context).reduced) {
      _c.stop();
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutSine.transform(_c.value);
        // Transform, not AnimatedScale: tests read AnimatedScale > 1 as a
        // focused tile.
        return Transform.translate(
          offset: Offset(widget.drift.dx * box.maxWidth * t, widget.drift.dy * box.maxHeight * t),
          child: Transform.scale(scale: 1 + 0.08 * t, child: child),
        );
      },
    ),
  );
}

/// Pager dots: the current one is a wide accent pill. Tappable with [onSelect].
class BillboardDots extends StatelessWidget {
  const BillboardDots({
    super.key,
    required this.count,
    required this.current,
    this.onSelect,
    this.compact = false,
  });

  final int count;
  final int current;
  final ValueChanged<int>? onSelect;

  /// The phone's small dots (5 dp, not tappable).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final motion = Motion.of(context);
    Widget dot(int i) => AnimatedContainer(
      duration: motion.focusTime,
      curve: Motion.curve,
      margin: compact ? const EdgeInsets.symmetric(horizontal: 2.5) : null,
      width: i == current ? (compact ? 14 : 24) : (compact ? 5 : 8),
      height: compact ? 5 : 8,
      decoration: BoxDecoration(
        color: i == current ? (compact ? c.text : c.accent) : c.text.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
    );
    if (compact || onSelect == null) {
      return ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < count; i++) dot(i)]),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == current,
            label: 'Slide ${i + 1} of $count',
            onTap: () => onSelect!(i),
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('hero-dot-$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect!(i),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(padding: const EdgeInsets.all(5), child: dot(i)),
              ),
            ),
          ),
      ],
    );
  }
}

BoxDecoration _cardBackground(ChithramTheme c) => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [c.heroTint, c.surface, c.background],
  ),
);

/// A channel's initial in a small accent circle, before its name.
class ChannelMark extends StatelessWidget {
  const ChannelMark({super.key, required this.name, this.size = 22});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [c.accent, c.accent2]),
      ),
      child: Text(
        letter,
        style: TextStyle(color: c.onAccent, fontSize: size * 0.5, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}

// ---------------------------------------------------------------- desktop

/// The desktop billboard: up to five videos that crossfade every
/// [heroAutoAdvance] (paused while pointed at or focused, off with animations
/// off), each with a Ken Burns push and a little parallax that follows the
/// pointer. Text sits on scrims that keep it readable over any frame. While
/// there is nothing to show it says so, and offers Retry after [error].
class DesktopBillboard extends StatefulWidget {
  const DesktopBillboard({
    super.key,
    required this.items,
    required this.kicker,
    required this.onPlay,
    required this.onRetry,
    this.kickerIcon = Icons.local_fire_department_rounded,
    this.error,
    this.loadingText = 'Loading what is popular…',
    this.secondaryLabel,
    this.secondaryIcon,
    this.secondaryTrailing = false,
    this.onSecondary,
    this.playFocusNode,
    this.onPlayFocused,
    this.actionKey = const ValueKey('home-hero-action'),
    this.secondaryKey = const ValueKey('home-hero-browse'),
  });

  final List<VideoItem> items;

  /// The accent pill over the title ("Recommended for you").
  final String kicker;
  final IconData kickerIcon;
  final String? error;
  final String loadingText;
  final void Function(VideoItem) onPlay;
  final VoidCallback onRetry;

  /// The outlined second button ("Browse YouTube", "Details"); none when
  /// [onSecondary] is null.
  final String? secondaryLabel;
  final IconData? secondaryIcon;

  /// The icon follows the label (an arrow) instead of leading it.
  final bool secondaryTrailing;
  final void Function(VideoItem)? onSecondary;
  final FocusNode? playFocusNode;
  final VoidCallback? onPlayFocused;
  final Key actionKey;
  final Key secondaryKey;

  @override
  State<DesktopBillboard> createState() => _DesktopBillboardState();
}

class _DesktopBillboardState extends State<DesktopBillboard> {
  int _page = 0;
  bool _hovered = false;
  bool _focusWithin = false;
  bool _reduced = false;
  Timer? _timer;

  /// The pointer over the billboard, -1 to 1 on each axis.
  Offset _pointer = Offset.zero;

  List<VideoItem> get _items => widget.items.take(5).toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = Motion.of(context).reduced;
    _schedule();
  }

  @override
  void didUpdateWidget(DesktopBillboard old) {
    super.didUpdateWidget(old);
    if (_page >= _items.length) _page = 0;
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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
    final motion = Motion.of(context);
    final type = d.type;
    final items = _items;
    final VideoItem? video = items.isEmpty ? null : items[math.min(_page, items.length - 1)];
    final error = widget.error;
    final height = (MediaQuery.sizeOf(context).height * 0.44).clamp(300.0, 460.0);

    final String title;
    final facts = video == null ? const <String>[] : videoFacts(video);
    if (video != null) {
      title = video.title;
    } else {
      title = error ?? widget.loadingText;
    }

    final text = Column(
      key: ValueKey(video?.videoId ?? (error != null ? 'error' : 'loading')),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (video != null)
          MetaPill(text: widget.kicker, icon: widget.kickerIcon, filled: true)
        else
          Text('YouTube', style: type.row.copyWith(color: c.accent)),
        const SizedBox(height: Space.s12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: type.hero.copyWith(height: 1.12, letterSpacing: -0.5, shadows: _textShadow),
          ),
        ),
        const SizedBox(height: Space.s12),
        if (video != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (video.author.isNotEmpty) ...[
                ChannelMark(name: video.author),
                const SizedBox(width: Space.s8),
              ],
              Flexible(
                child: Text(
                  facts.join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.body.copyWith(color: c.text.withValues(alpha: 0.82)),
                ),
              ),
            ],
          )
        else if (error != null)
          Text('Check the connection, then retry.', style: type.body.copyWith(color: c.textDim)),
      ],
    );

    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _schedule();
      },
      onHover: (e) {
        final size = context.size;
        if (size == null || _reduced) return;
        setState(
          () => _pointer = Offset(
            (e.localPosition.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
            (e.localPosition.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
          ),
        );
      },
      onExit: (_) {
        _hovered = false;
        setState(() => _pointer = Offset.zero);
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
          width: double.infinity,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: _cardBackground(c).copyWith(
            borderRadius: BorderRadius.circular(Radii.hero),
            border: Border.all(color: c.glassEdge),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (video != null) ...[
                // Parallax: the frame leans away from the pointer by up to 12 dp.
                TweenAnimationBuilder<Offset>(
                  tween: Tween(end: _pointer * -12),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, o, child) => Transform.translate(
                    offset: o,
                    child: Transform.scale(scale: 1.04, child: child),
                  ),
                  child: RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: motion.reduced ? Duration.zero : const Duration(milliseconds: 700),
                      switchInCurve: Curves.easeOut,
                      child: KenBurns(
                        key: ValueKey(video.videoId),
                        drift: _page.isEven ? const Offset(-0.02, -0.015) : const Offset(0.02, -0.01),
                        child: SizedBox.expand(child: HeroImage(videoId: video.videoId)),
                      ),
                    ),
                  ),
                ),
                // Two scrims: from the left under the text, and from the bottom.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        c.background.withAlpha(0xF2),
                        c.background.withAlpha(0x99),
                        c.background.withAlpha(0x10),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [c.background.withAlpha(0xCC), c.background.withAlpha(0x00)],
                      stops: const [0, 0.55],
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
                    // The text slides up into place with each new slide.
                    AnimatedSwitcher(
                      duration: motion.heroTime,
                      switchInCurve: Motion.curve,
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
                          child: child,
                        ),
                      ),
                      child: text,
                    ),
                    const SizedBox(height: Space.s24),
                    Row(
                      children: [
                        DesktopPill(
                          key: widget.actionKey,
                          focusNode: widget.playFocusNode,
                          primary: true,
                          icon: video != null ? Icons.play_arrow_rounded : Icons.refresh_rounded,
                          label: video != null ? 'Play' : (error != null ? 'Retry' : 'Loading'),
                          onPressed: video != null
                              ? () => widget.onPlay(video)
                              : (error != null ? widget.onRetry : null),
                          onFocused: widget.onPlayFocused,
                        ),
                        if (video != null && widget.onSecondary != null) ...[
                          const SizedBox(width: Space.s12),
                          DesktopPill(
                            key: widget.secondaryKey,
                            label: widget.secondaryLabel ?? 'Details',
                            icon: widget.secondaryTrailing ? null : widget.secondaryIcon,
                            trailingIcon: widget.secondaryTrailing ? widget.secondaryIcon : null,
                            onPressed: () => widget.onSecondary!(video),
                          ),
                        ],
                        const Spacer(),
                        if (items.length > 1)
                          BillboardDots(count: items.length, current: _page, onSelect: _go),
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

const _textShadow = [Shadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 2))];

// ---------------------------------------------------------------- phone

/// The inset of the text inside the phone billboard card.
const phoneHeroInset = 18.0;

/// The phone billboard: a pager across the full width, each page an inset
/// rounded card. The frame moves at a third of the swipe (parallax) and the
/// page in view gets the Ken Burns push. One status page while there are no
/// videos, with Retry after [error].
class PhoneBillboard extends StatefulWidget {
  const PhoneBillboard({
    super.key,
    required this.height,
    required this.items,
    required this.kicker,
    required this.onPlay,
    required this.onRetry,
    this.error,
    this.loadingText = 'Loading what is popular…',
    this.onDetails,
  });

  final double height;
  final List<VideoItem> items;
  final String kicker;
  final String? error;
  final String loadingText;
  final void Function(VideoItem) onPlay;
  final VoidCallback onRetry;

  /// A details button beside Play; none when null.
  final void Function(VideoItem)? onDetails;

  @override
  State<PhoneBillboard> createState() => _PhoneBillboardState();
}

class _PhoneBillboardState extends State<PhoneBillboard> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.items;
    final pages = math.max(videos.length, 1);
    final reduced = Motion.of(context).reduced;
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _controller,
        itemCount: pages,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.panel),
            child: videos.isEmpty
                ? _PhoneStatusPage(
                    error: widget.error,
                    loadingText: widget.loadingText,
                    onRetry: widget.onRetry,
                  )
                : _PhoneHeroPage(
                    video: videos[i],
                    kicker: widget.kicker,
                    page: _page,
                    pages: pages,
                    onPlay: widget.onPlay,
                    onDetails: widget.onDetails,
                    // How far this page is from the centre, -1 to 1, for the parallax.
                    offset: reduced ? null : _offset(i),
                    still: i != _page,
                  ),
          ),
        ),
      ),
    );
  }

  ValueListenable<double>? _offset(int i) => _PageOffset(_controller, i);
}

/// A page's distance from the centre of the pager (0 in view).
class _PageOffset extends ChangeNotifier implements ValueListenable<double> {
  _PageOffset(this.controller, this.index);

  final PageController controller;
  final int index;

  @override
  double get value {
    if (!controller.hasClients || !controller.position.haveDimensions) return 0;
    return ((controller.page ?? 0) - index).clamp(-1.0, 1.0);
  }

  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => controller.removeListener(listener);
}

class _PhoneHeroPage extends StatelessWidget {
  const _PhoneHeroPage({
    required this.video,
    required this.kicker,
    required this.page,
    required this.pages,
    required this.onPlay,
    required this.onDetails,
    required this.offset,
    required this.still,
  });

  final VideoItem video;
  final String kicker;
  final int page;
  final int pages;
  final void Function(VideoItem) onPlay;
  final void Function(VideoItem)? onDetails;
  final ValueListenable<double>? offset;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.of(FormFactor.phone);
    final c = ChithramColors.of(context);
    final line = videoMeta(video, separator: ' · ');
    Widget image = SizedBox.expand(child: HeroImage(videoId: video.videoId));
    if (!still) image = KenBurns(key: ValueKey(video.videoId), child: image);
    final parallax = offset;
    if (parallax != null) {
      // A final copy: the closure below must not see `image` reassigned to
      // this LayoutBuilder, or it would nest itself without end.
      final frame = image;
      image = LayoutBuilder(
        builder: (context, box) => ValueListenableBuilder<double>(
          valueListenable: parallax,
          child: frame,
          // The frame trails the card at a third of the swipe.
          builder: (context, o, child) =>
              Transform.translate(offset: Offset(o * box.maxWidth * 0.33, 0), child: child),
        ),
      );
    }
    return DecoratedBox(
      decoration: _cardBackground(c),
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.background.withAlpha(0x00), c.background.withAlpha(0xF0)],
                stops: const [0.3, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(phoneHeroInset),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kicker, style: type.overline.copyWith(color: c.accent)),
                const SizedBox(height: Space.s4),
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: type.hero.copyWith(shadows: _textShadow),
                ),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: Space.s4),
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.meta.copyWith(color: c.textDim),
                  ),
                ],
                const SizedBox(height: Space.s12),
                // Play bottom-left, where the thumb rests; the dots opposite.
                Row(
                  children: [
                    _PhonePlayButton(onPressed: () => onPlay(video)),
                    if (onDetails != null) ...[
                      const SizedBox(width: Space.s8),
                      IconButton.filledTonal(
                        tooltip: 'Details',
                        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: () => onDetails!(video),
                        icon: const Icon(Icons.info_outline_rounded),
                      ),
                    ],
                    const Spacer(),
                    if (pages > 1) BillboardDots(count: pages, current: page, compact: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pill Play button, 48 dp tall (the touch guideline).
class _PhonePlayButton extends StatelessWidget {
  const _PhonePlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: TypeScale.of(FormFactor.phone).card.fontSize, fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: const Text('Play'),
    );
  }
}

class _PhoneStatusPage extends StatelessWidget {
  const _PhoneStatusPage({required this.error, required this.loadingText, required this.onRetry});

  final String? error;
  final String loadingText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.of(FormFactor.phone);
    final failed = error;
    return DecoratedBox(
      decoration: _cardBackground(ChithramColors.of(context)),
      // Anchored at the bottom; scrolls rather than overflows at large text.
      child: SingleChildScrollView(
        reverse: true,
        padding: const EdgeInsets.all(phoneHeroInset),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('YouTube', style: type.overline.copyWith(color: ChithramColors.of(context).accent)),
              const SizedBox(height: Space.s4),
              Text(failed ?? loadingText, maxLines: 4, overflow: TextOverflow.ellipsis, style: type.h1),
              if (failed != null) ...[
                const SizedBox(height: Space.s16),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- TV

/// The TV billboard: the first video over its frame, with Play (the section's
/// entry when [playFocusNode] is its [SectionFocus.entry]) and, with
/// [onDetails], Details. A new video crossfades in; no Ken Burns and no blur,
/// to spare a 2 GB box. While there is nothing it says so, with Retry after
/// [error].
class TvBillboard extends StatelessWidget {
  const TvBillboard({
    super.key,
    required this.focus,
    required this.items,
    required this.kicker,
    required this.onPlay,
    required this.onRetry,
    this.kickerIcon = Icons.local_fire_department_rounded,
    this.error,
    this.loadingText = 'Loading what is popular…',
    this.onDetails,
    this.playFocusNode,
    this.actionKey = const ValueKey('home-hero-action'),
    this.detailsKey,
  });

  final SectionFocus focus;
  final List<VideoItem> items;
  final String kicker;
  final IconData kickerIcon;
  final String? error;
  final String loadingText;
  final void Function(VideoItem) onPlay;
  final VoidCallback onRetry;
  final void Function(VideoItem)? onDetails;
  final FocusNode? playFocusNode;
  final Key actionKey;
  final Key? detailsKey;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final height = (MediaQuery.sizeOf(context).height * (d.tv ? 0.44 : 0.42)).clamp(
      d.tv ? 190.0 : 220.0,
      460.0,
    );
    final VideoItem? video = items.firstOrNull;
    final failed = error;
    final String label, title, line;
    final facts = <String>[];
    if (video != null) {
      (label, title, line) = (kicker, video.title, '');
      facts.addAll(videoFacts(video));
    } else if (failed != null) {
      (label, title, line) = ('YouTube', failed, 'Check the connection, then retry.');
    } else {
      (label, title, line) = ('YouTube', loadingText, '');
    }
    return Container(
      // Fill the width: without it the card shrinks to its widest child.
      width: double.infinity,
      constraints: BoxConstraints(minHeight: height),
      margin: EdgeInsets.fromLTRB(
        d.phone ? Space.s8 : Space.s16,
        d.tv ? Space.s12 : Space.s16,
        d.phone ? Space.s8 : Space.s16,
        0,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: _cardBackground(c).copyWith(
        borderRadius: BorderRadius.circular(Radii.hero),
        border: Border.all(color: c.glassEdge),
      ),
      child: Stack(
        children: [
          if (video != null) ...[
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: Motion.of(context).heroTime,
                child: SizedBox.expand(
                  key: ValueKey(video.videoId),
                  child: HeroImage(videoId: video.videoId),
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
                    colors: [c.background.withAlpha(0x33), c.background.withAlpha(0xEE)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [c.background.withAlpha(0x99), c.background.withAlpha(0x00)],
                    stops: const [0, 0.5],
                  ),
                ),
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.all(d.phone ? 18 : (d.tv ? Space.s24 : 28)),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height - (d.phone ? 36 : (d.tv ? Space.s48 : 56))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (video != null)
                    MetaPill(text: label, icon: kickerIcon, filled: true)
                  else
                    Text(
                      label,
                      style: TextStyle(color: c.accent, fontSize: d.t(14), fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: Space.s8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: d.tv
                          ? d.type.hero.copyWith(height: 1.1)
                          : TextStyle(
                              fontSize: d.t(34),
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                              letterSpacing: -0.3,
                            ),
                    ),
                  ),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [for (final f in facts) MetaPill(text: f)]),
                  ],
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textDim, fontSize: d.t(14)),
                    ),
                  ],
                  SizedBox(height: d.tv ? Space.s16 : 18),
                  Wrap(
                    spacing: Space.s16,
                    runSpacing: Space.s12,
                    children: [
                      FocusCard(
                        key: actionKey,
                        focusNode: playFocusNode,
                        section: focus,
                        radius: Radii.pill,
                        onActivate: video != null ? () => onPlay(video) : (failed != null ? onRetry : null),
                        child: video != null
                            ? const ActionLabel(icon: Icons.play_arrow_rounded, text: 'Play', primary: true)
                            : ActionLabel(
                                icon: Icons.refresh_rounded,
                                text: failed != null ? 'Retry' : 'Loading',
                              ),
                      ),
                      if (video != null && onDetails != null)
                        FocusCard(
                          key: detailsKey,
                          section: focus,
                          radius: Radii.pill,
                          onActivate: () => onDetails!(video),
                          child: const ActionLabel(icon: Icons.info_outline_rounded, text: 'Details'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

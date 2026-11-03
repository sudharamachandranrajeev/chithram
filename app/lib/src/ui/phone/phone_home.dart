import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../core/services.dart';
import '../../features/youtube/feed/youtube_feed.dart';
import '../../features/youtube/phone/phone_video_card.dart';
import '../../features/youtube/youtube_results.dart';
import '../../theme.dart';
import '../common/form_factor.dart';
import '../common/tokens.dart';

/// The inset of the text inside the hero card (the design's 18 dp).
const _heroInset = 18.0;

/// Space between a rail's title and its cards.
const _railTitleGap = 10.0;

/// Gap between pager dots.
const _dotGap = 2.5;

/// Height of the hero's text at scale 1 (kicker, two title lines, meta line)
/// and of everything else in it (gaps, Play, insets); the card is never
/// shorter than these at the user's text scale.
const _heroTextHeight = 113.0;
const _heroChrome = 104.0;

/// Phone Home: a swipeable billboard card and swipeable rails of YouTube
/// videos, popular now and, as Chithram learns, suggestions. Pull to refresh.
class PhoneHome extends StatefulWidget {
  const PhoneHome({super.key});

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
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
    final textRoom = MediaQuery.textScalerOf(context).scale(_heroTextHeight) + _heroChrome;
    return ValueListenableBuilder<FeedState>(
      valueListenable: feed.state,
      builder: (context, state, _) => LayoutBuilder(
        builder: (context, box) => RefreshIndicator(
          onRefresh: () => feed.refresh(force: true),
          child: ListView(
            key: const PageStorageKey<String>('phone-home-scroll'),
            padding: const EdgeInsets.only(bottom: Space.s24),
            children: [
              // 220 dp on a small phone, taller on a big one, so the first rail
              // peeks in under it; taller still for large text.
              _PhoneHero(
                height: math.max((box.maxHeight * 0.36).clamp(220.0, 320.0), textRoom) + Space.s16,
                state: state,
                onRetry: () => feed.refresh(force: true),
              ),
              for (final rail in state.rails) _Rail(key: ValueKey('home-${rail.id}'), rail: rail),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({super.key, required this.rail});

  final FeedRail rail;

  static const _cardWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s16, Space.s24, Space.s16, _railTitleGap),
          child: Semantics(
            header: true,
            child: Text(
              rail.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.of(FormFactor.phone).row,
            ),
          ),
        ),
        SizedBox(
          height: _cardWidth * 9 / 16 + PhoneVideoCard.textHeight(scaler),
          child: ListView.separated(
            key: PageStorageKey<String>('phone-rail-${rail.id}'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.s16),
            itemCount: rail.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s12),
            itemBuilder: (context, i) => SizedBox(
              width: _cardWidth,
              child: PhoneVideoCard(
                item: rail.items[i],
                progress: rail.progress[rail.items[i].videoId],
                onOpen: () => playVideo(context, rail.items[i], source: rail.id),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The billboard: a pager across the full width, each page an inset rounded
/// card; one status page while there are no videos.
class _PhoneHero extends StatefulWidget {
  const _PhoneHero({required this.height, required this.state, required this.onRetry});

  final double height;
  final FeedState state;
  final VoidCallback onRetry;

  @override
  State<_PhoneHero> createState() => _PhoneHeroState();
}

class _PhoneHeroState extends State<_PhoneHero> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.state.hero;
    final suggested = widget.state.rails.any((r) => r.id == 'for-you');
    final pages = math.max(videos.length, 1);
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        key: const ValueKey('phone-hero'),
        controller: _controller,
        itemCount: pages,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.panel),
            child: videos.isEmpty
                ? _StatusPage(error: widget.state.error, onRetry: widget.onRetry)
                : _HeroPage(video: videos[i], suggested: suggested, page: _page, pages: pages),
          ),
        ),
      ),
    );
  }
}

/// The pager dots: the current page is a wide pill.
class _Dots extends StatelessWidget {
  const _Dots({required this.page, required this.pages});

  final int page;
  final int pages;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final time = Motion.of(context).hoverPressTime;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < pages; i++)
            AnimatedContainer(
              duration: time,
              curve: Motion.curve,
              margin: const EdgeInsets.symmetric(horizontal: _dotGap),
              width: i == page ? 14 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: i == page ? c.text : c.text.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(Radii.chip),
              ),
            ),
        ],
      ),
    );
  }
}

BoxDecoration _heroBackground(BuildContext context) {
  final c = ChithramColors.of(context);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [c.heroTint, c.surface, c.background],
    ),
  );
}

class _HeroPage extends StatelessWidget {
  const _HeroPage({required this.video, required this.suggested, required this.page, required this.pages});

  final VideoItem video;
  final bool suggested;
  final int page;
  final int pages;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.of(FormFactor.phone);
    final c = ChithramColors.of(context);
    final line = [video.author, video.viewsText].where((s) => s.isNotEmpty).join(' · ');
    return DecoratedBox(
      decoration: _heroBackground(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          HeroImage(videoId: video.videoId),
          // Keeps the text readable over any frame.
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
            padding: const EdgeInsets.all(_heroInset),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggested ? 'Recommended for you' : 'Popular on YouTube',
                    style: type.overline.copyWith(color: c.accent)),
                const SizedBox(height: Space.s4),
                Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: type.hero),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: Space.s4),
                  Text(line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.meta.copyWith(color: c.textDim)),
                ],
                const SizedBox(height: Space.s12),
                // Play bottom-left, where the thumb rests; the dots opposite.
                Row(
                  children: [
                    _PlayButton(onPressed: () => playVideo(context, video, source: suggested ? 'for-you' : null)),
                    const Spacer(),
                    if (pages > 1) _Dots(page: page, pages: pages),
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

/// The pill Play button, 48 dp tall (the design draws 44 dp, under the touch
/// guideline).
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: TypeScale.of(FormFactor.phone).card.fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: const Text('Play'),
    );
  }
}

class _StatusPage extends StatelessWidget {
  const _StatusPage({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.of(FormFactor.phone);
    final failed = error;
    return DecoratedBox(
      decoration: _heroBackground(context),
      // Anchored at the bottom; scrolls rather than overflows at large text.
      child: SingleChildScrollView(
        reverse: true,
        padding: const EdgeInsets.all(_heroInset),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('YouTube', style: type.overline.copyWith(color: ChithramColors.of(context).accent)),
              const SizedBox(height: Space.s4),
              Text(failed ?? 'Loading what is popular…',
                  maxLines: 4, overflow: TextOverflow.ellipsis, style: type.h1),
              if (failed != null) ...[
                const SizedBox(height: Space.s16),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: const StadiumBorder()),
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

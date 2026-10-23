import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../core/services.dart';
import '../../features/youtube/feed/youtube_feed.dart';
import '../../features/youtube/phone/phone_video_card.dart';
import '../../features/youtube/youtube_results.dart';
import '../../theme.dart';

/// Phone Home: a full-bleed swipeable billboard and swipeable rails of YouTube
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
    return ValueListenableBuilder<FeedState>(
      valueListenable: feed.state,
      builder: (context, state, _) => LayoutBuilder(
        builder: (context, box) => RefreshIndicator(
          onRefresh: () => feed.refresh(force: true),
          child: ListView(
            key: const PageStorageKey<String>('phone-home-scroll'),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // About 56% of the room under the top bar, so the first rail peeks in.
              _PhoneHero(
                height: math.max(box.maxHeight * 0.56, 280),
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

  static const _cardWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            rail.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          height: _cardWidth * 9 / 16 + PhoneVideoCard.textHeight(scaler),
          child: ListView.separated(
            key: PageStorageKey<String>('phone-rail-${rail.id}'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: rail.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: _cardWidth,
              child: PhoneVideoCard(
                item: rail.items[i],
                onOpen: () => playVideo(context, rail.items[i], source: rail.id),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The billboard's pages, edge to edge; one status page while there are none.
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
      child: Stack(
        children: [
          PageView.builder(
            key: const ValueKey('phone-hero'),
            controller: _controller,
            itemCount: pages,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => videos.isEmpty
                ? _StatusPage(error: widget.state.error, onRetry: widget.onRetry)
                : _HeroPage(video: videos[i], suggested: suggested),
          ),
          if (pages > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < pages; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _page ? ChithramColors.accent : ChithramColors.textDim,
                          borderRadius: BorderRadius.circular(3),
                        ),
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

const _heroBackground = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0x59F5A300), ChithramColors.surface, ChithramColors.background],
  ),
);

class _HeroPage extends StatelessWidget {
  const _HeroPage({required this.video, required this.suggested});

  final VideoItem video;
  final bool suggested;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final line = [video.author, video.viewsText].where((s) => s.isNotEmpty).join(' · ');
    return DecoratedBox(
      decoration: _heroBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          HeroImage(videoId: video.videoId),
          // Keeps the text readable over any frame.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x000B0B10), Color(0xF00B0B10)],
                stops: [0.3, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggested ? 'Recommended for you' : 'Popular on YouTube',
                    style: text.labelLarge?.copyWith(color: ChithramColors.accent, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: ChithramColors.textDim)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => playVideo(context, video, source: suggested ? 'for-you' : null),
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPage extends StatelessWidget {
  const _StatusPage({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final failed = error;
    return DecoratedBox(
      decoration: _heroBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YouTube', style: text.labelLarge?.copyWith(color: ChithramColors.accent, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(failed ?? 'Loading what is popular…',
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (failed != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

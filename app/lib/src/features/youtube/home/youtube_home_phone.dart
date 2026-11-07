import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../../theme.dart';
import '../../../ui/common/form_factor.dart';
import '../../../ui/common/motion_kit.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/common/video_billboard.dart';
import '../../../ui/common/video_card.dart';
import '../../../ui/phone/phone_home.dart' show PhoneRail, phoneHeroHeight;
import '../phone/phone_video_card.dart';
import '../youtube_results.dart';
import 'video_details.dart';
import 'youtube_home.dart';
import 'youtube_home_keys.dart';
import 'youtube_results_page.dart';
import 'youtube_search_field.dart';
import 'youtube_topics.dart';

/// The phone YouTube home: the search field and chips pinned at the top
/// (the IME's Search opens results), then the billboard and rails (For you)
/// or a column of cards (a topic). Pull to refresh.
class PhoneYouTubeHome extends StatefulWidget {
  const PhoneYouTubeHome({super.key, required this.view});

  final YouTubeHomeView view;

  @override
  State<PhoneYouTubeHome> createState() => _PhoneYouTubeHomeState();
}

class _PhoneYouTubeHomeState extends State<PhoneYouTubeHome> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    return LayoutBuilder(
      builder: (context, box) => RefreshIndicator(
        onRefresh: view.refresh,
        child: CustomScrollView(
          key: const PageStorageKey<String>('yt-home-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _Header(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s16),
                      child: YouTubeSearchField(
                        controller: _query,
                        onSubmit: (q) {
                          FocusScope.of(context).unfocus();
                          openYouTubeResults(context, q);
                        },
                      ),
                    ),
                    const SizedBox(height: Space.s12),
                    TopicChipBar(
                      topics: view.topics,
                      selected: view.topic,
                      onSelect: view.onTopic,
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: Space.s16),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: FadeThroughSwitcher(
                child: KeyedSubtree(key: view.contentKey, child: _content(context, view, box.maxHeight)),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: Space.s24)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, YouTubeHomeView view, double viewport) {
    final heroHeight = phoneHeroHeight(context, viewport);
    switch (view.status) {
      case HomeStatus.loading:
        return PhoneHomeSkeleton(heroHeight: heroHeight);
      case HomeStatus.failed:
      case HomeStatus.empty:
        return _StatusCard(view: view);
      case HomeStatus.ready:
        break;
    }
    final topic = view.topic;
    final state = view.state;
    void details(VideoItem v) => showVideoDetails(context, v, source: topic.railId);
    final billboard = PhoneBillboard(
      key: YouTubeHomeKeys.hero,
      height: heroHeight,
      items: heroFor(topic, state),
      kicker: kickerFor(topic, state),
      error: state.error,
      onPlay: (v) => playVideo(context, v, source: topic.railId),
      onRetry: view.onRetry,
      onDetails: details,
    );
    if (topic.forYou) {
      return Column(
        key: YouTubeHomeKeys.topic(topic.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          billboard,
          for (final rail in state.rails) PhoneRail(key: ValueKey('yt-row-${rail.id}'), rail: rail),
        ],
      );
    }
    final rail = view.rail!;
    return Column(
      key: YouTubeHomeKeys.topic(topic.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        billboard,
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s16, Space.s24, Space.s16, Space.s12),
          child: Semantics(header: true, child: Text(rail.title, style: TypeScale.of(FormFactor.phone).row)),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth - 2 * Space.s16;
            final columns = (width / 340).floor().clamp(1, 4);
            final rows = (rail.items.length / columns).ceil();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s16),
              child: Column(
                children: [
                  for (var r = 0; r < rows; r++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < columns; i++) ...[
                            if (i > 0) const SizedBox(width: Space.s12),
                            Expanded(
                              child: r * columns + i < rail.items.length
                                  ? StaggeredEntrance(
                                      index: r * columns + i,
                                      child: PhoneVideoCard(
                                        item: rail.items[r * columns + i],
                                        progress: rail.progress[rail.items[r * columns + i].videoId],
                                        onOpen: () => playVideo(context, rail.items[r * columns + i], source: rail.id),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The shape of the phone home while the feed loads.
class PhoneHomeSkeleton extends StatelessWidget {
  const PhoneHomeSkeleton({super.key, required this.heroHeight});

  final double heroHeight;

  @override
  Widget build(BuildContext context) => Shimmer(
    key: YouTubeHomeKeys.skeleton,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: heroHeight - Space.s16, radius: Radii.panel),
          const SizedBox(height: Space.s24),
          const SkeletonBox(width: 160, height: 18, radius: 6),
          const SizedBox(height: Space.s12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: VideoCardSkeleton()),
              SizedBox(width: Space.s12),
              Expanded(flex: 1, child: VideoCardSkeleton()),
            ],
          ),
        ],
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.view});

  final YouTubeHomeView view;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final type = TypeScale.of(FormFactor.phone);
    final (title, line) = statusText(view);
    return Container(
      key: YouTubeHomeKeys.error,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, 0),
      padding: const EdgeInsets.all(Space.s24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.panel),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [c.heroTint.withValues(alpha: 0.14), c.surface, c.background],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon(view), size: 40, color: c.textDim),
          const SizedBox(height: Space.s12),
          Text(title, style: type.h1),
          const SizedBox(height: Space.s4),
          Text(line, maxLines: 4, overflow: TextOverflow.ellipsis, style: type.body.copyWith(color: c.textDim)),
          const SizedBox(height: Space.s16),
          FilledButton.tonalIcon(
            key: YouTubeHomeKeys.retry,
            onPressed: view.onRetry,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: const StadiumBorder()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// The pinned search field and chips, on the page's background so cards
/// scroll under it cleanly.
class _Header extends SliverPersistentHeaderDelegate {
  _Header({required this.child});

  final Widget child;

  // The padding, the field, the gap, the chips and the 1 dp hairline (a
  // border adds to the container's padding).
  static const _height = Space.s12 + 48 + Space.s12 + 48 + Space.s8 + 1;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = ChithramColors.of(context);
    final under = shrinkOffset > 0 || overlapsContent;
    return Container(
      padding: const EdgeInsets.only(top: Space.s12, bottom: Space.s8),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: under ? c.hairline : Colors.transparent)),
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_Header old) => old.child != child;
}

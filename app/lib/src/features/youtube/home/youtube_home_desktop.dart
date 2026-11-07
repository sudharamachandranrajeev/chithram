import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/common/motion_kit.dart';
import '../../../ui/common/pill_button.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/common/video_billboard.dart';
import '../../../ui/common/video_card.dart';
import '../../../ui/common/video_row.dart';
import '../../../ui/desktop/desktop_home.dart' show cardsPerRow;
import '../youtube_results.dart';
import 'video_details.dart';
import 'youtube_home.dart';
import 'youtube_home_keys.dart';
import 'youtube_results_page.dart';
import 'youtube_search_field.dart';
import 'youtube_topics.dart';

/// The desktop YouTube home: a pinned header (the mark, the search field
/// with suggestions, the chips) over the billboard and the rows or grid. The
/// header turns opaque with a hairline once content scrolls under it.
class DesktopYouTubeHome extends StatefulWidget {
  const DesktopYouTubeHome({super.key, required this.view});

  final YouTubeHomeView view;

  @override
  State<DesktopYouTubeHome> createState() => _DesktopYouTubeHomeState();
}

class _DesktopYouTubeHomeState extends State<DesktopYouTubeHome> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final view = widget.view;
    return CustomScrollView(
      key: const PageStorageKey<String>('yt-home-scroll'),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _Header(
            gutter: d.gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const YouTubeMark(),
                    const SizedBox(width: Space.s32),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: YouTubeSearchField(
                            controller: _query,
                            focusNode: view.focus.entry,
                            onSubmit: (q) => openYouTubeResults(context, q),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s16),
                TopicChipBar(topics: view.topics, selected: view.topic, onSelect: view.onTopic),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(d.gutter, Space.s8, d.gutter, Space.s48),
          sliver: SliverToBoxAdapter(
            child: FadeThroughSwitcher(
              child: KeyedSubtree(key: view.contentKey, child: _content(context, view)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, YouTubeHomeView view) {
    switch (view.status) {
      case HomeStatus.loading:
        return const DesktopHomeSkeleton();
      case HomeStatus.failed:
      case HomeStatus.empty:
        return _StatusPanel(view: view);
      case HomeStatus.ready:
        break;
    }
    final topic = view.topic;
    final state = view.state;
    void details(VideoItem v) => showVideoDetails(context, v, source: topic.railId);
    final billboard = DesktopBillboard(
      key: YouTubeHomeKeys.hero,
      items: heroFor(topic, state),
      kicker: kickerFor(topic, state),
      kickerIcon: topic.icon,
      error: state.error,
      onPlay: (v) => playVideo(context, v, source: topic.railId ?? (state.rails.any((r) => r.id == 'for-you') ? 'for-you' : null)),
      onRetry: view.onRetry,
      secondaryLabel: 'Details',
      secondaryIcon: Icons.info_outline_rounded,
      onSecondary: details,
      actionKey: YouTubeHomeKeys.heroPlay,
      secondaryKey: YouTubeHomeKeys.heroDetails,
    );
    if (topic.forYou) {
      final perRow = cardsPerRow(MediaQuery.sizeOf(context).width);
      return Column(
        key: YouTubeHomeKeys.topic(topic.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          billboard,
          for (final rail in state.rails)
            VideoRow(
              key: ValueKey('yt-row-${rail.id}'),
              rail: rail,
              perRow: perRow,
              focus: view.focus,
              onOpen: (v) => playVideo(context, v, source: rail.id),
              onDetails: (v) => showVideoDetails(context, v, source: rail.id),
              // VIEW ALL opens the rail as its topic, when it has a chip.
              onViewAll: _topicOf(view, rail.id) == null ? null : () => view.onTopic(_topicOf(view, rail.id)!),
            ),
        ],
      );
    }
    final rail = view.rail!;
    return Column(
      key: YouTubeHomeKeys.topic(topic.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        billboard,
        const SizedBox(height: Space.s32),
        Text(rail.title, style: Dims.of(context).type.row),
        const SizedBox(height: Space.s16),
        DesktopVideoGrid(
          items: rail.items,
          progress: rail.progress,
          onOpen: (v) => playVideo(context, v, source: rail.id),
          onDetails: details,
        ),
      ],
    );
  }

  static YouTubeTopic? _topicOf(YouTubeHomeView view, String railId) {
    for (final t in view.topics) {
      if (t.railId == railId) return t;
    }
    return null;
  }
}

/// A grid of [VideoCard]s laid out as rows (it sits in the page's scroll
/// view), columns by width, cascading in.
class DesktopVideoGrid extends StatelessWidget {
  const DesktopVideoGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.onDetails,
    this.progress = const {},
  });

  final List<VideoItem> items;
  final void Function(VideoItem) onOpen;
  final void Function(VideoItem)? onDetails;
  final Map<String, double> progress;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = resultColumns(box.maxWidth);
      final rows = (items.length / columns).ceil();
      final onDetails = this.onDetails;
      return Column(
        children: [
          for (var r = 0; r < rows; r++)
            Padding(
              padding: EdgeInsets.only(top: r == 0 ? 0 : Space.s24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: Space.s16),
                    Expanded(
                      child: r * columns + i < items.length
                          ? StaggeredEntrance(
                              index: r * columns + i,
                              child: VideoCard(
                                item: items[r * columns + i],
                                progress: progress[items[r * columns + i].videoId],
                                onOpen: () => onOpen(items[r * columns + i]),
                                onDetails: onDetails == null ? null : () => onDetails(items[r * columns + i]),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// The shape of the desktop home while the feed loads: the billboard and two
/// rows of cards, shimmering.
class DesktopHomeSkeleton extends StatelessWidget {
  const DesktopHomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final perRow = cardsPerRow(MediaQuery.sizeOf(context).width);
    final height = (MediaQuery.sizeOf(context).height * 0.44).clamp(300.0, 460.0);
    return Shimmer(
      key: YouTubeHomeKeys.skeleton,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: height, radius: Radii.hero),
          for (var r = 0; r < 2; r++) ...[
            const SizedBox(height: Space.s32),
            const SkeletonBox(width: 220, height: 22, radius: 8),
            const SizedBox(height: Space.s16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < perRow; i++) ...[
                  if (i > 0) const SizedBox(width: Space.s16),
                  const Expanded(child: VideoCardSkeleton()),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.view});

  final YouTubeHomeView view;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final type = Dims.of(context).type;
    final (title, line) = statusText(view);
    return Container(
      key: YouTubeHomeKeys.error,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Space.s32, vertical: Space.s64),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.hero),
        border: Border.all(color: c.glassEdge),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [c.heroTint.withValues(alpha: 0.12), c.surface, c.background],
        ),
      ),
      child: Column(
        children: [
          Icon(statusIcon(view), size: 56, color: c.textDim),
          const SizedBox(height: Space.s16),
          Text(title, style: type.h1),
          const SizedBox(height: Space.s8),
          Text(line, textAlign: TextAlign.center, style: type.body.copyWith(color: c.textDim)),
          const SizedBox(height: Space.s24),
          DesktopPill(
            key: YouTubeHomeKeys.retry,
            primary: true,
            icon: Icons.refresh_rounded,
            label: 'Retry',
            onPressed: view.onRetry,
          ),
        ],
      ),
    );
  }
}

/// The pinned header: transparent over the top of the page, opaque with a
/// hairline once content scrolls under it.
class _Header extends SliverPersistentHeaderDelegate {
  _Header({required this.gutter, required this.child});

  final double gutter;
  final Widget child;

  // The padding, the field, the gap, the chips and the 1 dp hairline (a
  // border adds to the container's padding).
  static const _height = Space.s24 + 48 + Space.s16 + 40 + Space.s16 + 1;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = ChithramColors.of(context);
    final under = shrinkOffset > 0 || overlapsContent;
    return AnimatedContainer(
      duration: Motion.of(context).expandTime,
      padding: EdgeInsets.fromLTRB(gutter, Space.s24, gutter, Space.s16),
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: under ? 0.96 : 0),
        border: Border(bottom: BorderSide(color: under ? c.hairline : Colors.transparent)),
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_Header old) => old.child != child || old.gutter != gutter;
}

import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/common/motion_kit.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/common/video_billboard.dart';
import '../../../ui/common/video_card.dart';
import '../../../ui/tv/focus_card.dart';
import '../../../ui/tv/focus_rail.dart';
import '../../../ui/tv/home_page.dart' show ActionLabel, tvTileWidth;
import '../../../ui/tv/search_keyboard.dart';
import '../youtube_results.dart';
import 'video_details.dart';
import 'youtube_home.dart';
import 'youtube_home_keys.dart';
import 'youtube_results_page.dart';
import 'youtube_topics.dart';

/// The TV YouTube home, all D-pad: the search bar (the section's entry; OK
/// opens the on-screen keyboard, whose Search opens results), the chips (OK
/// picks one), the billboard and rails (For you) or a grid of tiles (a
/// topic). Crossfades only: no blur, no scale, no Ken Burns on a 2 GB box.
class TvYouTubeHome extends StatefulWidget {
  const TvYouTubeHome({super.key, required this.view});

  final YouTubeHomeView view;

  @override
  State<TvYouTubeHome> createState() => _TvYouTubeHomeState();
}

class _TvYouTubeHomeState extends State<TvYouTubeHome> {
  final _query = ValueNotifier('');
  final _bar = GlobalKey();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _openKeyboard() async {
    final box = _bar.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final submitted = await showSearchKeyboard(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      query: _query,
      suggest: _suggest,
    );
    final q = _query.value.trim();
    if (submitted && q.isNotEmpty && mounted) await openYouTubeResults(context, q);
  }

  Future<List<KeyboardSuggestion>> _suggest(String prefix) async {
    try {
      final found = await AppServices.of(context).youtube.suggest(prefix);
      return [
        for (final s in found.take(6)) KeyboardSuggestion(s, source: 'YouTube', icon: Icons.smart_display_rounded),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final view = widget.view;
    final side = d.phone ? Space.s8 : Space.s16;
    return SingleChildScrollView(
      key: const PageStorageKey<String>('yt-home-scroll'),
      padding: const EdgeInsets.only(bottom: Space.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(side, Space.s16, side, 0),
            child: Row(
              children: [
                const YouTubeMark(),
                const SizedBox(width: Space.s24),
                Expanded(
                  child: KeyedSubtree(
                    key: _bar,
                    child: FocusCard(
                      key: YouTubeHomeKeys.searchBar,
                      focusNode: view.focus.entry,
                      section: view.focus,
                      radius: Radii.pill,
                      onActivate: _openKeyboard,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: Space.s16),
                        color: c.surfaceHigh,
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, size: d.t(22), color: c.textDim),
                            const SizedBox(width: Space.s12),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: _query,
                                builder: (context, q, _) => Text(
                                  q.isEmpty ? 'Search YouTube' : q,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: d.t(18),
                                    color: q.isEmpty ? c.textDim : c.text,
                                    fontWeight: q.isEmpty ? FontWeight.w400 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(side, Space.s16, side, 0),
            child: Wrap(
              spacing: Space.s12,
              runSpacing: Space.s12,
              children: [
                for (final t in view.topics)
                  TvTopicChip(
                    key: YouTubeHomeKeys.chip(t.id),
                    topic: t,
                    selected: t.id == view.topic.id,
                    focus: view.focus,
                    onSelect: () => view.onTopic(t),
                  ),
              ],
            ),
          ),
          FadeThroughSwitcher(
            child: KeyedSubtree(key: view.contentKey, child: _content(context, view)),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, YouTubeHomeView view) {
    final d = Dims.of(context);
    switch (view.status) {
      case HomeStatus.loading:
        return const TvHomeSkeleton();
      case HomeStatus.failed:
      case HomeStatus.empty:
        return _StatusCard(view: view);
      case HomeStatus.ready:
        break;
    }
    final topic = view.topic;
    final state = view.state;
    final tileWidth = d.tv ? tvTileWidth(context) : d.u(300);
    final billboard = TvBillboard(
      key: YouTubeHomeKeys.hero,
      focus: view.focus,
      items: heroFor(topic, state),
      kicker: kickerFor(topic, state),
      kickerIcon: topic.icon,
      error: state.error,
      onPlay: (v) => playVideo(context, v, source: topic.railId),
      onRetry: view.onRetry,
      onDetails: (v) => showVideoDetails(context, v, source: topic.railId),
      actionKey: YouTubeHomeKeys.heroPlay,
      detailsKey: YouTubeHomeKeys.heroDetails,
    );
    if (topic.forYou) {
      return Column(
        key: YouTubeHomeKeys.topic(topic.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          billboard,
          SizedBox(height: d.tv ? Space.s24 : Space.s16),
          for (final rail in state.rails)
            FocusRail(
              key: ValueKey('yt-row-${rail.id}'),
              title: rail.title,
              count: rail.items.length,
              section: view.focus,
              spacing: d.tv ? tvRailGap(tileWidth) : null,
              itemBuilder: (_, i) => SizedBox(
                width: tileWidth,
                child: VideoTileBody(
                  item: rail.items[i],
                  thumbnailHeight: d.tv ? tileWidth * 9 / 16 : null,
                  progress: rail.progress[rail.items[i].videoId],
                ),
              ),
              onSelect: (i) => playVideo(context, rail.items[i], source: rail.id),
              onMenu: (i) => showVideoDetails(context, rail.items[i], source: rail.id),
            ),
        ],
      );
    }
    final rail = view.rail!;
    final side = d.phone ? Space.s8 : Space.s16;
    return Column(
      key: YouTubeHomeKeys.topic(topic.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        billboard,
        Padding(
          padding: EdgeInsets.fromLTRB(side, Space.s24, side, Space.s24),
          child: Wrap(
            spacing: tvRailGap(tileWidth),
            runSpacing: Space.s24,
            children: [
              for (final v in rail.items)
                SizedBox(
                  width: tileWidth,
                  child: FocusCard(
                    key: ValueKey('yt-tile-${v.videoId}'),
                    section: view.focus,
                    onActivate: () => playVideo(context, v, source: rail.id),
                    child: VideoTileBody(
                      item: v,
                      thumbnailHeight: tileWidth * 9 / 16,
                      progress: rail.progress[v.videoId],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The shape of the TV home while the feed loads.
class TvHomeSkeleton extends StatelessWidget {
  const TvHomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final tile = d.tv ? tvTileWidth(context) : d.u(300);
    final height = (MediaQuery.sizeOf(context).height * 0.44).clamp(190.0, 460.0);
    final side = d.phone ? Space.s8 : Space.s16;
    return Shimmer(
      key: YouTubeHomeKeys.skeleton,
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, Space.s12, side, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: height, radius: Radii.hero),
            const SizedBox(height: Space.s24),
            const SkeletonBox(width: 200, height: 20, radius: 6),
            const SizedBox(height: Space.s12),
            ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    for (var i = 0; i < 6; i++) ...[
                      if (i > 0) SizedBox(width: tvRailGap(tile)),
                      SizedBox(width: tile, child: VideoCardSkeleton(thumbnailHeight: tile * 9 / 16)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.view});

  final YouTubeHomeView view;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final (title, line) = statusText(view);
    final side = d.phone ? Space.s8 : Space.s16;
    return Container(
      key: YouTubeHomeKeys.error,
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(side, Space.s16, side, 0),
      padding: const EdgeInsets.all(Space.s32),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.hero),
        border: Border.all(color: c.glassEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon(view), size: 48, color: c.textDim),
          const SizedBox(height: Space.s12),
          Text(title, style: d.type.h1),
          const SizedBox(height: Space.s4),
          Text(line, style: TextStyle(color: c.textDim, fontSize: d.t(16))),
          const SizedBox(height: Space.s24),
          FocusCard(
            key: YouTubeHomeKeys.retry,
            section: view.focus,
            radius: Radii.pill,
            onActivate: view.onRetry,
            child: const ActionLabel(icon: Icons.refresh_rounded, text: 'Retry', primary: true),
          ),
        ],
      ),
    );
  }
}

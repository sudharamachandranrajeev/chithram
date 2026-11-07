import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/common/motion_kit.dart';
import '../../../ui/common/pill_button.dart';
import '../../../ui/common/search_page.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/common/video_card.dart';
import '../../../ui/tv/focus_card.dart';
import '../phone/phone_video_card.dart';
import '../youtube_results.dart';
import '../youtube_search_controller.dart';
import 'video_details.dart';
import 'youtube_home_keys.dart';
import 'youtube_search_field.dart';

/// Opens YouTube results for [query] over the YouTube home, coming in on the
/// shared axis. The home stays as it was under it, so Back (the system's,
/// the desktop title bar's, Esc) returns to it with its scroll and topic.
/// A TV gets the D-pad search page, already searched.
Future<void> openYouTubeResults(BuildContext context, String query) {
  final tv = Dims.of(context).tv;
  return Navigator.of(context).push(
    sharedAxisRoute<void>((_) => tv ? _TvResults(query: query) : YouTubeResultsPage(query: query)),
  );
}

/// How many result columns fit [width] on a desktop: cards of about 300 dp.
int resultColumns(double width) => (width / 300).floor().clamp(2, 6);

/// YouTube results for pointer and touch: the search field (pre-filled, to
/// refine), then a grid of cards on a desktop or a column of them on a
/// phone, cascading in. More load as the end comes into view.
class YouTubeResultsPage extends StatefulWidget {
  const YouTubeResultsPage({super.key, required this.query});

  final String query;

  @override
  State<YouTubeResultsPage> createState() => _YouTubeResultsPageState();
}

class _YouTubeResultsPageState extends State<YouTubeResultsPage> {
  late final _field = TextEditingController(text: widget.query);
  YouTubeSearchController? _results;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_results == null) {
      final results = YouTubeSearchController(AppServices.of(context).youtube)..addListener(_changed);
      _results = results;
      unawaited(results.search(widget.query));
    }
  }

  @override
  void dispose() {
    _results?.dispose();
    _field.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _search(String q) => unawaited(_results!.search(q));

  void _nearEnd() {
    final r = _results!;
    if (r.continuation != null && !r.loading) Future.microtask(r.loadMore);
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final results = _results!;
    final gutter = d.phone ? Space.s16 : d.gutter;
    final firstLoad = results.loading && results.items.isEmpty;
    final Widget body;
    if (firstLoad) {
      body = _SkeletonSliver(gutter: gutter);
    } else if (results.error != null) {
      body = SliverToBoxAdapter(
        child: _Message(
          icon: Icons.cloud_off_rounded,
          text: results.error!,
          onRetry: () => _search(results.query),
        ),
      );
    } else if (results.searched && results.items.isEmpty) {
      body = SliverToBoxAdapter(
        child: _Message(icon: Icons.search_off_rounded, text: 'No results for “${results.query}”.'),
      );
    } else if (d.phone) {
      body = PhoneVideoSliver(items: results.items, onOpen: (v) => playVideo(context, v), onNearEnd: _nearEnd);
    } else {
      body = SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        sliver: SliverLayoutBuilder(
          builder: (context, box) {
            final columns = resultColumns(box.crossAxisExtent);
            final cell = (box.crossAxisExtent - Space.s16 * (columns - 1)) / columns;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: Space.s24,
                crossAxisSpacing: Space.s16,
                // The 16:9 thumbnail plus room for two title lines and the meta
                // line (scaled with the text), so a short title leaves no
                // tall empty card.
                mainAxisExtent: cell * 9 / 16 + Space.s24 + MediaQuery.textScalerOf(context).scale(68),
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                if (i >= results.items.length - 3) _nearEnd();
                final v = results.items[i];
                return StaggeredEntrance(
                  index: i % 20,
                  child: VideoCard(
                    key: ValueKey('yt-result-${v.videoId}'),
                    item: v,
                    onOpen: () => playVideo(context, v),
                    onDetails: () => showVideoDetails(context, v),
                  ),
                );
              }, childCount: results.items.length),
            );
          },
        ),
      );
    }
    return Material(
      key: YouTubeHomeKeys.results,
      color: c.background,
      child: SafeArea(
        child: CustomScrollView(
          key: const PageStorageKey<String>('yt-results-scroll'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(d.phone ? Space.s4 : gutter - Space.s8, Space.s12, gutter, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    IconButton(
                      key: YouTubeHomeKeys.resultsBack,
                      tooltip: 'Back',
                      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: Space.s8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: YouTubeSearchField(key: YouTubeHomeKeys.resultsField, controller: _field, onSubmit: _search),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, Space.s24, gutter, Space.s16),
              sliver: SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: Motion.of(context).expandTime,
                  // Left-aligned like the field above (the default centres).
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    results.query.isEmpty ? 'Search YouTube' : 'Results for “${results.query}”',
                    key: ValueKey(results.query),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: d.type.h1,
                  ),
                ),
              ),
            ),
            body,
            if (results.loading && results.items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, Space.s24, gutter, 0),
                  child: Shimmer(
                    child: Row(
                      children: [
                        for (var i = 0; i < (d.phone ? 1 : 3); i++) ...[
                          if (i > 0) const SizedBox(width: Space.s16),
                          const Expanded(child: VideoCardSkeleton()),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: Space.s32)),
          ],
        ),
      ),
    );
  }
}

/// A grid (desktop) or column (phone) of card skeletons while the first
/// page of results loads.
class _SkeletonSliver extends StatelessWidget {
  const _SkeletonSliver({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        key: YouTubeHomeKeys.skeleton,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: LayoutBuilder(
          builder: (context, box) {
            final columns = d.phone ? 1 : resultColumns(box.maxWidth);
            final rows = d.phone ? 3 : 2;
            return Shimmer(
              child: Column(
                children: [
                  for (var r = 0; r < rows; r++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < columns; i++) ...[
                            if (i > 0) const SizedBox(width: Space.s16),
                            const Expanded(child: VideoCardSkeleton()),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// An icon, a line of text and, with [onRetry], a Retry button.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    return Padding(
      key: YouTubeHomeKeys.resultsStatus,
      padding: const EdgeInsets.symmetric(horizontal: Space.s24, vertical: Space.s48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: c.textDim),
          const SizedBox(height: Space.s16),
          Text(text, textAlign: TextAlign.center, style: d.type.body.copyWith(color: c.textDim)),
          if (onRetry != null) ...[
            const SizedBox(height: Space.s16),
            d.phone
                ? FilledButton.tonalIcon(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: const StadiumBorder()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  )
                : DesktopPill(icon: Icons.refresh_rounded, label: 'Retry', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

/// TV results: the D-pad search page with [query] typed in and searched,
/// its bar ready to refine. Back returns to the YouTube home.
class _TvResults extends StatefulWidget {
  const _TvResults({required this.query});

  final String query;

  @override
  State<_TvResults> createState() => _TvResultsState();
}

class _TvResultsState extends State<_TvResults> {
  final _focus = SectionFocus();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.focus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    key: YouTubeHomeKeys.results,
    color: ChithramColors.of(context).background,
    child: SafeArea(
      child: Overscan(
        child: SearchPage(focus: _focus, youtubeOnly: true, initialQuery: widget.query),
      ),
    ),
  );
}

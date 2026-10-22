import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;
import 'package:iptv/iptv.dart';

import '../../core/services.dart';
import '../../features/youtube/phone/phone_video_card.dart';
import '../../features/youtube/youtube_search_controller.dart';
import '../../intake/intake.dart';
import '../../player/play_request.dart';
import '../../theme.dart';
import '../text_entry.dart';
import 'phone_widgets.dart';

/// Search (and the YouTube tab, with [youtubeOnly]) on a phone: a search bar
/// with the system keyboard at the top, then vertical sections of results.
/// Nothing is searched while typing; pull down to search again.
class PhoneSearchPage extends StatefulWidget {
  const PhoneSearchPage({super.key, this.youtubeOnly = false, this.initialQuery});

  final bool youtubeOnly;

  /// Typed in and searched at once (text that arrived through intake).
  final String? initialQuery;

  @override
  State<PhoneSearchPage> createState() => _PhoneSearchPageState();
}

class _PhoneSearchPageState extends State<PhoneSearchPage> {
  late final _field = TextEditingController(text: widget.initialQuery);
  YouTubeSearchController? _results;
  List<StoredChannel> _channels = const [];
  var _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_results == null) {
      _results = YouTubeSearchController(AppServices.of(context).youtube)..addListener(_changed);
      if (_field.text.trim().isNotEmpty) Future.microtask(() => _search(_field.text));
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _results?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _search(String q) async {
    final iptv = AppServices.of(context).iptv;
    final generation = ++_generation;
    final run = _results!.search(q);
    if (!widget.youtubeOnly) {
      final found = q.trim().isEmpty ? const <StoredChannel>[] : await iptv.searchChannels(q);
      if (mounted && generation == _generation) setState(() => _channels = found);
    }
    await run;
  }

  Future<void> _openVideo(VideoItem v) async {
    final request = await AppServices.of(context).youtube.playRequest(v);
    if (mounted) await openPlayer(context, request);
  }

  Future<void> _openChannel(int i) =>
      openPlayer(context, AppServices.of(context).iptv.playRequest(_channels, i));

  Future<void> _openLink() async {
    final text = await askText(
      context,
      title: 'Open link',
      hint: 'YouTube link, playlist, magnet or media URL',
    );
    if (text == null || text.isEmpty || !mounted) return;
    await handleIntake(context, TextPayload(text));
  }

  String? _status(YouTubeSearchController r) {
    if (r.loading && r.items.isEmpty) return 'Searching...';
    if (r.error != null) return r.error;
    if (r.searched && r.items.isEmpty && _channels.isEmpty) return 'No results for "${r.query}".';
    if (!r.searched && _field.text.trim().isEmpty) {
      return widget.youtubeOnly ? 'Search YouTube.' : 'Unified search across your sources and YouTube.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results!;
    final status = _status(results);
    final showYoutubeTitle = !widget.youtubeOnly && results.items.isNotEmpty;
    return Column(
      children: [
        PhoneSearchBar(
          controller: _field,
          hint: widget.youtubeOnly ? 'Search YouTube' : 'Search titles and channels',
          onSearch: _search,
          autofocus: widget.initialQuery == null,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _search(_field.text),
            child: CustomScrollView(
              key: PageStorageKey<String>('phone-${widget.youtubeOnly ? 'youtube' : 'search'}-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (status != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      key: const ValueKey('search-status'),
                      padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 8),
                      child: Text(status, style: const TextStyle(color: ChithramColors.textDim)),
                    ),
                  ),
                if (!widget.youtubeOnly)
                  SliverToBoxAdapter(
                    child: ListTile(
                      key: const ValueKey('search-open-link'),
                      minTileHeight: 56,
                      leading: const Icon(Icons.link_rounded),
                      title: const Text('Open link'),
                      subtitle: const Text('YouTube, magnet or media URL'),
                      onTap: _openLink,
                    ),
                  ),
                if (_channels.isNotEmpty && !widget.youtubeOnly) ...[
                  const SliverToBoxAdapter(child: PhoneSectionTitle('Live TV channels')),
                  SliverList.builder(
                    itemCount: _channels.length,
                    itemBuilder: (context, i) => ListTile(
                      key: ValueKey('search-channel-$i'),
                      minTileHeight: 56,
                      leading: const Icon(Icons.tv_rounded),
                      title: Text(_channels[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _openChannel(i),
                    ),
                  ),
                ],
                if (showYoutubeTitle) const SliverToBoxAdapter(child: PhoneSectionTitle('YouTube')),
                PhoneVideoSliver(
                  items: results.items,
                  onOpen: _openVideo,
                  onNearEnd: () => Future.microtask(results.loadMore),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

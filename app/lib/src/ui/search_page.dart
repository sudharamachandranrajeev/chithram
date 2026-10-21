import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:innertube/innertube.dart' hide Page;
import 'package:iptv/iptv.dart';

import '../core/services.dart';
import '../features/youtube/youtube_results.dart';
import '../features/youtube/youtube_search_controller.dart';
import '../intake/intake.dart';
import '../player/play_request.dart';
import '../theme.dart';
import 'dims.dart';
import 'focus_card.dart';
import 'focus_rail.dart';
import 'keyboard.dart';
import 'text_entry.dart';

/// Search with an on-screen D-pad keyboard (a TextField is avoided on TV:
/// flutter/flutter#147772). On desktop, typing on a hardware keyboard also
/// works: letters, digits and Backspace.
///
/// Pressing Search looks up YouTube videos and, on the global page, matching
/// Live TV channels. Nothing is searched while typing. [youtubeOnly] gives the
/// YouTube section: same keyboard and results, without the channel rail.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.focus, this.youtubeOnly = false});

  final SectionFocus focus;
  final bool youtubeOnly;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';
  YouTubeSearchController? _results;
  List<StoredChannel> _channels = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _results ??= YouTubeSearchController(AppServices.of(context).youtube)
      ..addListener(_changed);
  }

  @override
  void dispose() {
    _results?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _search() async {
    final q = _query;
    final results = _results!;
    final iptv = AppServices.of(context).iptv;
    final run = results.search(q);
    if (!widget.youtubeOnly) {
      final found = await iptv.searchChannels(q);
      if (mounted) setState(() => _channels = found);
    }
    await run;
  }

  Future<void> _openVideo(VideoItem v) async {
    final request = await AppServices.of(context).youtube.playRequest(v);
    if (mounted) await openPlayer(context, request);
  }

  Future<void> _openChannel(int i) async {
    final iptv = AppServices.of(context).iptv;
    await openPlayer(context, iptv.playRequest(_channels, i));
  }

  Future<void> _openLink() async {
    final text = await askText(
      context,
      title: 'Open link',
      hint: 'YouTube link, playlist, magnet or media URL',
    );
    if (text == null || text.isEmpty || !mounted) return;
    await handleIntake(context, TextPayload(text));
  }

  void _add(String c) => setState(() => _query += c);
  void _backspace() {
    if (_query.isNotEmpty)
      setState(() => _query = _query.substring(0, _query.length - 1));
  }

  void _clear() => setState(() => _query = '');

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && RegExp(r'^[a-zA-Z0-9]$').hasMatch(ch)) {
      _add(ch.toLowerCase());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final pad = d.phone ? 12.0 : 28.0;
    final results = _results!;
    final title = widget.youtubeOnly ? 'YouTube' : 'Search';
    final subtitle = widget.youtubeOnly
        ? 'Search YouTube.'
        : 'Unified search across your sources.';
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: CustomScrollView(
        // The first row of results is built (and reachable by D-pad) at once.
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        key: PageStorageKey<String>(
          '${widget.youtubeOnly ? 'youtube' : 'search'}-scroll',
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: d.t(32),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: ChithramColors.textDim,
                      fontSize: d.t(14),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: ChithramColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ChithramColors.surfaceHigh),
                    ),
                    child: Stack(
                      children: [
                        if (_query.isEmpty)
                          Text(
                            'Type a title',
                            style: TextStyle(
                              color: ChithramColors.textDim,
                              fontSize: d.t(18),
                            ),
                          ),
                        Text(
                          _query,
                          key: const ValueKey('search-query'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: d.t(18),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  OnScreenKeyboard(
                    focus: widget.focus,
                    onChar: _add,
                    onBackspace: _backspace,
                    onClear: _clear,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _ActionCard(
                        key: const ValueKey('search-go'),
                        focus: widget.focus,
                        icon: Icons.search_rounded,
                        label: 'Search',
                        onActivate: _search,
                      ),
                      if (!widget.youtubeOnly) ...[
                        _ActionCard(
                          key: const ValueKey('search-open-link'),
                          focus: widget.focus,
                          icon: Icons.link_rounded,
                          label: 'Open link',
                          onActivate: _openLink,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _status(d, results),
                ],
              ),
            ),
          ),
          if (_channels.isNotEmpty && !widget.youtubeOnly)
            SliverToBoxAdapter(
              child: FocusRail(
                title: 'Live TV channels',
                count: _channels.length,
                section: widget.focus,
                onSelect: _openChannel,
                itemBuilder: (context, i) =>
                    PosterTile(label: _channels[i].name, hue: 200.0 + i * 23),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 14, pad, 24),
            sliver: VideoResultsSliver(
              items: results.items,
              section: widget.focus,
              onOpen: _openVideo,
              onNearEnd: () => Future.microtask(results.loadMore),
            ),
          ),
        ],
      ),
    );
  }

  Widget _status(Dims d, YouTubeSearchController results) {
    final String? text;
    if (results.loading && results.items.isEmpty) {
      text = 'Searching...';
    } else if (results.error != null) {
      text = results.error;
    } else if (results.searched && results.items.isEmpty && _channels.isEmpty) {
      text = 'No results for "${results.query}".';
    } else if (!results.searched) {
      text = 'Choose Search to look up "$_query".';
    } else {
      text = null;
    }
    if (text == null || (_query.isEmpty && !results.searched))
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        key: const ValueKey('search-status'),
        style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.focus,
    required this.icon,
    required this.label,
    required this.onActivate,
  });

  final SectionFocus focus;
  final IconData icon;
  final String label;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return FocusCard(
      section: focus,
      radius: 12,
      onActivate: onActivate,
      child: Container(
        height: d.phone ? 44 : d.u(52),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        color: ChithramColors.surfaceHigh,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: d.t(22)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: d.t(16), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

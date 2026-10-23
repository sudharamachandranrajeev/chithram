import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:innertube/innertube.dart' hide Page;
import 'package:iptv/iptv.dart';

import '../../core/services.dart';
import '../../features/youtube/youtube_results.dart';
import '../../find/find_api.dart';
import '../../features/youtube/youtube_search_controller.dart';
import '../../intake/intake.dart';
import '../../player/play_request.dart';
import '../../theme.dart';
import 'dims.dart';
import '../phone/phone_search_page.dart';
import '../tv/focus_card.dart';
import '../tv/focus_rail.dart';
import '../tv/keyboard.dart';
import 'form_factor.dart';
import 'text_entry.dart';

/// Search with an on-screen D-pad keyboard on TV and desktop (a TextField is
/// avoided on TV: flutter/flutter#147772). On desktop, typing on a hardware
/// keyboard also works: letters, digits and Backspace. A phone uses a real
/// TextField, so the system keyboard appears.
///
/// Pressing Search looks up YouTube videos and, on the global page, matching
/// Live TV channels. Nothing is searched while typing. [youtubeOnly] gives the
/// YouTube section: same keyboard and results, without the channel rail.
class SearchPage extends StatelessWidget {
  const SearchPage({
    super.key,
    required this.focus,
    this.youtubeOnly = false,
    this.initialQuery,
  });

  final SectionFocus focus;
  final bool youtubeOnly;

  /// Typed in and searched at once (text that arrived through intake).
  final String? initialQuery;

  @override
  Widget build(BuildContext context) => FormSwitch(
    tv: _TvSearchPage(focus: focus, youtubeOnly: youtubeOnly, initialQuery: initialQuery),
    phone: PhoneSearchPage(youtubeOnly: youtubeOnly, initialQuery: initialQuery),
  );
}

class _TvSearchPage extends StatefulWidget {
  const _TvSearchPage({required this.focus, required this.youtubeOnly, this.initialQuery});

  final SectionFocus focus;
  final bool youtubeOnly;
  final String? initialQuery;

  @override
  State<_TvSearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_TvSearchPage> {
  String _query = '';
  late final _field = TextEditingController(text: widget.initialQuery);
  YouTubeSearchController? _results;
  List<StoredChannel> _channels = const [];

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_results == null) {
      _results = YouTubeSearchController(AppServices.of(context).youtube)
        ..addListener(_changed);
      if (_query.trim().isNotEmpty) Future.microtask(_search);
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
    if (Dims.of(context).phone) return KeyEventResult.ignored;
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
                    child: d.phone
                        ? TextField(
                            key: const ValueKey('search-field'),
                            controller: _field,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            keyboardType: TextInputType.text,
                            style: TextStyle(fontSize: d.t(18)),
                            decoration: InputDecoration.collapsed(
                              hintText: 'Type a title',
                              hintStyle: TextStyle(
                                color: ChithramColors.textDim,
                                fontSize: d.t(18),
                              ),
                            ),
                            onChanged: (v) => _query = v,
                            onSubmitted: (v) {
                              _query = v;
                              _search();
                            },
                          )
                        : Stack(
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
                  if (!d.phone)
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
                        if (_query.trim().isNotEmpty)
                          _ActionCard(
                            key: const ValueKey('search-find-sources'),
                            focus: widget.focus,
                            icon: Icons.travel_explore_rounded,
                            label: "Find sources for '${_query.trim()}'",
                            onActivate: () => openFindSources(context, TextQuery(_query.trim())),
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

/// Opens search with [text] already typed in and searched (the "Search for
/// this text" action of the intake path).
Future<void> openSearch(BuildContext context, String text) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => _SearchRoute(text: text)));
}

class _SearchRoute extends StatefulWidget {
  const _SearchRoute({required this.text});

  final String text;

  @override
  State<_SearchRoute> createState() => _SearchRouteState();
}

class _SearchRouteState extends State<_SearchRoute> {
  final _focus = SectionFocus();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Overscan(
          child: SearchPage(focus: _focus, initialQuery: widget.text),
        ),
      ),
    );
  }
}

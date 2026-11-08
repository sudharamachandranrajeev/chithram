import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/redact.dart';
import '../core/services.dart';
import '../features/torrents/torrent_actions.dart';
import '../features/torrents/torrent_logic.dart';
import '../player/play_request.dart';
import '../theme.dart';
import '../ui/common/dims.dart';
import 'find_api.dart';

/// How the Find page orders results.
enum FindSort {
  seeders('Most seeders'),
  size('Largest'),
  newest('Newest');

  const FindSort(this.label);
  final String label;
}

/// [results] ordered by [sort]; ties (and missing values) fall back to
/// seeders, then title.
List<FindResult> sortResults(List<FindResult> results, FindSort sort) {
  int bySeeders(FindResult a, FindResult b) => (b.seeders ?? -1).compareTo(a.seeders ?? -1);
  int byTitle(FindResult a, FindResult b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
  final out = List.of(results);
  out.sort((a, b) {
    final c = switch (sort) {
      FindSort.seeders => bySeeders(a, b),
      FindSort.size => (b.sizeBytes ?? -1).compareTo(a.sizeBytes ?? -1),
      FindSort.newest => (b.published?.millisecondsSinceEpoch ?? -1).compareTo(a.published?.millisecondsSinceEpoch ?? -1),
    };
    if (c != 0) return c;
    final s = bySeeders(a, b);
    return s != 0 ? s : byTitle(a, b);
  });
  return out;
}

/// The infohash of a torrent result (its own, or from its magnet), lower case.
String? resultHash(FindResult r) {
  final h = r.infoHash?.trim().toLowerCase();
  if (h != null && RegExp(r'^[0-9a-f]{40}$').hasMatch(h)) return h;
  final m = r.magnet;
  return m == null ? null : btihFromMagnet(m);
}

/// The magnet to add for [r]: its own, or one built from the infohash.
String? resultMagnet(FindResult r) {
  final m = r.magnet;
  if (m != null && btihFromMagnet(m) != null) return m;
  final h = resultHash(r);
  if (h == null) return null;
  return 'magnet:?xt=urn:btih:$h&dn=${Uri.encodeComponent(r.title)}';
}

/// Adds [r] to [into] unless the same torrent is there already; then the
/// copy with more seeders stays. True when [into] changed.
bool mergeResult(List<FindResult> into, FindResult r) {
  final h = r.kind == ResultKind.torrent ? resultHash(r) : null;
  if (h != null) {
    final i = into.indexWhere((x) => x.kind == ResultKind.torrent && resultHash(x) == h);
    if (i >= 0) {
      if ((r.seeders ?? -1) <= (into[i].seeders ?? -1)) return false;
      into[i] = r;
      return true;
    }
  }
  into.add(r);
  return true;
}

/// "today", "5d", "3mo", "2y" since [t].
String ageLabel(DateTime t, DateTime now) {
  final days = now.difference(t).inDays;
  if (days < 1) return 'today';
  if (days < 60) return '${days}d';
  if (days < 730) return '${days ~/ 30}mo';
  return '${days ~/ 365}y';
}

/// The second line of a result: size, seeders/leechers, age, where from.
String resultLine(FindResult r, String provider, DateTime now) => [
      if (r.sizeBytes != null) formatBytes(r.sizeBytes!),
      if (r.seeders != null) '${r.seeders} seeders${r.leechers != null ? ' / ${r.leechers} leechers' : ''}',
      if (r.published != null) ageLabel(r.published!, now),
      if (r.kind == ResultKind.video) 'video',
      if (r.kind == ResultKind.live) 'live',
      provider,
    ].join(' · ');

enum _State { searching, done, failed }

/// Asks every available provider and lists what they find: sorted, one row
/// per torrent. Select a result to stream it, download it or copy its magnet.
class FindPage extends StatefulWidget {
  const FindPage({super.key, required this.query});

  final FindQuery query;

  @override
  State<FindPage> createState() => _FindPageState();
}

class _FindPageState extends State<FindPage> {
  final _cancel = CancelToken();
  final _results = <FindResult>[];
  final _subs = <StreamSubscription<FindResult>>[];
  final _providers = <String, FindProvider>{};
  final _state = <String, _State>{};
  final _counts = <String, int>{};
  final _unavailable = <String>[];
  FindSort _sort = FindSort.seeders;
  bool _started = false;

  String get _what => switch (widget.query) {
        TitleQuery(:final title) => title,
        EpisodeQuery(:final show, :final season, :final episode) => '$show S${season}E$episode',
        TextQuery(:final text) => text,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppServices.of(context);
    for (final s in services.findSources) {
      for (final p in s.providers.value) {
        if (!p.available) {
          _unavailable.add('${p.label}: ${p.unavailableReason ?? 'unavailable'}');
          continue;
        }
        _providers[p.id] = p;
        _state[p.id] = _State.searching;
        _subs.add(p.search(widget.query, _cancel).listen(
          (r) {
            if (!mounted) return;
            _counts[p.id] = (_counts[p.id] ?? 0) + 1;
            setState(() => mergeResult(_results, r));
          },
          onError: (Object _) {
            if (mounted) setState(() => _state[p.id] = _State.failed);
          },
          onDone: () {
            if (mounted && _state[p.id] == _State.searching) setState(() => _state[p.id] = _State.done);
          },
        ));
      }
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  String _label(String providerId) => _providers[providerId]?.label ?? providerId;

  String get _statusLine => [
        for (final id in _providers.keys)
          '${_label(id)}: ${switch (_state[id]!) {
            _State.searching => 'searching...',
            _State.done => '${_counts[id] ?? 0} found',
            _State.failed => 'failed',
          }}',
      ].join(' · ');

  void _say(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _open(FindResult r) async {
    final p = _providers[r.providerId];
    if (p == null) return;
    if (r.kind != ResultKind.torrent) {
      try {
        final req = await p.playRequest(r);
        if (mounted) await openPlayer(context, req);
      } catch (e) {
        _say(redactText('$e'));
      }
      return;
    }
    final magnet = resultMagnet(r);
    final canFetch = r.hasTorrentFile;
    if (magnet == null && !canFetch) {
      _say('This result has no magnet or .torrent');
      return;
    }
    Future<Uint8List> fetch() => p.fetchTorrent(r);
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(r.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        children: [
          SimpleDialogOption(
            key: const ValueKey('find-stream'),
            onPressed: () => Navigator.pop(c, 'stream'),
            child: const ListTile(leading: Icon(Icons.play_arrow_rounded), title: Text('Stream')),
          ),
          SimpleDialogOption(
            key: const ValueKey('find-files'),
            onPressed: () => Navigator.pop(c, 'files'),
            child: const ListTile(leading: Icon(Icons.list_rounded), title: Text('Stream: choose a file')),
          ),
          SimpleDialogOption(
            key: const ValueKey('find-download'),
            onPressed: () => Navigator.pop(c, 'download'),
            child: const ListTile(leading: Icon(Icons.download_rounded), title: Text('Download')),
          ),
          if (magnet != null)
            SimpleDialogOption(
              key: const ValueKey('find-copy'),
              onPressed: () => Navigator.pop(c, 'copy'),
              child: const ListTile(leading: Icon(Icons.copy_rounded), title: Text('Copy magnet link')),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'stream':
      case 'files':
        await streamTorrent(context, magnet: magnet, fetch: fetch, chooseFile: choice == 'files');
      case 'download':
        await downloadTorrent(context, magnet: magnet, fetch: fetch);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: magnet!));
        _say('Magnet link copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final now = DateTime.now();
    final sorted = sortResults(_results, _sort);
    final searching = _state.values.any((s) => s == _State.searching);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Find '$_what'", maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              key: const ValueKey('find-new-search'),
              tooltip: 'New search',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => unawaited(searchTorrents(context)),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (searching) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in FindSort.values)
                    ChoiceChip(
                      key: ValueKey('find-sort-${s.name}'),
                      label: Text(s.label),
                      selected: _sort == s,
                      onSelected: (_) => setState(() => _sort = s),
                    ),
                ],
              ),
            ),
            if (_providers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Text(_statusLine, style: TextStyle(color: colors.textDim, fontSize: d.t(12))),
              ),
            Expanded(
              child: sorted.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _providers.isEmpty
                              ? [
                                  'No search providers yet. Install a search plugin or add a Torznab '
                                      'endpoint in Settings.',
                                  ..._unavailable,
                                ].join('\n')
                              : searching
                                  ? 'Searching...'
                                  : 'Nothing found.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textDim, fontSize: d.t(16)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: sorted.length,
                      itemBuilder: (_, i) {
                        final r = sorted[i];
                        return ListTile(
                          key: ValueKey('find-result-$i'),
                          autofocus: i == 0,
                          leading: Icon(
                            switch (r.kind) {
                              ResultKind.torrent => Icons.downloading_rounded,
                              ResultKind.video => Icons.smart_display_outlined,
                              ResultKind.live => Icons.live_tv_rounded,
                            },
                            color: (r.seeders ?? 1) > 0 ? colors.accent : colors.textDim,
                          ),
                          title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(resultLine(r, _label(r.providerId), now)),
                          onTap: () => unawaited(_open(r)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

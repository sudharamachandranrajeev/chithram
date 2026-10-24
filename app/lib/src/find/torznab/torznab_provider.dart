import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:torznab/torznab.dart';

import '../../features/torrents/torrent_logic.dart';
import '../../player/play_request.dart';
import '../find_api.dart';
import 'torznab_service.dart';

/// Find sources: one provider per enabled Torznab endpoint.
class TorznabProviders implements FindProviderSource {
  TorznabProviders(this.service) {
    service.addListener(_sync);
    _sync();
  }

  final TorznabService service;
  final _providers = ValueNotifier<List<FindProvider>>(const []);

  var _loading = false;

  /// The first look at the list loads the endpoints (the database stays
  /// unopened until Find sources or a source list asks).
  @override
  ValueListenable<List<FindProvider>> get providers {
    if (!_loading) {
      _loading = true;
      unawaited(service.load());
    }
    return _providers;
  }

  void _sync() {
    final next = [for (final e in service.enabled) TorznabProvider(service, e)];
    final same =
        next.length == _providers.value.length &&
        [for (var i = 0; i < next.length; i++) next[i].id == _providers.value[i].id].every((b) => b);
    if (!same) _providers.value = next;
  }

  void dispose() {
    service.removeListener(_sync);
    _providers.dispose();
  }
}

class TorznabProvider implements FindProvider {
  TorznabProvider(this.service, this.endpoint);

  final TorznabService service;
  final TorznabEndpoint endpoint;
  final _links = <String, String>{};

  @override
  String get id => 'torznab:${endpoint.id}';
  @override
  String get label => endpoint.name;
  @override
  bool get available => endpoint.enabled;
  @override
  String? get unavailableReason => endpoint.enabled ? null : 'Disabled in Settings';

  static String _key(String title, int? size) => '$title|${size ?? ''}';

  @override
  Stream<FindResult> search(FindQuery q, CancelToken c) async* {
    final (text, cats, season, episode, imdb, tvdb) = switch (q) {
      TitleQuery() => (
        '${q.title}${q.year == null ? '' : ' ${q.year}'}',
        [2000],
        null as int?,
        null as int?,
        null as String?,
        null as int?,
      ),
      EpisodeQuery() => (q.show, [5000], q.season as int?, q.episode as int?, q.imdbId, q.tvdbId),
      TextQuery() => (q.text, [2000, 5000], null, null, null, null),
    };
    final items = await service.search(
      endpoint,
      query: text,
      cats: cats,
      season: season,
      episode: episode,
      imdbId: imdb,
      tvdbId: tvdb,
    );
    for (final i in items) {
      if (c.cancelled) return;
      final hash = i.infoHash ?? (i.magnet == null ? null : btihFromMagnet(i.magnet!));
      final url = i.torrentUrl;
      if (url != null) _links[_key(i.title, i.sizeBytes)] = url;
      yield FindResult(
        providerId: id,
        title: i.title,
        kind: ResultKind.torrent,
        sizeBytes: i.sizeBytes,
        seeders: i.seeders,
        leechers: i.leechers,
        infoHash: hash,
        magnet: i.magnet,
        detailsUrl: i.detailsUrl,
        published: i.published,
        hasTorrentFile: url != null,
      );
    }
  }

  @override
  Future<Uint8List> fetchTorrent(FindResult r) {
    final url = _links[_key(r.title, r.sizeBytes)];
    if (url == null) throw TorznabException('This result has no torrent file');
    return service.fetchTorrent(endpoint, url);
  }

  @override
  Future<PlayRequest> playRequest(FindResult r) => throw UnsupportedError('Torznab results are torrents');
}

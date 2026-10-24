import 'dart:async';
import 'dart:typed_data';


import '../find/find_api.dart';
import '../player/play_request.dart';
import 'plugin_registry.dart';

/// One installed plugin as a Find provider (torrent results only).
class PluginFindProvider implements FindProvider {
  PluginFindProvider(this._registry, this.plugin);

  final PluginRegistry _registry;
  final InstalledPlugin plugin;

  /// result key -> the plugin's `link`, for the results with a .torrent link
  /// instead of a magnet (see [fetchTorrent]).
  final _links = <String, String>{};

  PluginFindProvider withPlugin(InstalledPlugin p) {
    final next = PluginFindProvider(_registry, p);
    next._links.addAll(_links);
    return next;
  }

  @override
  String get id => 'plugin:${plugin.id}';

  @override
  String get label => plugin.name;

  @override
  bool get available =>
      plugin.enabled &&
      plugin.health.status != PluginHealthStatus.blocked &&
      plugin.health.status != PluginHealthStatus.unavailable;

  @override
  String? get unavailableReason => switch (plugin.health.status) {
        PluginHealthStatus.blocked => 'Blocked: ${plugin.health.lastError ?? 'needs your attention'}',
        PluginHealthStatus.unavailable => _registry.unavailableReason ?? 'Plugins cannot run here',
        _ => plugin.enabled ? null : 'Disabled',
      };

  static String _key(String title, int? size) => '$title\u0001${size ?? -1}';

  @override
  Stream<FindResult> search(FindQuery q, CancelToken c) async* {
    final (text, cat) = switch (q) {
      TitleQuery(:final title, :final year) => ('$title${year == null ? '' : ' $year'}', 'movies'),
      EpisodeQuery(:final show, :final season, :final episode) => (
          '$show S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
          'tv'
        ),
      TextQuery(:final text) => (text, 'all'),
    };
    final run = _registry.search(plugin, text, cat: plugin.categoryFor(cat));
    final r = await Future.any<PluginSearch?>([run, c.whenCancelled.then((_) => null)]);
    if (r == null) return;
    for (final h in r.hits) {
      if (!h.isMagnet) _links[_key(h.name, h.sizeBytes)] = h.link;
      yield FindResult(
        providerId: id,
        title: h.name,
        kind: ResultKind.torrent,
        sizeBytes: h.sizeBytes,
        seeders: h.seeders,
        leechers: h.leechers,
        infoHash: h.infoHash,
        magnet: h.isMagnet ? h.link : null,
        detailsUrl: h.descLink,
        published: h.pubDate,
        hasTorrentFile: !h.isMagnet,
      );
    }
  }

  @override
  Future<Uint8List> fetchTorrent(FindResult r) async {
    final link = _links[_key(r.title, r.sizeBytes)];
    if (link == null) throw StateError('No torrent link for ${r.title}');
    return _registry.fetchTorrent(plugin, link);
  }

  @override
  Future<PlayRequest> playRequest(FindResult r) =>
      throw UnsupportedError('Plugin results are torrents; they open through the torrent screens');
}

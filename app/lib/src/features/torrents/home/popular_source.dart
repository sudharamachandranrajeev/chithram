import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torznab/torznab.dart';

import '../../../find/torznab/torznab_service.dart';
import '../torrent_logic.dart';
import 'popular_item.dart';

/// Something Torrent Home can ask for the latest releases of a kind. The user
/// added it: a Torznab endpoint or an installed search plugin.
abstract interface class PopularSource {
  String get id;
  String get label;

  /// The newest releases of [kind] the source lists (about 100).
  Future<List<PopularItem>> fetch(PopularKind kind);

  /// The .torrent for an item with no magnet and no infohash, at most 2 MiB.
  Future<Uint8List> fetchTorrent(PopularItem item);
}

/// Sources that are asked together, [concurrency] at a time.
class PopularGroup {
  const PopularGroup(this.sources, {this.concurrency = 2});
  final List<PopularSource> sources;
  final int concurrency;
}

/// The sources the user has now. Asked on every refresh, so installs and
/// removals show up without a restart.
abstract interface class PopularSources {
  Future<List<PopularGroup>> groups();
}

/// One Torznab endpoint: latest in Movies (2000) or TV (5000), limit 100, no query.
class TorznabPopularSource implements PopularSource {
  TorznabPopularSource(this.service, this.endpoint);

  final TorznabService service;
  final TorznabEndpoint endpoint;

  @override
  String get id => 'torznab:${endpoint.id}';
  @override
  String get label => endpoint.name;

  @override
  Future<List<PopularItem>> fetch(PopularKind kind) async {
    final items = await service.search(endpoint, cats: [if (kind == PopularKind.film) 2000 else 5000], limit: 100);
    return [
      for (final i in items)
        PopularItem(
          title: i.title,
          kind: kind,
          sourceId: id,
          sourceLabel: label,
          sizeBytes: i.sizeBytes,
          seeders: i.seeders,
          leechers: i.leechers,
          infoHash: i.infoHash ?? (i.magnet == null ? null : btihFromMagnet(i.magnet!)),
          magnet: i.magnet,
          torrentUrl: i.torrentUrl,
          detailsUrl: i.detailsUrl,
          published: i.published,
          categories: i.categories,
          sources: [label],
        ),
    ];
  }

  @override
  Future<Uint8List> fetchTorrent(PopularItem item) {
    final url = item.torrentUrl;
    if (url == null) throw TorznabException('This result has no torrent file');
    return service.fetchTorrent(endpoint, url);
  }
}

class TorznabPopularSources implements PopularSources {
  TorznabPopularSources(this.service);

  final TorznabService service;

  @override
  Future<List<PopularGroup>> groups() async {
    await service.load();
    final sources = [for (final e in service.enabled) TorznabPopularSource(service, e)];
    return sources.isEmpty ? const [] : [PopularGroup(sources, concurrency: 3)];
  }
}

/// One row of a plugin search (the nova3 fields Torrent Home uses).
class PluginHit {
  const PluginHit({
    required this.name,
    required this.link,
    this.descLink,
    this.size,
    this.seeds,
    this.leech,
    this.pubDate,
  });
  final String name, link;
  final String? descLink;
  final int? size, seeds, leech;

  /// Null when the plugin omits `pub_date`.
  final DateTime? pubDate;
}

/// An enabled plugin, as the plugin registry names it.
class PluginEngineRef {
  const PluginEngineRef(this.id, this.label);
  final String id, label;
}

/// How many plugin processes run at once: 1 on devices with 2 GB of RAM or
/// less, 2 on other phones and TVs, 4 on desktop.
int pluginConcurrency({required bool desktop, int? ramMb}) => desktop ? 4 : (ramMb != null && ramMb <= 2048 ? 1 : 2);

/// The seam to the plugin registry (feat/plugins): the enabled engines, a
/// search `NovaHost.search(engine, what, cat)` with `cat` `movies` or `tv`,
/// and the plugin's own torrent download. Query: the current year.
class PluginPopularSources implements PopularSources {
  PluginPopularSources({
    required this.enabled,
    required this.search,
    required this.download,
    required this.concurrency,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<List<PluginEngineRef>> Function() enabled;
  final Future<List<PluginHit>> Function(String engineId, String what, String category) search;
  final Future<Uint8List> Function(String engineId, String link) download;
  final int concurrency;
  final DateTime Function() _clock;

  @override
  Future<List<PopularGroup>> groups() async {
    final engines = await enabled();
    if (engines.isEmpty) return const [];
    return [
      PopularGroup([for (final e in engines) _PluginPopularSource(this, e)], concurrency: concurrency),
    ];
  }
}

class _PluginPopularSource implements PopularSource {
  _PluginPopularSource(this.owner, this.engine);

  final PluginPopularSources owner;
  final PluginEngineRef engine;

  @override
  String get id => 'plugin:${engine.id}';
  @override
  String get label => engine.label;

  @override
  Future<List<PopularItem>> fetch(PopularKind kind) async {
    final hits = await owner.search(engine.id, '${owner._clock().year}', kind == PopularKind.film ? 'movies' : 'tv');
    return [
      for (final h in hits)
        PopularItem(
          title: h.name,
          kind: kind,
          sourceId: id,
          sourceLabel: label,
          sizeBytes: h.size != null && h.size! >= 0 ? h.size : null,
          // nova3 reports -1 for "unknown".
          seeders: h.seeds != null && h.seeds! >= 0 ? h.seeds : null,
          leechers: h.leech != null && h.leech! >= 0 ? h.leech : null,
          infoHash: h.link.startsWith('magnet:') ? btihFromMagnet(h.link) : null,
          magnet: h.link.startsWith('magnet:') ? h.link : null,
          torrentUrl: h.link.startsWith('magnet:') ? null : h.link,
          detailsUrl: h.descLink,
          published: h.pubDate,
          sources: [label],
        ),
    ];
  }

  @override
  Future<Uint8List> fetchTorrent(PopularItem item) {
    final link = item.torrentUrl;
    if (link == null) throw StateError('no torrent link');
    return owner.download(engine.id, link);
  }
}

/// A source with fixed answers, for tests and the host harness.
class FixturePopularSource implements PopularSource {
  FixturePopularSource({
    this.id = 'fixture',
    this.label = 'Fixture',
    this.films = const [],
    this.tv = const [],
    this.error,
    this.delay = Duration.zero,
    Uint8List? torrentBytes,
  }) : torrentBytes = torrentBytes ?? Uint8List(0);

  @override
  final String id, label;
  final List<PopularItem> films, tv;

  /// Thrown from [fetch] when set.
  final Object? error;
  final Duration delay;
  final Uint8List torrentBytes;
  final calls = <PopularKind>[];

  @override
  Future<List<PopularItem>> fetch(PopularKind kind) async {
    calls.add(kind);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final e = error;
    if (e != null) throw e;
    return kind == PopularKind.film ? films : tv;
  }

  @override
  Future<Uint8List> fetchTorrent(PopularItem item) async => torrentBytes;
}

class FixturePopularSources implements PopularSources {
  FixturePopularSources(this.sources, {this.concurrency = 2});

  List<PopularSource> sources;
  final int concurrency;

  @override
  Future<List<PopularGroup>> groups() async =>
      sources.isEmpty ? const [] : [PopularGroup(sources, concurrency: concurrency)];
}

/// Desktop builds ask four plugins at once, other devices fewer.
bool get isDesktopPlatform => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

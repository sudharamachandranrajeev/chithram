import 'dart:convert';

import 'package:chithram_player/chithram_player.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart';

import '../../core/item_id.dart';
import '../../player/play_request.dart';
import 'add_playlist.dart';
import 'suggestions.dart';

/// The sources and channels the Live TV page shows.
class LiveTvSnapshot {
  const LiveTvSnapshot(this.sources, this.channels);

  final List<Source> sources;

  /// Channels by source id.
  final Map<String, List<StoredChannel>> channels;
}

/// Live TV sources and channels, over the `iptv` package. Nothing is fetched
/// until a source is added (by the user, after a confirmation for the
/// built-in suggestions) or refreshed.
class IptvService extends ChangeNotifier {
  IptvService({required IptvStore store, IptvHttp? http})
      : _store = store,
        _registry = SourceRegistry(store, http ?? DartIoHttp());

  final IptvStore _store;
  final SourceRegistry _registry;
  final _refreshing = <String>{};

  /// Source ids being downloaded right now.
  Set<String> get refreshing => Set.unmodifiable(_refreshing);

  Future<List<Source>> sources() => _registry.sources();

  Future<LiveTvSnapshot> snapshot() async {
    final sources = await _registry.sources();
    return LiveTvSnapshot(sources, {
      for (final s in sources) s.id: await _store.channels(s.id),
    });
  }

  Future<RefreshResult> addM3uUrl({required String name, required String url}) async {
    final id = 'm3u-${sha256.convert(utf8.encode(ItemId.normaliseUrl(url))).toString().substring(0, 12)}';
    await _registry.add(Source(id: id, kind: SourceKind.m3uUrl, name: name, location: url));
    return refresh(id);
  }

  /// Adds one of the built-in suggestions and downloads it. Call only after
  /// the user confirmed.
  Future<RefreshResult> addSuggestion(
    CatalogueSuggestion s, {
    String? country,
    String? language,
  }) async {
    await _registry.add(s.toSource(country: country, language: language));
    return refresh(s.sourceId);
  }

  Future<RefreshResult> refresh(String id) async {
    _refreshing.add(id);
    notifyListeners();
    try {
      return await _registry.refresh(id);
    } finally {
      _refreshing.remove(id);
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    await _registry.remove(id);
    notifyListeners();
  }

  Future<List<StoredChannel>> channels(String sourceId) => _store.channels(sourceId);

  /// Playable channels whose name contains [q] (case-insensitive).
  Future<List<StoredChannel>> searchChannels(String q, {int limit = 30}) async {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final out = <StoredChannel>[];
    for (final s in await sources()) {
      for (final c in await channels(s.id)) {
        if (c.playable && c.name.toLowerCase().contains(needle)) out.add(c);
        if (out.length >= limit) return out;
      }
    }
    return out;
  }

  /// A request for `list[index]`. Up and Down step through [list]; callers
  /// pass only the channels worth zapping to (no dead or missing ones).
  PlayRequest playRequest(List<StoredChannel> list, int index) {
    final c = list[index];
    return PlayRequest(
      itemId: ItemId.iptv(c.key),
      title: c.name,
      subtitle: c.group,
      artwork: c.logo,
      isLive: true,
      resolve: () async {
        final url = c.url ?? (await _registry.resolveUrl(c))?.toString();
        if (url == null) throw StateError('no stream URL for ${c.name}');
        return MediaSpec(videoUrl: url, headers: c.headers, isLive: true);
      },
      zap: _ChannelZap(this, list, index),
    );
  }

  /// Asks for a playlist URL and a name, then adds and downloads it. [url]
  /// prefills the prompt.
  Future<void> openAddPlaylist(BuildContext c, {String? url}) => addPlaylistFromUrl(c, this, url: url);
}

class _ChannelZap implements ZapList {
  _ChannelZap(this._service, this._list, this.initialIndex);

  final IptvService _service;
  final List<StoredChannel> _list;

  @override
  final int initialIndex;

  @override
  int get length => _list.length;

  @override
  String titleAt(int i) => _list[i].name;

  @override
  PlayRequest requestAt(int i) => _service.playRequest(_list, i);
}

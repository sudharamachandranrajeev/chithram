import 'dart:convert';

import 'package:chithram_player/chithram_player.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart';

import '../../core/item_id.dart';
import '../../player/play_request.dart';
import '../../ui/text_entry.dart';

/// Live TV sources and channels, over the `iptv` package. Stub: the add flow
/// is a single URL prompt; the Live TV work package replaces it.
class IptvService {
  IptvService({required IptvStore store, IptvHttp? http})
      : _store = store,
        _registry = SourceRegistry(store, http ?? DartIoHttp());

  final IptvStore _store;
  final SourceRegistry _registry;

  Future<List<Source>> sources() => _registry.sources();

  Future<RefreshResult> addM3uUrl({required String name, required String url}) async {
    final id = 'm3u-${sha256.convert(utf8.encode(ItemId.normaliseUrl(url))).toString().substring(0, 12)}';
    await _registry.add(Source(id: id, kind: SourceKind.m3uUrl, name: name, location: url));
    return _registry.refresh(id);
  }

  Future<RefreshResult> refresh(String id) => _registry.refresh(id);

  Future<void> remove(String id) => _registry.remove(id);

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

  /// Asks for a playlist URL and adds it. [url] prefills the prompt.
  Future<void> openAddPlaylist(BuildContext c, {String? url}) async {
    final entered = await askText(c, title: 'Playlist URL', hint: 'https://...', initial: url);
    if (entered == null || entered.isEmpty) return;
    final host = Uri.tryParse(entered)?.host ?? '';
    await addM3uUrl(name: host.isEmpty ? 'Playlist' : host, url: entered);
  }
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

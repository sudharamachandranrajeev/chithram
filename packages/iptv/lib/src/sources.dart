import 'dart:async';
import 'dart:io';

import 'catalogue.dart';
import 'http.dart';
import 'm3u.dart';
import 'store.dart';
import 'xmltv.dart';
import 'xtream.dart';

enum SourceKind { m3uUrl, m3uFile, xtream, xmltvUrl, catalogue }

/// A user-added source. Passwords are never part of [toJson]; the app keeps
/// them in a [SecretStore] (flutter_secure_storage in the app).
class Source {
  Source({
    required this.id,
    required this.kind,
    required this.name,
    required this.location,
    this.username,
    this.enabled = true,
    this.deprecated = false,
    this.failures = 0,
    this.lastAttempt,
    this.lastSuccess,
    this.etag,
    this.lastModified,
    this.refreshInterval = const Duration(hours: 12),
    this.filterCountry,
    this.filterLanguage,
    this.filterCategory,
    this.lastError,
  });

  final String id;
  final SourceKind kind;
  final String name;

  /// URL, file path or Xtream base URL.
  final String location;
  final String? username;
  final bool enabled;

  /// Set after too many failed refreshes; the source is auto-disabled.
  final bool deprecated;
  final int failures;
  final DateTime? lastAttempt;
  final DateTime? lastSuccess;
  final String? etag;
  final String? lastModified;
  final Duration refreshInterval;
  final String? filterCountry;
  final String? filterLanguage;
  final String? filterCategory;
  final String? lastError;

  /// Opt-in iptv-org subscription, e.g. India + Malayalam.
  factory Source.iptvOrg({
    required String id,
    String? country,
    String? language,
    String? category,
  }) =>
      Source(
        id: id,
        kind: SourceKind.catalogue,
        name: 'iptv-org',
        location: CatalogueEndpoints.iptvOrgApi,
        filterCountry: country,
        filterLanguage: language,
        filterCategory: category,
      );

  /// Opt-in Free-TV/IPTV playlist.
  factory Source.freeTv(String id) => Source(
        id: id,
        kind: SourceKind.m3uUrl,
        name: 'Free-TV/IPTV',
        location: CatalogueEndpoints.freeTvPlaylist,
      );

  bool get active => enabled && !deprecated;

  Source copyWith({
    bool? enabled,
    bool? deprecated,
    int? failures,
    DateTime? lastAttempt,
    DateTime? lastSuccess,
    String? etag,
    String? lastModified,
    String? lastError,
    bool clearError = false,
  }) =>
      Source(
        id: id,
        kind: kind,
        name: name,
        location: location,
        username: username,
        enabled: enabled ?? this.enabled,
        deprecated: deprecated ?? this.deprecated,
        failures: failures ?? this.failures,
        lastAttempt: lastAttempt ?? this.lastAttempt,
        lastSuccess: lastSuccess ?? this.lastSuccess,
        etag: etag ?? this.etag,
        lastModified: lastModified ?? this.lastModified,
        refreshInterval: refreshInterval,
        filterCountry: filterCountry,
        filterLanguage: filterLanguage,
        filterCategory: filterCategory,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'location': location,
        'username': username,
        'enabled': enabled,
        'deprecated': deprecated,
        'failures': failures,
        'lastAttempt': lastAttempt?.millisecondsSinceEpoch,
        'lastSuccess': lastSuccess?.millisecondsSinceEpoch,
        'etag': etag,
        'lastModified': lastModified,
        'intervalMin': refreshInterval.inMinutes,
        'country': filterCountry,
        'language': filterLanguage,
        'category': filterCategory,
        'lastError': lastError,
      };

  factory Source.fromJson(Map<String, dynamic> j) {
    DateTime? d(Object? v) => v is int
        ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
        : null;
    return Source(
      id: j['id'] as String,
      kind: SourceKind.values.firstWhere((k) => k.name == j['kind']),
      name: j['name'] as String,
      location: j['location'] as String,
      username: j['username'] as String?,
      enabled: j['enabled'] != false,
      deprecated: j['deprecated'] == true,
      failures: (j['failures'] as int?) ?? 0,
      lastAttempt: d(j['lastAttempt']),
      lastSuccess: d(j['lastSuccess']),
      etag: j['etag'] as String?,
      lastModified: j['lastModified'] as String?,
      refreshInterval: Duration(minutes: (j['intervalMin'] as int?) ?? 720),
      filterCountry: j['country'] as String?,
      filterLanguage: j['language'] as String?,
      filterCategory: j['category'] as String?,
      lastError: j['lastError'] as String?,
    );
  }

  @override
  String toString() => 'Source($kind $name)'; // no location: may hold creds
}

/// Pluggable secret storage (Xtream passwords).
abstract class SecretStore {
  Future<String?> read(String sourceId);
  Future<void> write(String sourceId, String secret);
  Future<void> delete(String sourceId);
}

class InMemorySecretStore implements SecretStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String id) async => _m[id];
  @override
  Future<void> write(String id, String s) async => _m[id] = s;
  @override
  Future<void> delete(String id) async => _m.remove(id);
}

class StoredChannel {
  StoredChannel({
    required this.key,
    required this.sourceId,
    required this.name,
    this.url,
    this.ref,
    this.group,
    this.logo,
    this.tvgId,
    this.catchup,
    this.catchupDays,
    this.catchupSource,
    this.referrer,
    this.userAgent,
    this.categories = const [],
    this.dead = false,
    this.deadSince,
    this.ttfbMs,
    this.missing = false,
    this.firstSeen,
    this.lastSeen,
  });

  /// Stable identity across refreshes (survives URL changes when tvg-id or
  /// catalogue id exists).
  final String key;
  final String sourceId;
  final String name;

  /// Null for Xtream channels; see [ref] and [SourceRegistry.resolveUrl].
  final String? url;

  /// Xtream stream id.
  final String? ref;
  final String? group;
  final String? logo;
  final String? tvgId;
  final String? catchup;
  final int? catchupDays;
  final String? catchupSource;
  final String? referrer;
  final String? userAgent;
  final List<String> categories;

  /// Probe says unplayable. Kept in the list so the UI can hide/show it.
  final bool dead;
  final DateTime? deadSince;
  final int? ttfbMs;

  /// Gone from the latest source refresh. Kept, not deleted.
  final bool missing;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  Map<String, String> get headers => {
        'Referer': ?referrer,
        'User-Agent': ?userAgent,
      };

  bool get playable => !dead && !missing;

  StoredChannel copyWith({
    bool? dead,
    DateTime? deadSince,
    bool clearDeadSince = false,
    int? ttfbMs,
    bool? missing,
  }) =>
      StoredChannel(
        key: key,
        sourceId: sourceId,
        name: name,
        url: url,
        ref: ref,
        group: group,
        logo: logo,
        tvgId: tvgId,
        catchup: catchup,
        catchupDays: catchupDays,
        catchupSource: catchupSource,
        referrer: referrer,
        userAgent: userAgent,
        categories: categories,
        dead: dead ?? this.dead,
        deadSince: clearDeadSince ? null : (deadSince ?? this.deadSince),
        ttfbMs: ttfbMs ?? this.ttfbMs,
        missing: missing ?? this.missing,
        firstSeen: firstSeen,
        lastSeen: lastSeen,
      );

  /// Fresh data from a refresh merged over the old record (keeps health).
  StoredChannel mergedOver(StoredChannel? old, DateTime now) => StoredChannel(
        key: key,
        sourceId: sourceId,
        name: name,
        url: url,
        ref: ref,
        group: group,
        logo: logo,
        tvgId: tvgId,
        catchup: catchup,
        catchupDays: catchupDays,
        catchupSource: catchupSource,
        referrer: referrer,
        userAgent: userAgent,
        categories: categories,
        // A changed URL deserves a fresh probe, so health is reset then.
        dead: old != null && old.url == url ? old.dead : false,
        deadSince: old != null && old.url == url ? old.deadSince : null,
        ttfbMs: old?.ttfbMs,
        missing: false,
        firstSeen: old?.firstSeen ?? now,
        lastSeen: now,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'src': sourceId,
        'name': name,
        'url': url,
        'ref': ref,
        'group': group,
        'logo': logo,
        'tvgId': tvgId,
        'catchup': catchup,
        'catchupDays': catchupDays,
        'catchupSource': catchupSource,
        'referrer': referrer,
        'ua': userAgent,
        'cats': categories,
        'dead': dead,
        'deadSince': deadSince?.millisecondsSinceEpoch,
        'ttfb': ttfbMs,
        'missing': missing,
        'first': firstSeen?.millisecondsSinceEpoch,
        'last': lastSeen?.millisecondsSinceEpoch,
      };

  factory StoredChannel.fromJson(Map<String, dynamic> j) {
    DateTime? d(Object? v) => v is int
        ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
        : null;
    return StoredChannel(
      key: j['key'] as String,
      sourceId: j['src'] as String,
      name: j['name'] as String,
      url: j['url'] as String?,
      ref: j['ref'] as String?,
      group: j['group'] as String?,
      logo: j['logo'] as String?,
      tvgId: j['tvgId'] as String?,
      catchup: j['catchup'] as String?,
      catchupDays: j['catchupDays'] as int?,
      catchupSource: j['catchupSource'] as String?,
      referrer: j['referrer'] as String?,
      userAgent: j['ua'] as String?,
      categories: [for (final c in (j['cats'] as List? ?? const [])) '$c'],
      dead: j['dead'] == true,
      deadSince: d(j['deadSince']),
      ttfbMs: j['ttfb'] as int?,
      missing: j['missing'] == true,
      firstSeen: d(j['first']),
      lastSeen: d(j['last']),
    );
  }

  @override
  String toString() => 'StoredChannel($name)';
}

class RefreshResult {
  RefreshResult(this.sourceId, this.status,
      {this.added = 0, this.removed = 0, this.total = 0, this.error});
  final String sourceId;
  final RefreshStatus status;
  final int added;
  final int removed;
  final int total;
  final String? error;
}

enum RefreshStatus { updated, notModified, failed, skipped, deprecated }

/// Receives parsed XMLTV batches for an `xmltvUrl` source (app writes SQLite).
typedef EpgIngest = Future<void> Function(Source source, Stream<EpgBatch> batches);

class SourceRegistry {
  SourceRegistry(
    this._store,
    this._http, {
    SecretStore? secrets,
    this.maxFailures = 5,
    this.onEpg,
    DateTime Function()? clock,
  })  : secrets = secrets ?? InMemorySecretStore(),
        _clock = clock ?? DateTime.now;

  final IptvStore _store;
  final IptvHttp _http;
  final SecretStore secrets;

  /// Consecutive failed refreshes before a source is flagged deprecated and
  /// auto-disabled.
  final int maxFailures;
  final EpgIngest? onEpg;
  final DateTime Function() _clock;

  Future<void> add(Source s, {String? password}) async {
    if (password != null) await secrets.write(s.id, password);
    await _store.saveSource(s);
  }

  Future<void> remove(String id) async {
    await secrets.delete(id);
    await _store.deleteSource(id);
  }

  /// Re-enabling clears the deprecated flag and failure count.
  Future<void> enable(String id) async {
    for (final s in await _store.sources()) {
      if (s.id == id) {
        await _store.saveSource(Source(
          id: s.id, kind: s.kind, name: s.name, location: s.location,
          username: s.username, refreshInterval: s.refreshInterval,
          filterCountry: s.filterCountry, filterLanguage: s.filterLanguage,
          filterCategory: s.filterCategory, etag: s.etag,
          lastModified: s.lastModified, lastSuccess: s.lastSuccess,
        ));
      }
    }
  }

  Future<List<Source>> sources() => _store.sources();

  /// Sources whose interval elapsed.
  Future<List<Source>> due() async {
    final now = _clock().toUtc();
    return [
      for (final s in await _store.sources())
        if (s.active &&
            (s.lastAttempt == null ||
                now.difference(s.lastAttempt!) >= s.refreshInterval))
          s,
    ];
  }

  Future<List<RefreshResult>> refreshDue() async {
    final out = <RefreshResult>[];
    for (final s in await due()) {
      out.add(await refresh(s.id));
    }
    return out;
  }

  /// Streaming URL for a channel (Xtream URLs are built on demand so the
  /// password never sits in the channel table).
  Future<Uri?> resolveUrl(StoredChannel c, {String ext = 'm3u8'}) async {
    if (c.url != null) return Uri.tryParse(c.url!);
    final src = (await _store.sources()).where((s) => s.id == c.sourceId);
    if (src.isEmpty || c.ref == null) return null;
    final x = await _xtream(src.first);
    return x?.liveUrl(int.parse(c.ref!), ext: ext);
  }

  Future<XtreamClient?> _xtream(Source s) async {
    final pw = await secrets.read(s.id);
    if (pw == null || s.username == null) return null;
    return XtreamClient(
        XtreamAccount(baseUrl: s.location, username: s.username!, password: pw),
        _http);
  }

  Future<RefreshResult> refresh(String id) async {
    final all = await _store.sources();
    final s = all.where((x) => x.id == id).firstOrNull;
    if (s == null) return RefreshResult(id, RefreshStatus.skipped);
    if (!s.active) return RefreshResult(id, RefreshStatus.skipped);
    final now = _clock().toUtc();
    try {
      final r = await _fetch(s, now);
      return r;
    } catch (e) {
      final failures = s.failures + 1;
      final dep = failures >= maxFailures;
      await _store.saveSource(s.copyWith(
        failures: failures,
        lastAttempt: now,
        lastError: e.runtimeType.toString(),
        deprecated: dep,
        enabled: dep ? false : null,
      ));
      return RefreshResult(id, dep ? RefreshStatus.deprecated : RefreshStatus.failed,
          error: e.runtimeType.toString());
    }
  }

  Future<RefreshResult> _fetch(Source s, DateTime now) async {
    switch (s.kind) {
      case SourceKind.m3uUrl:
      case SourceKind.m3uFile:
      case SourceKind.xmltvUrl:
        return _fetchStream(s, now);
      case SourceKind.xtream:
        final x = await _xtream(s);
        if (x == null) throw StateError('missing credentials');
        final auth = await x.authenticate();
        if (!auth.authenticated) throw StateError('xtream auth failed');
        final cats = {
          for (final c in await x.liveCategories()) c.id: c.name,
        };
        final streams = await x.liveStreams();
        final items = [
          for (final st in streams)
            StoredChannel(
              key: '${s.id}:x${st.id}',
              sourceId: s.id,
              name: st.name,
              ref: '${st.id}',
              group: cats[st.categoryId],
              logo: st.icon,
              tvgId: st.epgChannelId,
              catchup: st.tvArchive ? 'xtream' : null,
              catchupDays: st.tvArchive ? st.tvArchiveDuration : null,
            ),
        ];
        return _commit(s, items, now);
      case SourceKind.catalogue:
        final cat = await IptvOrgClient(_http, baseUrl: s.location).load();
        final sel = cat.select(
          country: s.filterCountry,
          language: s.filterLanguage,
          category: s.filterCategory,
        );
        final items = <StoredChannel>[];
        for (final it in sel) {
          for (var i = 0; i < it.streams.length; i++) {
            final st = it.streams[i];
            items.add(StoredChannel(
              key: '${s.id}:${it.channel.id}${i == 0 ? '' : '#$i'}',
              sourceId: s.id,
              name: it.channel.name,
              url: st.url,
              group: it.channel.categories.isEmpty
                  ? null
                  : it.channel.categories.first,
              logo: it.channel.logo,
              tvgId: it.channel.id,
              referrer: st.referrer,
              userAgent: st.userAgent,
              categories: it.channel.categories,
            ));
          }
        }
        return _commit(s, items, now);
    }
  }

  Future<RefreshResult> _fetchStream(Source s, DateTime now) async {
    Stream<List<int>> bytes;
    String? etag, lastMod;
    IptvResponse? resp;
    if (s.kind == SourceKind.m3uFile) {
      bytes = File(s.location).openRead();
    } else {
      resp = await _http.open(Uri.parse(s.location), headers: {
        if (s.etag != null) 'If-None-Match': s.etag!,
        if (s.lastModified != null) 'If-Modified-Since': s.lastModified!,
      }, timeout: const Duration(seconds: 30));
      if (resp.status == 304) {
        resp.close();
        await _store.saveSource(s.copyWith(
            failures: 0, lastAttempt: now, lastSuccess: now, clearError: true));
        return RefreshResult(s.id, RefreshStatus.notModified);
      }
      if (!resp.ok) {
        resp.close();
        throw HttpStatusException(resp.status, 'source ${s.name}');
      }
      etag = resp.headers['etag'];
      lastMod = resp.headers['last-modified'];
      bytes = resp.body;
    }

    if (s.kind == SourceKind.xmltvUrl) {
      var n = 0;
      final catchup = <String, int>{};
      for (final other in await _store.sources()) {
        for (final c in await _store.channels(other.id)) {
          if (c.tvgId != null && c.catchupDays != null) {
            catchup[c.tvgId!] = c.catchupDays!;
          }
        }
      }
      final batches = parseXmltv(bytes, window: EpgWindow(now: now, catchupDays: catchup));
      if (onEpg != null) {
        await onEpg!(s, batches);
      } else {
        await for (final b in batches) {
          n += b.programmes.length;
        }
      }
      await _store.saveSource(s.copyWith(
          failures: 0, lastAttempt: now, lastSuccess: now, etag: etag,
          lastModified: lastMod, clearError: true));
      return RefreshResult(s.id, RefreshStatus.updated, total: n);
    }

    final items = <StoredChannel>[];
    final seen = <String, int>{};
    await for (final e in parseM3uStream(bytes)) {
      final base = e.tvgId != null && e.tvgId!.isNotEmpty
          ? '${s.id}:${e.tvgId}'
          : '${s.id}:${e.name.toLowerCase()}';
      // Several streams for one tvg-id get an index suffix, in file order.
      final n = seen[base] = (seen[base] ?? -1) + 1;
      items.add(StoredChannel(
        key: n == 0 ? base : '$base#$n',
        sourceId: s.id,
        name: e.name,
        url: e.url,
        group: e.group,
        logo: e.logo,
        tvgId: e.tvgId,
        catchup: e.catchup,
        catchupDays: e.catchupDays,
        catchupSource: e.catchupSource,
        referrer: e.referrer,
        userAgent: e.userAgent,
      ));
    }
    return _commit(s, items, now, etag: etag, lastModified: lastMod);
  }

  Future<RefreshResult> _commit(Source s, List<StoredChannel> fresh, DateTime now,
      {String? etag, String? lastModified}) async {
    if (fresh.isEmpty) throw StateError('source returned no channels');
    final old = {for (final c in await _store.channels(s.id)) c.key: c};
    final merged = <StoredChannel>[];
    var added = 0;
    for (final c in fresh) {
      final o = old.remove(c.key);
      if (o == null) added++;
      merged.add(c.mergedOver(o, now));
    }
    // Channels that vanished are flagged, not deleted.
    for (final gone in old.values) {
      merged.add(gone.copyWith(missing: true));
    }
    await _store.replaceChannels(s.id, merged);
    await _store.saveSource(s.copyWith(
      failures: 0,
      lastAttempt: now,
      lastSuccess: now,
      etag: etag,
      lastModified: lastModified,
      clearError: true,
    ));
    return RefreshResult(s.id, RefreshStatus.updated,
        added: added, removed: old.length, total: fresh.length);
  }
}

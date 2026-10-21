import 'dart:convert';

import 'http.dart';

/// The only built-in catalogue endpoints. Both are opt-in: nothing is fetched
/// until the user subscribes.
class CatalogueEndpoints {
  static const iptvOrgApi = 'https://iptv-org.github.io/api';
  static const freeTvPlaylist =
      'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8';
}

class CatChannel {
  CatChannel({
    required this.id,
    required this.name,
    this.country,
    this.categories = const [],
    this.logo,
    this.isNsfw = false,
    this.closed,
    this.network,
    this.website,
  });
  final String id;
  final String name;
  final String? country;
  final List<String> categories;
  final String? logo;
  final bool isNsfw;
  final String? closed;
  final String? network;
  final String? website;

  factory CatChannel.fromJson(Map j) => CatChannel(
        id: '${j['id']}',
        name: '${j['name']}',
        country: j['country'] as String?,
        categories: [for (final c in (j['categories'] as List? ?? const [])) '$c'],
        logo: j['logo'] as String?,
        isNsfw: j['is_nsfw'] == true,
        closed: j['closed'] as String?,
        network: j['network'] as String?,
        website: j['website'] as String?,
      );
}

class CatStream {
  CatStream({
    required this.channel,
    required this.url,
    this.feed,
    this.title,
    this.quality,
    this.userAgent,
    this.referrer,
  });
  final String? channel;
  final String? feed;
  final String url;
  final String? title;
  final String? quality;
  final String? userAgent;
  final String? referrer;

  Map<String, String> get headers => {
        'Referer': ?referrer,
        'User-Agent': ?userAgent,
      };

  factory CatStream.fromJson(Map j) => CatStream(
        channel: j['channel'] as String?,
        feed: j['feed'] as String?,
        url: '${j['url']}',
        title: j['title'] as String?,
        quality: j['quality'] as String?,
        userAgent: j['user_agent'] as String?,
        referrer: j['referrer'] as String?,
      );
}

class CatGuide {
  CatGuide(this.channel, this.site, this.siteId, this.lang);
  final String? channel;
  final String? site;
  final String? siteId;
  final String? lang;
}

class CatFeed {
  CatFeed(this.channel, this.id, this.languages);
  final String channel;
  final String id;
  final List<String> languages; // ISO 639-3
}

class CatNamed {
  CatNamed(this.code, this.name);
  final String code;
  final String name;
}

/// A playable catalogue item: channel metadata joined with its streams.
class CatItem {
  CatItem(this.channel, this.streams, this.languages);
  final CatChannel channel;
  final List<CatStream> streams;
  final List<String> languages;
}

class Catalogue {
  Catalogue({
    required this.channels,
    required this.streams,
    this.feeds = const [],
    this.guides = const [],
    this.categories = const [],
    this.countries = const [],
    this.languages = const [],
    this.blocked = const {},
  });
  final List<CatChannel> channels;
  final List<CatStream> streams;
  final List<CatFeed> feeds;
  final List<CatGuide> guides;
  final List<CatNamed> categories;
  final List<CatNamed> countries;
  final List<CatNamed> languages;

  /// Channel ids on blocklist.json. Always excluded from [select].
  final Set<String> blocked;

  /// Joins channels with streams, dropping blocklisted, closed, NSFW (unless
  /// [allowNsfw]) and non-http(s) entries. Filters are ANDed; each is
  /// case-insensitive. [country] is ISO 3166 alpha-2 ("IN"), [language] is ISO
  /// 639-3 ("mal", "tam"), [category] is the iptv-org category id ("sports").
  List<CatItem> select({
    String? country,
    String? language,
    String? category,
    bool allowNsfw = false,
    bool includeClosed = false,
  }) {
    final cc = country?.toLowerCase();
    final lang = language?.toLowerCase();
    final cat = category?.toLowerCase();
    final langsByChannel = <String, Set<String>>{};
    for (final f in feeds) {
      langsByChannel
          .putIfAbsent(f.channel, () => {})
          .addAll(f.languages.map((l) => l.toLowerCase()));
    }
    final streamsByChannel = <String, List<CatStream>>{};
    for (final s in streams) {
      final c = s.channel;
      if (c == null) continue;
      final u = Uri.tryParse(s.url);
      if (u == null || (u.scheme != 'http' && u.scheme != 'https')) continue;
      streamsByChannel.putIfAbsent(c, () => []).add(s);
    }
    final out = <CatItem>[];
    for (final ch in channels) {
      if (blocked.contains(ch.id)) continue;
      if (!allowNsfw && ch.isNsfw) continue;
      if (!includeClosed && ch.closed != null) continue;
      if (cc != null && ch.country?.toLowerCase() != cc) continue;
      if (cat != null && !ch.categories.any((c) => c.toLowerCase() == cat)) {
        continue;
      }
      final langs = langsByChannel[ch.id] ?? const <String>{};
      if (lang != null && !langs.contains(lang)) continue;
      final ss = streamsByChannel[ch.id];
      if (ss == null || ss.isEmpty) continue;
      out.add(CatItem(ch, ss, langs.toList()));
    }
    return out;
  }
}

/// Fetches the iptv-org API. [baseUrl] is overridable for tests.
class IptvOrgClient {
  IptvOrgClient(this._http, {this.baseUrl = CatalogueEndpoints.iptvOrgApi});
  final IptvHttp _http;
  final String baseUrl;

  Future<List> _list(String name) async {
    final r = await _http.open(Uri.parse('$baseUrl/$name.json'),
        timeout: const Duration(seconds: 30));
    if (!r.ok) {
      r.close();
      throw HttpStatusException(r.status, name);
    }
    final j = jsonDecode(await readText(r, maxBytes: 64 * 1024 * 1024));
    return j is List ? j : const [];
  }

  /// Blocklist is mandatory: failing to fetch it fails the whole load.
  Future<Catalogue> load({bool withGuides = false}) async {
    final blocklist = await _list('blocklist');
    final channels = await _list('channels');
    final streams = await _list('streams');
    final feeds = await _list('feeds');
    final categories = await _list('categories');
    final countries = await _list('countries');
    final languages = await _list('languages');
    final guides = withGuides ? await _list('guides') : const [];
    return Catalogue(
      channels: [for (final c in channels) if (c is Map) CatChannel.fromJson(c)],
      streams: [for (final s in streams) if (s is Map) CatStream.fromJson(s)],
      feeds: [
        for (final f in feeds)
          if (f is Map)
            CatFeed('${f['channel']}', '${f['id']}',
                [for (final l in (f['languages'] as List? ?? const [])) '$l']),
      ],
      guides: [
        for (final g in guides)
          if (g is Map)
            CatGuide(g['channel'] as String?, g['site'] as String?,
                g['site_id'] as String?, g['lang'] as String?),
      ],
      categories: _named(categories, 'id'),
      countries: _named(countries, 'code'),
      languages: _named(languages, 'code'),
      blocked: {
        for (final b in blocklist)
          if (b is Map && b['channel'] != null) '${b['channel']}',
      },
    );
  }

  static List<CatNamed> _named(List l, String key) =>
      [for (final e in l) if (e is Map) CatNamed('${e[key]}', '${e['name']}')];
}

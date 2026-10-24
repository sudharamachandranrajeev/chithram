import 'dart:convert';

import 'package:http/http.dart' as http;

import 'clients.dart';
import 'errors.dart';
import 'models.dart';
import 'net.dart';
import 'player_parser.dart';
import 'seek_data.dart';
import 'util.dart';

final _searchApi = Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false');
final _browseApi = Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false');
final _nextApi = Uri.parse('https://www.youtube.com/youtubei/v1/next?prettyPrint=false');
final _suggestApi = Uri.parse('https://suggestqueries-clients6.youtube.com/complete/search');
final _channelIdRe = RegExp(r'^UC[A-Za-z0-9_-]{22}$');

/// The suggestion strings from a suggest answer: JSONP
/// `window.google.ac.h(["q",[["text",0,[..]],...],{..}])` or plain JSON
/// `["q",["text",...]]`. Anything else gives an empty list.
List<String> parseSuggestions(String body) {
  final open = body.indexOf('[');
  final close = body.lastIndexOf(']');
  if (open < 0 || close <= open) return const [];
  try {
    final j = jsonDecode(body.substring(open, close + 1));
    if (j is! List || j.length < 2 || j[1] is! List) return const [];
    return [
      for (final e in j[1] as List)
        if (e is String)
          e
        else if (e is List && e.isNotEmpty && e.first is String)
          e.first as String,
    ].take(10).toList();
  } on FormatException {
    return const [];
  }
}

/// Search's "Videos" filter.
const _videosOnly = 'EgIQAQ==';

/// Search filter params for [InnertubeBrowse.search].
abstract final class SearchFilter {
  /// Videos only (the default).
  static const videos = _videosOnly;

  /// Currently live streams.
  static const live = 'EgJAAQ==';

  /// Videos under 4 minutes: what Shorts (<= 60 s) are served as in search.
  static const underFourMinutes = 'EgQQARgB';
}

/// Search, channel uploads, related videos and video details, with
/// continuation paging. Keep calling [Page.continuation] back into the same
/// method until it is null.
class InnertubeBrowse {
  InnertubeBrowse({http.Client? client, this.webVersion = '2.20250101.00.00', this.region = 'US'})
      : net = Net(client) {
    visitor = VisitorData(net);
  }

  final Net net;
  final String webVersion;

  /// Two-letter country code: what is popular and what is available differ.
  final String region;
  late final VisitorData visitor;

  Map<String, Object?> get _context => {
        'client': {'clientName': 'WEB', 'clientVersion': webVersion, 'hl': 'en', 'gl': region},
      };

  static const _cookies = {'Cookie': 'CONSENT=YES+cb; SOCS=CAI'};

  /// Videos matching [query]; pass the previous page's `continuation`.
  /// [params] is a [SearchFilter] value.
  Future<Page<VideoItem>> search(String query, {String? continuation, String params = _videosOnly}) async {
    final body = <String, Object?>{'context': _context};
    if (continuation != null) {
      body['continuation'] = continuation;
    } else {
      body['query'] = query;
      body['params'] = params;
    }
    return parseVideoPage(await net.postJson(_searchApi, body, headers: _cookies));
  }

  /// What YouTube's search box suggests for [prefix] (at most 10, best first).
  /// An empty prefix suggests nothing.
  Future<List<String>> suggest(String prefix) async {
    final q = prefix.trim();
    if (q.isEmpty) return const [];
    final uri = _suggestApi.replace(queryParameters: {
      'client': 'youtube',
      'ds': 'yt',
      'hl': 'en',
      'gl': region,
      'q': q,
    });
    return parseSuggestions(await net.getText(uri, timeout: const Duration(seconds: 5)));
  }

  /// A channel's uploads (newest first). [channelId] is `UC...`.
  Future<Page<VideoItem>> channelUploads(String channelId, {String? continuation}) async {
    final body = <String, Object?>{'context': _context};
    if (continuation != null) {
      body['continuation'] = continuation;
    } else {
      if (!_channelIdRe.hasMatch(channelId)) throw InnertubeException('not a channel id: $channelId');
      body['browseId'] = 'VLUU${channelId.substring(2)}';
    }
    return parseVideoPage(await net.postJson(_browseApi, body, headers: _cookies));
  }

  /// What YouTube suggests watching after [videoId] (its "up next" list),
  /// without [videoId] itself.
  Future<List<VideoItem>> related(String videoId) async => (await watchInfo(videoId)).related;

  /// One `/next` call: the related list, the chapters and the "most
  /// replayed" graph of [videoId]. [duration] trims chapters past the end.
  Future<WatchInfo> watchInfo(String videoId, {Duration? duration}) async {
    final response = await net.postJson(_nextApi, {'context': _context, 'videoId': videoId}, headers: _cookies);
    return parseWatchInfo(response, videoId, duration: duration);
  }

  /// The videos on a channel's home tab, shelf by shelf. On YouTube's own
  /// topic channels (Music, Sports, News, Gaming) that is what is popular in
  /// [region] now.
  Future<List<VideoItem>> channelHome(String channelId) async {
    if (!_channelIdRe.hasMatch(channelId)) throw InnertubeException('not a channel id: $channelId');
    final body = {'context': _context, 'browseId': channelId};
    return parseVideoPage(await net.postJson(_browseApi, body, headers: _cookies)).items;
  }

  /// Title, channel, description and counters (from the VISIONOS player
  /// response's videoDetails).
  Future<VideoDetails> videoDetails(String videoId) async {
    var id = await visitor.get();
    try {
      return parseVideoDetails(await fetchPlayer(net, visionosClient, videoId, id));
    } on PlayabilityException catch (error) {
      if (!error.loginRequired) rethrow;
      id = await visitor.get(fresh: true);
      return parseVideoDetails(await fetchPlayer(net, visionosClient, videoId, id));
    }
  }
}

/// Related videos, chapters and heatmap in a `/next` response.
WatchInfo parseWatchInfo(Object? response, String videoId, {Duration? duration}) {
  final page = parseVideoPage(response);
  return WatchInfo(
    related: [for (final v in page.items) if (v.videoId != videoId) v],
    chapters: parseChapters(response, description: descriptionOf(response), duration: duration),
    heatmap: parseHeatmap(response),
  );
}

/// Seconds from "1:02:03" / "3:45".
Duration? parseClock(String text) {
  final t = text.trim();
  if (!RegExp(r'^\d{1,3}(?::\d\d){1,2}$').hasMatch(t)) return null;
  final seconds = t.split(':').fold<int>(0, (total, part) => total * 60 + int.parse(part));
  return Duration(seconds: seconds);
}

const _videoKeys = ['videoRenderer', 'playlistVideoRenderer', 'gridVideoRenderer', 'compactVideoRenderer'];

/// Videos and the next-page token in a search / browse / continuation response.
Page<VideoItem> parseVideoPage(Object? response) {
  final items = <VideoItem>[];
  final seen = <String>{};
  _walk(response, (key, node) {
    final item = key == 'lockupViewModel' ? _lockupItem(node) : _videoItem(node);
    if (item != null && seen.add(item.videoId)) items.add(item);
  });
  String? next;
  for (final c in findAll(response, 'continuationItemRenderer')) {
    final token = asString(asJson(asJson(c['continuationEndpoint'])['continuationCommand'])['token']);
    if (token.isNotEmpty) next = token;
  }
  return Page(items, next);
}

void _walk(Object? node, void Function(String key, Json node) onVideo) {
  if (node is Map) {
    node.forEach((k, v) {
      if ((_videoKeys.contains(k) || k == 'lockupViewModel') && v is Map) {
        onVideo(k as String, asJson(v));
      } else {
        _walk(v, onVideo);
      }
    });
  } else if (node is List) {
    for (final v in node) {
      _walk(v, onVideo);
    }
  }
}

VideoItem? _videoItem(Json r) {
  final id = asString(r['videoId']);
  if (id.length != 11) return null;
  final title = textOf(r['title']);
  if (title.isEmpty) return null;
  final byline = asJson(r['ownerText'] ?? r['longBylineText'] ?? r['shortBylineText']);
  final firstRun = asList(byline['runs']).isEmpty ? <String, dynamic>{} : asJson(asList(byline['runs']).first);
  final channelId = asString(asJson(asJson(firstRun['navigationEndpoint'])['browseEndpoint'])['browseId']);
  var duration = parseClock(textOf(r['lengthText']));
  final lengthSeconds = toInt(r['lengthSeconds']);
  if (duration == null && lengthSeconds != null && lengthSeconds > 0) duration = Duration(seconds: lengthSeconds);
  final live = asList(r['badges']).any((b) => asString(asJson(asJson(b)['metadataBadgeRenderer'])['style']).contains('LIVE')) ||
      asList(r['thumbnailOverlays']).any(
          (o) => asString(asJson(asJson(o)['thumbnailOverlayTimeStatusRenderer'])['style']) == 'LIVE');
  return VideoItem(
    videoId: id,
    title: title,
    author: asString(firstRun['text']),
    channelId: channelId,
    duration: duration,
    viewsText: textOf(r['viewCountText']),
    isLive: live,
    thumbnails: parseThumbnails(r['thumbnail']),
  );
}

/// The newer layout (related videos, topic channels): a `lockupViewModel`.
/// Playlists and mixes use it too; only videos are kept.
VideoItem? _lockupItem(Json l) {
  if (asString(l['contentType']) != 'LOCKUP_CONTENT_TYPE_VIDEO') return null;
  final id = asString(l['contentId']);
  if (id.length != 11) return null;
  final meta = asJson(asJson(l['metadata'])['lockupMetadataViewModel']);
  final title = asString(asJson(meta['title'])['content']);
  if (title.isEmpty) return null;
  // Row 1: the channel. Row 2: views (or "watching") and age.
  final rows = [
    for (final r in asList(asJson(asJson(meta['metadata'])['contentMetadataViewModel'])['metadataRows']))
      [for (final p in asList(asJson(r)['metadataParts'])) asJson(p)],
  ];
  final author = rows.isEmpty || rows.first.isEmpty ? '' : asString(asJson(rows.first.first['text'])['content']);
  var views = '';
  for (final p in rows.skip(1).expand((r) => r)) {
    final text = asString(asJson(p['text'])['content']);
    final label = asString(p['accessibilityLabel']);
    if (label.contains('watching')) {
      views = text.contains('watching') ? text : '$text watching';
    } else if (label.contains('view')) {
      views = text.contains('view') ? text : '$text views';
    }
  }
  final channelId = findAll(meta, 'browseEndpoint')
      .map((e) => asString(e['browseId']))
      .firstWhere(_channelIdRe.hasMatch, orElse: () => '');
  final image = asJson(asJson(l['contentImage'])['thumbnailViewModel']);
  final badges = findAll(image, 'thumbnailBadgeViewModel');
  Duration? duration;
  for (final b in badges) {
    duration ??= parseClock(asString(b['text']));
  }
  return VideoItem(
    videoId: id,
    title: title,
    author: author,
    channelId: channelId,
    duration: duration,
    viewsText: views,
    isLive: badges.any((b) => asString(b['badgeStyle']).contains('LIVE') || asString(b['text']) == 'LIVE'),
    thumbnails: parseThumbnails({'thumbnails': asJson(image['image'])['sources']}),
  );
}

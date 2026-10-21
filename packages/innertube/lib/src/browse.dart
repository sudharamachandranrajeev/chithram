import 'package:http/http.dart' as http;

import 'clients.dart';
import 'errors.dart';
import 'models.dart';
import 'net.dart';
import 'player_parser.dart';
import 'util.dart';

final _searchApi = Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false');
final _browseApi = Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false');
final _channelIdRe = RegExp(r'^UC[A-Za-z0-9_-]{22}$');

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

/// Search, channel uploads and video details, with continuation paging.
/// Keep calling [Page.continuation] back into the same method until it is
/// null.
class InnertubeBrowse {
  InnertubeBrowse({http.Client? client, this.webVersion = '2.20250101.00.00'}) : net = Net(client) {
    visitor = VisitorData(net);
  }

  final Net net;
  final String webVersion;
  late final VisitorData visitor;

  Map<String, Object?> get _context => {
        'client': {'clientName': 'WEB', 'clientVersion': webVersion, 'hl': 'en', 'gl': 'US'},
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
    final item = _videoItem(node);
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
      if (_videoKeys.contains(k) && v is Map) {
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

import 'package:innertube/innertube.dart';

import '../../core/item_id.dart';
import '../../player/play_request.dart';

// innertube's `Page` clashes with Flutter's: import it with a prefix or `hide`
// in files that also import material.

/// YouTube search and stream resolution. Stub: search works; mapping a
/// resolved video to a `MediaSpec` comes with the YouTube work package.
class YouTubeService {
  YouTubeService({InnertubeBrowse? browse, YouTubeResolver? resolver}) {
    _browse = browse;
    _resolver = resolver;
  }

  InnertubeBrowse? _browse;
  YouTubeResolver? _resolver;

  InnertubeBrowse get browse => _browse ??= InnertubeBrowse();
  YouTubeResolver get resolver => _resolver ??= YouTubeResolver();

  Future<Page<VideoItem>> search(String q, {String? continuation}) =>
      browse.search(q, continuation: continuation);

  Future<PlayRequest> playRequest(VideoItem v) async => PlayRequest(
        itemId: ItemId.youtube(v.videoId),
        title: v.title,
        subtitle: v.author.isEmpty ? null : v.author,
        isLive: v.isLive,
        resolve: () => throw UnimplementedError('YouTube stream mapping'),
      );

  Future<PlayRequest> playRequestForId(String videoId) async => PlayRequest(
        itemId: ItemId.youtube(videoId),
        title: videoId,
        resolve: () => throw UnimplementedError('YouTube stream mapping'),
      );

  static final _idRe = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// The video id in a YouTube link (watch, youtu.be, shorts, live), or null.
  static String? videoIdFromUrl(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return null;
    final host = u.host.toLowerCase();
    String? id;
    if (host == 'youtu.be') {
      id = u.pathSegments.firstOrNull;
    } else if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      final seg = u.pathSegments;
      if (u.path == '/watch') {
        id = u.queryParameters['v'];
      } else if (seg.length >= 2 && (seg[0] == 'shorts' || seg[0] == 'live')) {
        id = seg[1];
      }
    }
    return id != null && _idRe.hasMatch(id) ? id : null;
  }
}

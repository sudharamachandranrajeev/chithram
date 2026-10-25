import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'scan.dart';

/// A fetched page: where it ended up after redirects, its content type and,
/// for text, its body.
class FetchedPage {
  const FetchedPage({required this.url, required this.contentType, this.body = ''});

  final Uri url;
  final String contentType;
  final String body;
}

typedef PageFetch = Future<FetchedPage?> Function(Uri url, {Map<String, String> headers});

/// Finds the playable media on a page: the page itself, then the frames it
/// embeds (players usually live in one), up to [maxDepth] frames deep and
/// [maxFrames] in all. Frames on this device's own network are skipped
/// unless the page itself is there.
class WebMediaResolver {
  WebMediaResolver({PageFetch? fetch, this.maxDepth = 2, this.maxFrames = 8}) : _fetch = fetch ?? fetchPage;

  final PageFetch _fetch;
  final int maxDepth;
  final int maxFrames;

  /// Null when [page] cannot be fetched.
  Future<PageScan?> scan(Uri page) async {
    final top = await _fetch(page, headers: const {'User-Agent': browserUserAgent});
    if (top == null) return null;
    final direct = _asMedia(top, page);
    if (direct != null) return PageScan(page: top.url, media: [direct]);
    final first = scanPage(top.body, top.url);
    final media = <MediaCandidate>{...first.media};
    final local = isLocalHost(top.url.host);
    final seen = <Uri>{top.url};
    var queue = [for (final f in first.frames) (f, top.url)];
    var fetched = 0;
    for (var depth = 1; depth <= maxDepth && queue.isNotEmpty; depth++) {
      final next = <(Uri, Uri)>[];
      for (final (frame, parent) in queue) {
        if (fetched >= maxFrames) break;
        if (!seen.add(frame) || (!local && isLocalHost(frame.host))) continue;
        fetched++;
        final got = await _fetch(frame, headers: {'User-Agent': browserUserAgent, 'Referer': parent.toString()});
        if (got == null) continue;
        final m = _asMedia(got, parent);
        if (m != null) {
          media.add(m);
          continue;
        }
        final inner = scanPage(got.body, got.url);
        media.addAll(inner.media);
        next.addAll([for (final f in inner.frames) (f, got.url)]);
      }
      queue = next;
    }
    return PageScan(
      page: first.page,
      title: first.title,
      media: rankMedia(media),
      frames: first.frames,
      links: first.links,
    );
  }

  static MediaCandidate? _asMedia(FetchedPage p, Uri referer) {
    final kind = mediaKindOf(p.url, type: p.contentType);
    if (kind == null || p.contentType.contains('html')) return null;
    return MediaCandidate(url: p.url, kind: kind, referer: referer);
  }
}

/// True for loopback, private, link-local and `.local` hosts.
bool isLocalHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.localhost')) return true;
  final ip = InternetAddress.tryParse(h.replaceAll(RegExp(r'^\[|\]$'), ''));
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal) return true;
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return b[0] == 10 || b[0] == 0 || (b[0] == 172 && b[1] >= 16 && b[1] < 32) || (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] < 128);
  }
  return (b[0] & 0xfe) == 0xfc;
}

/// Fetches [url] as a browser would. Text up to 3 MB is read; for media
/// (video, playlists) only the content type is kept. Null on failure.
Future<FetchedPage?> fetchPage(Uri url, {Map<String, String> headers = const {}}) async {
  if (url.scheme != 'http' && url.scheme != 'https') return null;
  const timeout = Duration(seconds: 15);
  const maxBytes = 3 * 1024 * 1024;
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await () async {
      final req = await client.getUrl(url);
      req.maxRedirects = 5;
      req.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml,*/*;q=0.8');
      headers.forEach(req.headers.set);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final finalUrl = res.redirects.isEmpty ? url : url.resolveUri(res.redirects.last.location);
      final type = res.headers.contentType?.mimeType ?? '';
      if (type.startsWith('video/') || (!type.contains('html') && mediaKindOf(finalUrl, type: type) != null)) {
        return FetchedPage(url: finalUrl, contentType: type);
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in res) {
        out.add(chunk);
        if (out.length > maxBytes) break;
      }
      return FetchedPage(url: finalUrl, contentType: type, body: utf8.decode(out.takeBytes(), allowMalformed: true));
    }()
        .timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

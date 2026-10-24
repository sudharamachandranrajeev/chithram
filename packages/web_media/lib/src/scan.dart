import 'ads.dart';
import 'unpack.dart';

enum MediaKind { hls, dash, file }

/// A stream or file found on a page.
class MediaCandidate {
  const MediaCandidate({required this.url, required this.kind, required this.referer, this.label, this.height});

  final Uri url;
  final MediaKind kind;

  /// The page (or frame) it was found on; many hosts refuse the stream without it.
  final Uri referer;

  /// What the page calls it ("720p", "Server 2"), when it says.
  final String? label;

  /// Picture height in lines, when the page says.
  final int? height;

  /// What the player sends with every request.
  Map<String, String> get headers => {
        'Referer': referer.toString(),
        'Origin': '${referer.scheme}://${referer.authority}',
        'User-Agent': browserUserAgent,
      };

  @override
  bool operator ==(Object other) => other is MediaCandidate && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'MediaCandidate($kind $url${height == null ? '' : ' ${height}p'})';
}

/// A link on a page to another page, for browsing.
class PageLink {
  const PageLink({required this.url, required this.text, this.image});

  final Uri url;
  final String text;
  final Uri? image;

  @override
  String toString() => 'PageLink($text -> $url)';
}

/// What a page holds, read from its HTML without running it.
class PageScan {
  const PageScan({required this.page, this.title, this.media = const [], this.frames = const [], this.links = const []});

  final Uri page;
  final String? title;

  /// Best first.
  final List<MediaCandidate> media;

  /// Embedded frames (`<iframe>`) that may hold the player.
  final List<Uri> frames;

  /// Links to other pages, in page order, ads left out.
  final List<PageLink> links;
}

/// Sent as the User-Agent: many sites refuse anything else.
const browserUserAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';

const _maxLinks = 400;

final _title = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false);
final _ogTitle = RegExp(
    r'''<meta[^>]+property\s*=\s*["']og:title["'][^>]*content\s*=\s*["']([^"']*)["']''',
    caseSensitive: false);
final _tag = RegExp(r'<(video|source|iframe|embed)\b([^>]*)>', caseSensitive: false);
final _attr = RegExp(r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''');
final _ogVideo = RegExp(
    r'''<meta[^>]+(?:property|name)\s*=\s*["'](?:og:video(?::url|:secure_url)?|twitter:player:stream)["'][^>]*content\s*=\s*["']([^"']+)["']''',
    caseSensitive: false);
final _jsonKey = RegExp(r'''["']?(?:contentUrl|embedUrl|file|src|source|hls|hlsUrl|dash|videoUrl|video_url|stream|streamUrl|url)["']?\s*[:=]\s*["']([^"']+)["']''');
final _quotedMedia = RegExp(
    r'''["']((?:https?:)?//[^"'\s<>]+?\.(?:m3u8|mpd|mp4|webm|mkv|m4v)(?:\?[^"'\s<>]*)?)["']''',
    caseSensitive: false);
final _anchor = RegExp(r'<a\b([^>]*)>(.*?)</a>', caseSensitive: false, dotAll: true);
final _img = RegExp(r'<img\b([^>]*)>', caseSensitive: false);
final _tags = RegExp(r'<[^>]*>');
final _space = RegExp(r'\s+');
final _height = RegExp(r'(?<![\d])(2160|1440|1080|720|576|540|480|360|240|144)[pP]?(?![\d])');

/// Reads [html] (fetched from [page]): its title, the media it points at, its
/// frames and its links. Ads and ad frames are left out (see [isAdUrl]).
/// Never runs a script; packed scripts are unpacked as text and read too.
PageScan scanPage(String html, Uri page) {
  final text = html.replaceAll(r'\/', '/');
  final media = <MediaCandidate>{};
  final frames = <Uri>{};

  void addMedia(String raw, {String? label, String? type}) {
    final url = _resolve(page, _decodeEntities(raw));
    if (url == null || isAdUrl(url)) return;
    final kind = mediaKindOf(url, type: type);
    if (kind == null) return;
    media.add(MediaCandidate(
      url: url,
      kind: kind,
      referer: page,
      label: label,
      height: _heightIn(label) ?? _heightIn(url.path),
    ));
  }

  for (final m in _tag.allMatches(text)) {
    final name = m.group(1)!.toLowerCase();
    final attrs = _attrs(m.group(2)!);
    final src = attrs['src'] ?? attrs['data-src'] ?? attrs['data-lazy-src'];
    if (src == null || src.isEmpty) continue;
    final srcUrl = Uri.tryParse(src);
    if (name == 'iframe' || (name == 'embed' && (srcUrl == null || mediaKindOf(srcUrl) == null))) {
      final url = _resolve(page, _decodeEntities(src));
      if (url != null && !isAdUrl(url) && url != page) frames.add(url);
    } else {
      addMedia(src, label: attrs['label'] ?? attrs['title'] ?? attrs['res'] ?? attrs['size'], type: attrs['type']);
    }
  }
  for (final m in _ogVideo.allMatches(text)) {
    addMedia(m.group(1)!);
  }
  for (final source in [text, ...unpackAll(text).map((s) => s.replaceAll(r'\/', '/'))]) {
    for (final m in _jsonKey.allMatches(source)) {
      addMedia(m.group(1)!, label: _labelNear(source, m.end));
    }
    for (final m in _quotedMedia.allMatches(source)) {
      addMedia(m.group(1)!, label: _labelNear(source, m.end));
    }
  }

  return PageScan(
    page: page,
    title: _cleanText(_ogTitle.firstMatch(text)?.group(1) ?? _title.firstMatch(text)?.group(1)),
    media: rankMedia(media),
    frames: frames.toList(),
    links: _links(text, page, frames),
  );
}

/// Best first: taller pictures, then HLS (adaptive), DASH, then plain files.
List<MediaCandidate> rankMedia(Iterable<MediaCandidate> media) => media.toList()
  ..sort((a, b) {
    final h = (b.height ?? 0).compareTo(a.height ?? 0);
    return h != 0 ? h : a.kind.index.compareTo(b.kind.index);
  });

/// What kind of media [url] is, from its extension or [type]; null when it
/// is not media.
MediaKind? mediaKindOf(Uri url, {String? type}) {
  final t = (type ?? '').toLowerCase();
  if (t.contains('mpegurl')) return MediaKind.hls;
  if (t.contains('dash+xml')) return MediaKind.dash;
  final path = url.path.toLowerCase();
  if (path.endsWith('.m3u8')) return MediaKind.hls;
  if (path.endsWith('.mpd')) return MediaKind.dash;
  if (RegExp(r'\.(mp4|webm|mkv|m4v|mov)$').hasMatch(path)) return MediaKind.file;
  if (t.startsWith('video/')) return MediaKind.file;
  return null;
}

List<PageLink> _links(String text, Uri page, Set<Uri> frames) {
  final out = <PageLink>[];
  final seen = <Uri>{page};
  for (final m in _anchor.allMatches(text)) {
    final href = _attrs(m.group(1)!)['href'];
    if (href == null || href.startsWith('#')) continue;
    final url = _resolve(page, _decodeEntities(href));
    if (url == null || isAdUrl(url) || frames.contains(url)) continue;
    final bare = url.removeFragment();
    if (!seen.add(bare)) continue;
    final inner = m.group(2)!;
    final img = _img.firstMatch(inner);
    final imgAttrs = img == null ? const <String, String>{} : _attrs(img.group(1)!);
    final label = _cleanText(inner) ?? _cleanText(_attrs(m.group(1)!)['title']) ?? _cleanText(imgAttrs['alt']);
    if (label == null) continue;
    final imgSrc = imgAttrs['data-src'] ?? imgAttrs['data-lazy-src'] ?? imgAttrs['src'];
    final image = imgSrc == null || imgSrc.startsWith('data:') ? null : _resolve(page, _decodeEntities(imgSrc));
    out.add(PageLink(url: bare, text: label, image: image));
    if (out.length >= _maxLinks) break;
  }
  return out;
}

Map<String, String> _attrs(String s) => {
      for (final m in _attr.allMatches(s)) m.group(1)!.toLowerCase(): m.group(2) ?? m.group(3) ?? m.group(4) ?? '',
    };

/// An absolute http(s) URL for [raw] on [page], or null.
Uri? _resolve(Uri page, String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final Uri url;
  try {
    url = page.resolve(s);
  } on FormatException {
    return null;
  }
  if ((url.scheme != 'http' && url.scheme != 'https') || url.host.isEmpty) return null;
  return url;
}

/// A quality label just after a URL in a player config, e.g.
/// `{file:"...", label:"720p"}`.
String? _labelNear(String s, int from) {
  final window = s.substring(from, (from + 80).clamp(0, s.length));
  final m = RegExp(r'''^[^{}\[\]]*?["']?(?:label|res|quality|title)["']?\s*:\s*["']?([^"',}]+)''').firstMatch(window);
  return m?.group(1)?.trim();
}

int? _heightIn(String? s) {
  if (s == null) return null;
  final m = _height.firstMatch(s);
  return m == null ? null : int.parse(m.group(1)!);
}

String? _cleanText(String? s) {
  if (s == null) return null;
  final t = _decodeEntities(s.replaceAll(_tags, ' ')).replaceAll(_space, ' ').trim();
  return t.isEmpty ? null : t;
}

String _decodeEntities(String s) => s
    .replaceAllMapped(RegExp(r'&#(\d{1,7});'), (m) => _char(int.parse(m.group(1)!)))
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]{1,6});'), (m) => _char(int.parse(m.group(1)!, radix: 16)))
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

String _char(int code) => code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : ' ';

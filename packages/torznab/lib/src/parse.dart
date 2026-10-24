import 'package:xml/xml.dart';

import 'api.dart';
import 'fetch.dart';

/// 6000-6999 is the adult range. Chithram never asks for it and drops it.
bool isAdultCategory(int c) => c >= 6000 && c < 7000;

XmlDocument _doc(String body) {
  try {
    final d = XmlDocument.parse(body);
    final root = d.rootElement;
    if (root.name.local == 'error') {
      final code = root.getAttribute('code');
      final desc = root.getAttribute('description') ?? 'unknown error';
      throw TorznabException(_errorText(code, desc), code: code);
    }
    return d;
  } on XmlException {
    throw TorznabException('The answer is not Torznab XML');
  }
}

String _errorText(String? code, String desc) {
  final c = int.tryParse(code ?? '');
  if (c != null && c >= 100 && c <= 199) return 'The indexer refused the API key: $desc';
  if (c != null && c >= 200 && c < 300) return 'The indexer rejected the request: $desc';
  return 'The indexer reported an error: $desc';
}

bool _yes(XmlElement? e) => e != null && (e.getAttribute('available') ?? '').toLowerCase() == 'yes';

/// `t=caps`.
TorznabCaps parseCaps(String body) {
  final root = _doc(body).rootElement;
  final searching = root.getElement('searching');
  final cats = <int>{};
  for (final c in root.descendantElements.where((e) => e.name.local == 'category' || e.name.local == 'subcat')) {
    final id = int.tryParse(c.getAttribute('id') ?? '');
    if (id != null && !isAdultCategory(id)) cats.add(id);
  }
  return TorznabCaps(
    search: _yes(searching?.getElement('search')),
    tvSearch: _yes(searching?.getElement('tv-search')),
    movieSearch: _yes(searching?.getElement('movie-search')),
    categories: cats.toList()..sort(),
  );
}

/// The items of a search answer, adult categories dropped.
List<TorznabItem> parseItems(String body) {
  final root = _doc(body).rootElement;
  final out = <TorznabItem>[];
  for (final item in root.findAllElements('item')) {
    final parsed = _item(item);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

final _hex40 = RegExp(r'^[0-9a-fA-F]{40}$');

TorznabItem? _item(XmlElement e) {
  String? text(String name) {
    final v = e.getElement(name)?.innerText.trim();
    return v == null || v.isEmpty ? null : v;
  }

  final attrs = <String, List<String>>{};
  for (final a in e.childElements) {
    if (a.name.local != 'attr') continue;
    final n = a.getAttribute('name');
    final v = a.getAttribute('value');
    if (n != null && v != null) (attrs[n] ??= []).add(v);
  }
  String? attr(String n) => attrs[n]?.first;
  int? intAttr(String n) => int.tryParse(attr(n) ?? '');

  final cats = <int>{
    for (final v in attrs['category'] ?? const <String>[]) ?int.tryParse(v),
    for (final c in e.findElements('category')) ?int.tryParse(c.innerText.trim()),
  };
  if (cats.any(isAdultCategory)) return null;

  final title = text('title');
  if (title == null) return null;

  final enclosure = e.getElement('enclosure');
  final enclosureUrl = enclosure?.getAttribute('url');
  final link = text('link');
  String? magnet = attr('magneturl');
  String? torrentUrl;
  for (final u in [enclosureUrl, link]) {
    if (u == null) continue;
    if (u.startsWith('magnet:')) {
      magnet ??= u;
    } else if (torrentUrl == null && (u.startsWith('http://') || u.startsWith('https://'))) {
      torrentUrl = u;
    }
  }
  if (magnet != null && !magnet.startsWith('magnet:')) magnet = null;

  final hash = attr('infohash');
  final seeders = intAttr('seeders');
  var leechers = intAttr('leechers');
  final peers = intAttr('peers');
  if (leechers == null && peers != null && seeders != null) leechers = (peers - seeders).clamp(0, 1 << 31);

  return TorznabItem(
    title: title,
    guid: text('guid'),
    infoHash: hash != null && _hex40.hasMatch(hash) ? hash.toLowerCase() : null,
    magnet: magnet,
    torrentUrl: torrentUrl,
    detailsUrl: text('comments') ?? (link != null && link != torrentUrl && !link.startsWith('magnet:') ? link : null),
    sizeBytes:
        intAttr('size') ?? int.tryParse(enclosure?.getAttribute('length') ?? '') ?? int.tryParse(text('size') ?? ''),
    seeders: seeders,
    leechers: leechers,
    published: parseDate(text('pubDate')),
    categories: cats.toList()..sort(),
  );
}

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/// RFC 822 (`Sat, 24 Oct 2026 08:00:00 +0000`, `GMT`, `Z`) or ISO 8601; null
/// when neither fits.
DateTime? parseDate(String? s) {
  if (s == null) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toUtc();
  final m = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,3})?',
  ).firstMatch(s);
  if (m == null) return null;
  final month = _months.indexOf(m.group(2)!.toLowerCase());
  if (month < 0) return null;
  var year = int.parse(m.group(3)!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  var t = DateTime.utc(
    year,
    month + 1,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
  final zone = m.group(7);
  if (zone != null && RegExp(r'^[+-]\d{4}$').hasMatch(zone)) {
    final off = Duration(hours: int.parse(zone.substring(1, 3)), minutes: int.parse(zone.substring(3, 5)));
    t = zone.startsWith('+') ? t.subtract(off) : t.add(off);
  }
  return t;
}

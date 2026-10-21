import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:xml/xml_events.dart';

import 'm3u.dart';

class EpgChannel {
  EpgChannel(this.id, this.names, this.icon);
  final String id;
  final List<String> names;
  final String? icon;
}

class EpgProgramme {
  EpgProgramme({
    required this.channel,
    required this.start,
    required this.stop,
    required this.title,
    this.description,
    this.categories = const [],
    this.lang,
  });
  final String channel;
  final DateTime start; // UTC
  final DateTime stop; // UTC
  final String title;
  final String? description;
  final List<String> categories;
  final String? lang;

  bool airingAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);
}

/// A batch of parsed items; the consumer inserts it in one DB transaction.
class EpgBatch {
  EpgBatch(this.channels, this.programmes);
  final List<EpgChannel> channels;
  final List<EpgProgramme> programmes;
}

/// Which programmes to keep. Default -1 day .. +3 days around [now];
/// channels with catch-up keep as many past days as [catchupDays] says.
class EpgWindow {
  EpgWindow({
    DateTime? now,
    this.past = const Duration(days: 1),
    this.future = const Duration(days: 3),
    this.catchupDays = const {},
  }) : now = (now ?? DateTime.now()).toUtc();
  final DateTime now;
  final Duration past;
  final Duration future;

  /// EPG channel id -> days of catch-up.
  final Map<String, int> catchupDays;

  DateTime startFor(String channel) {
    final d = catchupDays[channel];
    final p = (d != null && d * 24 > past.inHours) ? Duration(days: d) : past;
    return now.subtract(p);
  }

  DateTime get end => now.add(future);

  bool keeps(String channel, DateTime start, DateTime stop) =>
      stop.isAfter(startFor(channel)) && start.isBefore(end);
}

/// Parses `20260101120000 +0530` (zone optional, defaults to UTC) into UTC.
DateTime? parseXmltvTime(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.length < 8) return null;
  int? n(int a, int b) =>
      t.length >= b ? int.tryParse(t.substring(a, b)) : null;
  final y = n(0, 4), mo = n(4, 6), d = n(6, 8);
  if (y == null || mo == null || d == null) return null;
  final h = n(8, 10) ?? 0, mi = n(10, 12) ?? 0, se = n(12, 14) ?? 0;
  var dt = DateTime.utc(y, mo, d, h, mi, se);
  final m = RegExp(r'([+-])(\d{2}):?(\d{2})\s*$').firstMatch(t.substring(14 > t.length ? t.length : 14));
  if (m != null) {
    final off = Duration(
        hours: int.parse(m.group(2)!), minutes: int.parse(m.group(3)!));
    dt = m.group(1) == '+' ? dt.subtract(off) : dt.add(off);
  }
  return dt;
}

/// gunzips when the stream starts with the gzip magic, else passes through.
Stream<List<int>> maybeGunzip(Stream<List<int>> src) async* {
  final it = StreamIterator(src);
  if (!await it.moveNext()) return;
  final first = it.current;
  final isGz = first.length >= 2 && first[0] == 0x1f && first[1] == 0x8b;
  Stream<List<int>> rest() async* {
    yield first;
    while (await it.moveNext()) {
      yield it.current;
    }
  }

  try {
    if (isGz) {
      yield* rest().transform(gzip.decoder);
    } else {
      yield* rest();
    }
  } finally {
    await it.cancel();
  }
}

/// Streaming XMLTV parse. Pure over a byte stream, so it is safe to call from
/// inside `Isolate.run`. Yields batches of at most [batchSize] programmes.
Stream<EpgBatch> parseXmltv(
  Stream<List<int>> bytes, {
  EpgWindow? window,
  int batchSize = 2000,
  int maxBytes = 1024 * 1024 * 1024,
  bool Function(String channelId)? keepChannel,
}) async* {
  final win = window ?? EpgWindow();
  var total = 0;
  final limited = maybeGunzip(bytes).map((c) {
    total += c.length;
    if (total > maxBytes) {
      throw M3uLimitException('XMLTV larger than $maxBytes bytes');
    }
    return c;
  });
  final events = limited
      .transform(const Utf8Decoder(allowMalformed: true))
      .toXmlEvents()
      .normalizeEvents()
      .flatten();

  var chans = <EpgChannel>[];
  var progs = <EpgProgramme>[];

  // Parser state.
  String? chId;
  List<String> chNames = [];
  String? chIcon;

  String? pChan;
  DateTime? pStart, pStop;
  String? pTitle, pDesc, pLang;
  List<String> pCats = [];

  String? textTarget; // current text-collecting element
  final text = StringBuffer();

  await for (final e in events) {
    if (e is XmlStartElementEvent) {
      final name = e.name;
      if (name == 'channel') {
        chId = _attr(e, 'id');
        chNames = [];
        chIcon = null;
      } else if (name == 'programme') {
        pChan = _attr(e, 'channel');
        pStart = parseXmltvTime(_attr(e, 'start'));
        pStop = parseXmltvTime(_attr(e, 'stop'));
        pTitle = null;
        pDesc = null;
        pLang = null;
        pCats = [];
      } else if (name == 'icon' && chId != null) {
        chIcon = _attr(e, 'src');
      } else if (name == 'display-name' && chId != null ||
          (pChan != null &&
              (name == 'title' || name == 'desc' || name == 'category'))) {
        textTarget = name;
        text.clear();
        if (name == 'title') pLang = _attr(e, 'lang') ?? pLang;
      }
      if (e.isSelfClosing) {
        // Self-closing: behave as immediate end.
        textTarget = null;
        if (name == 'programme') pChan = null;
        if (name == 'channel') chId = null;
      }
    } else if (e is XmlTextEvent) {
      if (textTarget != null && text.length < 8192) text.write(e.value);
    } else if (e is XmlCDATAEvent) {
      if (textTarget != null && text.length < 8192) text.write(e.value);
    } else if (e is XmlEndElementEvent) {
      final name = e.name;
      if (name == textTarget) {
        final v = text.toString().trim();
        if (v.isNotEmpty) {
          switch (name) {
            case 'display-name':
              chNames.add(v);
            case 'title':
              pTitle ??= v;
            case 'desc':
              pDesc ??= v;
            case 'category':
              pCats.add(v);
          }
        }
        textTarget = null;
      } else if (name == 'channel' && chId != null) {
        if (keepChannel == null || keepChannel(chId)) {
          chans.add(EpgChannel(chId, chNames, chIcon));
        }
        chId = null;
      } else if (name == 'programme' && pChan != null) {
        final c = pChan, s = pStart, st = pStop;
        if (s != null &&
            st != null &&
            pTitle != null &&
            (keepChannel == null || keepChannel(c)) &&
            win.keeps(c, s, st)) {
          progs.add(EpgProgramme(
            channel: c,
            start: s,
            stop: st,
            title: pTitle,
            description: pDesc,
            categories: pCats,
            lang: pLang,
          ));
        }
        pChan = null;
        if (progs.length >= batchSize) {
          yield EpgBatch(chans, progs);
          chans = [];
          progs = [];
        }
      }
    }
  }
  if (chans.isNotEmpty || progs.isNotEmpty) yield EpgBatch(chans, progs);
}

String? _attr(XmlStartElementEvent e, String name) {
  for (final a in e.attributes) {
    if (a.name == name) return a.value;
  }
  return null;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// Maps playlist channels to EPG channel ids. Order of preference: exact
/// tvg-id, case-insensitive tvg-id, normalised name against EPG display names.
/// Returns playlist-entry index -> EPG channel id.
Map<int, String> mapChannelsToEpg(
    List<M3uEntry> entries, Iterable<EpgChannel> epg) {
  final byId = <String, String>{};
  final byLowerId = <String, String>{};
  final byName = <String, String>{};
  for (final c in epg) {
    byId[c.id] = c.id;
    byLowerId[c.id.toLowerCase()] = c.id;
    for (final n in c.names) {
      byName.putIfAbsent(_norm(n), () => c.id);
    }
  }
  final out = <int, String>{};
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final id = e.tvgId;
    String? hit;
    if (id != null) hit = byId[id] ?? byLowerId[id.toLowerCase()];
    hit ??= byName[_norm(e.tvgName ?? e.name)];
    if (hit != null) out[i] = hit;
  }
  return out;
}

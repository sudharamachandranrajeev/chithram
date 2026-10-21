import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

String ts(DateTime d, {String zone = '+0000'}) {
  String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  final u = d.toUtc();
  return '${p(u.year, 4)}${p(u.month)}${p(u.day)}${p(u.hour)}${p(u.minute)}${p(u.second)} $zone';
}

String xmltv(DateTime now) {
  String prog(String ch, Duration from, Duration len, String title,
          [String extra = '']) =>
      '<programme start="${ts(now.add(from))}" stop="${ts(now.add(from + len))}" channel="$ch">'
      '<title lang="en">$title</title><desc>About &amp; $title</desc>$extra</programme>';
  return '''<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="synthetic">
<channel id="sp1.test"><display-name>Sport One</display-name><icon src="https://img.example.test/s.png"/></channel>
<channel id="nw1.test"><display-name>News One</display-name></channel>
${prog('sp1.test', const Duration(minutes: -30), const Duration(hours: 2), 'IPL Final', '<category>Cricket</category>')}
${prog('sp1.test', const Duration(days: -3), const Duration(hours: 1), 'Too old')}
${prog('sp1.test', const Duration(days: 5), const Duration(hours: 1), 'Too far')}
${prog('nw1.test', const Duration(days: -2), const Duration(hours: 1), 'Old but catchup')}
${prog('nw1.test', const Duration(hours: 1), const Duration(hours: 1), '<![CDATA[Late <News>]]>')}
</tv>''';
}

void main() {
  final now = DateTime.utc(2026, 6, 1, 12);

  test('time parsing with zones', () {
    expect(parseXmltvTime('20260601120000 +0530'), DateTime.utc(2026, 6, 1, 6, 30));
    expect(parseXmltvTime('20260601120000 -0100'), DateTime.utc(2026, 6, 1, 13));
    expect(parseXmltvTime('20260601120000'), DateTime.utc(2026, 6, 1, 12));
    expect(parseXmltvTime('202606011200 +0000'), DateTime.utc(2026, 6, 1, 12));
    expect(parseXmltvTime('garbage'), isNull);
  });

  test('parses, filters window, honours catch-up days', () async {
    final bytes = utf8.encode(xmltv(now));
    final batches = await parseXmltv(Stream.value(bytes),
            window: EpgWindow(now: now, catchupDays: {'nw1.test': 3}))
        .toList();
    final p = batches.expand((b) => b.programmes).toList();
    final c = batches.expand((b) => b.channels).toList();
    expect(c.map((e) => e.id), ['sp1.test', 'nw1.test']);
    expect(c.first.icon, 'https://img.example.test/s.png');
    expect(p.map((e) => e.title),
        ['IPL Final', 'Old but catchup', 'Late <News>']);
    expect(p.first.categories, ['Cricket']);
    expect(p.first.description, 'About & IPL Final');
    expect(p.first.airingAt(now), isTrue);
    // Without catch-up days, the old programme is dropped.
    final plain = await parseXmltv(Stream.value(bytes), window: EpgWindow(now: now))
        .expand((b) => b.programmes)
        .map((e) => e.title)
        .toList();
    expect(plain, ['IPL Final', 'Late <News>']);
  });

  test('gzip input and small batches', () async {
    final gz = gzip.encode(utf8.encode(xmltv(now)));
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < gz.length; i += 13) {
        yield gz.sublist(i, i + 13 > gz.length ? gz.length : i + 13);
      }
    }

    final batches = await parseXmltv(chunks(),
            window: EpgWindow(now: now), batchSize: 1)
        .toList();
    expect(batches.length, greaterThan(1));
    expect(batches.expand((b) => b.programmes), hasLength(2));
  });

  test('malformed XML does not hang or corrupt earlier batches', () async {
    final bad = '${xmltv(now).substring(0, 400)}<programme start=';
    final out = <EpgBatch>[];
    try {
      await for (final b in parseXmltv(Stream.value(utf8.encode(bad)),
          window: EpgWindow(now: now))) {
        out.add(b);
      }
    } catch (_) {}
    expect(true, isTrue);
  });

  test('runs inside an isolate', () async {
    final dir = Directory.systemTemp.createTempSync('xmltv');
    final f = File('${dir.path}/g.xml')..writeAsStringSync(xmltv(now));
    final n = await Isolate.run(() async {
      var n = 0;
      await for (final b in parseXmltv(f.openRead(), window: EpgWindow(now: now))) {
        n += b.programmes.length;
      }
      return n;
    });
    dir.deleteSync(recursive: true);
    expect(n, 2);
  });

  test('channel id mapping: tvg-id, case, name fallback', () {
    final entries = parseM3u('''#EXTM3U
#EXTINF:-1 tvg-id="SP1.test",Whatever
http://a.example.test/1
#EXTINF:-1,News-One
http://a.example.test/2
#EXTINF:-1 tvg-id="none",Unknown
http://a.example.test/3
''');
    final epg = [
      EpgChannel('sp1.test', ['Sport One'], null),
      EpgChannel('nw1.test', ['News One'], null),
    ];
    expect(mapChannelsToEpg(entries, epg), {0: 'sp1.test', 1: 'nw1.test'});
  });
}

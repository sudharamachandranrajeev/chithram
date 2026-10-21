@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

void summary(String line) {
  // ignore: avoid_print
  print('PERF $line');
  final f = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (f != null) File(f).writeAsStringSync('$line\n\n', mode: FileMode.append);
}

String two(int n) => n.toString().padLeft(2, '0');
String stamp(DateTime d) =>
    '${d.year}${two(d.month)}${two(d.day)}${two(d.hour)}${two(d.minute)}00 +0000';

void main() {
  test('10k-entry M3U parses in < 10 s', () async {
    final b = StringBuffer('#EXTM3U\n');
    for (var i = 0; i < 10000; i++) {
      b.write('#EXTINF:-1 tvg-id="ch$i.test" tvg-name="Channel $i" '
          'tvg-logo="https://img.example.test/$i.png" group-title="Group ${i % 40}",Channel $i\n'
          '#EXTVLCOPT:http-referrer=https://ref.example.test/\n'
          'https://s$i.example.test/live/$i.m3u8\n');
    }
    final bytes = utf8.encode(b.toString());
    final sw = Stopwatch()..start();
    var n = 0;
    await for (final _ in parseM3uStream(Stream.value(bytes))) {
      n++;
    }
    sw.stop();
    summary('M3U 10,000 entries (${(bytes.length / 1e6).toStringAsFixed(1)} MB): '
        '${sw.elapsedMilliseconds} ms');
    expect(n, 10000);
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('generated ~100 MB XMLTV ingests in < 120 s (in an isolate)', () async {
    final dir = Directory.systemTemp.createTempSync('xmltv_perf');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/guide.xml');
    final now = DateTime.now().toUtc();
    final sink = file.openWrite();
    sink.write('<?xml version="1.0" encoding="UTF-8"?>\n<tv>\n');
    const channels = 1500;
    for (var c = 0; c < channels; c++) {
      sink.write('<channel id="ch$c.test"><display-name>Channel $c</display-name></channel>\n');
    }
    // 30-minute slots across -2d..+5d; roughly 4/7 fall inside the window.
    var written = 0;
    var inWindow = 0;
    final desc = 'Synthetic description for load testing. ' * 3;
    var slot = 0;
    while (true) {
      for (var c = 0; c < channels; c++) {
        final start = now.subtract(const Duration(days: 2)).add(Duration(minutes: 30 * slot));
        final end = start.add(const Duration(minutes: 30));
        if (end.isAfter(now.subtract(const Duration(days: 1))) &&
            start.isBefore(now.add(const Duration(days: 3)))) {
          inWindow++;
        }
        sink.write('<programme start="${stamp(start)}" stop="${stamp(end)}" channel="ch$c.test">'
            '<title lang="en">Show $c-$slot</title><desc lang="en">$desc</desc>'
            '<category lang="en">Entertainment</category><category lang="en">Cricket</category>'
            '<episode-num system="xmltv_ns">0.$slot.</episode-num></programme>\n');
      }
      slot++;
      if (slot % 8 == 0) {
        await sink.flush();
        written = file.lengthSync();
        if (written > 100 * 1000 * 1000) break;
      }
      if (slot >= 336) slot = 0; // wrap: keep times bounded, still unique-ish
    }
    sink.write('</tv>\n');
    await sink.close();
    final size = file.lengthSync();

    final sw = Stopwatch()..start();
    final path = file.path;
    final nowMs = now.millisecondsSinceEpoch;
    final counts = await Isolate.run(() async {
      var progs = 0, chans = 0, batches = 0;
      await for (final b in parseXmltv(
        File(path).openRead(),
        window: EpgWindow(now: DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true)),
      )) {
        progs += b.programmes.length;
        chans += b.channels.length;
        batches++;
      }
      return (progs, chans, batches);
    });
    sw.stop();
    summary('XMLTV ${(size / 1e6).toStringAsFixed(0)} MB, $channels channels, '
        '${counts.$1} programmes kept, ${counts.$3} batches: ${sw.elapsed.inSeconds} s '
        '(${sw.elapsedMilliseconds} ms)');
    expect(counts.$2, channels);
    expect(counts.$1, greaterThan(0));
    expect(inWindow, greaterThan(0));
    expect(sw.elapsed, lessThan(const Duration(seconds: 120)));
  }, timeout: const Timeout(Duration(minutes: 6)));
}

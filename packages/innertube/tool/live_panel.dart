// Live panel: resolves 20 public videos through YouTubeResolver and records,
// for each, the winning tier, the best height the picker chooses and whether
// a ranged GET returns 206. Non-blocking in CI; writes panel.json and a
// markdown table (also to $GITHUB_STEP_SUMMARY).
//
//   dart run tool/live_panel.dart [outDir]
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:innertube/innertube.dart';

class Entry {
  const Entry(this.kind, this.label, {this.id, this.query, this.shorts = false, this.live = false, this.skip = 0});
  final String kind;
  final String label;
  final String? id;
  final String? query;
  final bool shorts;
  final bool live;

  /// Shorts only: how many matching hits to pass over, so two entries get two different videos.
  final int skip;
}

// Static ids are well-known official / Blender / Google-adjacent uploads;
// query entries resolve the first sensible search hit, which also exercises
// InnertubeBrowse.search against the live API.
const panel = [
  Entry('4K', 'Costa Rica 4K', id: 'LXb3EKWsInQ'),
  Entry('4K', 'Big Buck Bunny 4K 60fps', id: 'aqz-KE-bpKQ'),
  // Live ids rot (streams get replaced), so pick from the live-filtered search.
  Entry('live', 'Live: lofi radio', query: 'lofi hip hop radio', live: true),
  Entry('live', 'Live: synthwave radio', query: 'synthwave radio 24/7', live: true),
  Entry('music', 'Rick Astley - Never Gonna Give You Up', id: 'dQw4w9WgXcQ'),
  Entry('music', 'Despacito', id: 'kJQP7kiw5Fk'),
  Entry('music', 'Shape of You', id: 'JGwWNGJdvx8'),
  Entry('music', 'Gangnam Style', id: '9bZkp7q19f0'),
  Entry('music', 'Sorry - Justin Bieber', id: 'fRh_vgS2dFE'),
  Entry('music', 'Blank Space', id: 'e-ORhEE9VVg'),
  Entry('long', 'Big Buck Bunny', id: 'YE7VzlLtp-4'),
  Entry('long', 'Tears of Steel', id: 'R6MlUcmOul8'),
  Entry('Malayalam', 'Jimikki Kammal', query: 'Jimikki Kammal Velipadinte Pustakam video song'),
  Entry('Malayalam', 'Hridayam - Darshana', query: 'Hridayam Darshana official video song'),
  Entry('Malayalam', 'Premam - Malare', query: 'Premam Malare video song'),
  Entry('Tamil', 'Why This Kolaveri Di', query: 'Why This Kolaveri Di official video song'),
  Entry('Tamil', 'Arabic Kuthu', query: 'Arabic Kuthu Halamithi Habibo video song'),
  Entry('Tamil', 'Vaathi Coming', query: 'Vaathi Coming Master video song'),
  Entry('Shorts', 'a Short (search)', query: '#shorts', shorts: true),
  Entry('Shorts', 'a Short (search 2)', query: 'shorts funny', shorts: true, skip: 1),
];

class Row {
  Row(this.entry);
  final Entry entry;
  String id = '';
  String title = '';
  String tier = '-';
  int? maxHeight;
  int? pickedHeight;
  String codec = '';
  int? rangeStatus;
  String? hls;
  bool ok = false;
  String? failure;
  List<String> attempts = [];

  Map<String, Object?> toJson() => {
        'kind': entry.kind,
        'label': entry.label,
        'id': id,
        'title': title,
        'tier': tier,
        'maxHeight': maxHeight,
        'pickedHeight': pickedHeight,
        'codec': codec,
        'rangeStatus': rangeStatus,
        'hls': hls,
        'ok': ok,
        'failure': failure,
        'attempts': attempts,
      };
}

/// Candidate ids for a search entry, best first. Live entries use the live
/// filter, Shorts the under-4-minute filter keeping <= 60 s.
Future<List<String>> findIds(InnertubeBrowse browse, Entry e) async {
  final page = await browse.search(
    e.query!,
    params: e.live ? SearchFilter.live : (e.shorts ? SearchFilter.underFourMinutes : SearchFilter.videos),
  );
  final ids = <String>[];
  var skip = e.skip;
  for (final v in page.items) {
    final d = v.duration;
    if (e.live) {
      if (v.isLive || d == null) ids.add(v.videoId);
    } else if (e.shorts) {
      if (d != null && d.inSeconds <= 60) {
        if (skip-- > 0) continue;
        ids.add(v.videoId);
      }
    } else if (d != null && d.inSeconds >= 120 && d.inSeconds <= 600) {
      ids.add(v.videoId);
    }
  }
  return ids;
}

Future<void> main(List<String> args) async {
  final outDir = Directory(args.isNotEmpty ? args.first : 'panel_out')..createSync(recursive: true);
  final client = http.Client();
  final resolver = YouTubeResolver(client: client);
  final browse = InnertubeBrowse(client: client);
  const caps = DeviceCaps(maxHeight: 2160);
  final rows = <Row>[];

  for (final entry in panel) {
    final row = Row(entry);
    rows.add(row);
    try {
      var id = entry.id;
      late final VideoStreams streams;
      if (id != null) {
        row.id = id;
        streams = await resolver.resolve(id);
      } else {
        final ids = await findIds(browse, entry);
        if (ids.isEmpty) throw 'no search hit for "${entry.query}"';
        Object? last;
        VideoStreams? found;
        // Live: first candidate that really resolves as live with an HLS manifest.
        for (final candidate in ids.take(entry.live ? 6 : 1)) {
          try {
            final s = await resolver.resolve(candidate);
            if (entry.live && (!s.isLive || s.hlsManifestUrl == null)) {
              last = '$candidate is not live';
              continue;
            }
            row.id = candidate;
            found = s;
            break;
          } catch (error) {
            last = error;
          }
        }
        if (found == null) throw 'no resolvable hit for "${entry.query}": $last';
        streams = found;
      }
      row.title = streams.title;
      row.tier = streams.tier.name;
      row.attempts = [for (final a in streams.attempts) '${a.tier.name}:${a.ok ? 'ok' : a.error}'];
      row.maxHeight = streams.video.followedBy(streams.muxed).fold<int>(0, (m, f) => f.shortSide > m ? f.shortSide : m);
      if (entry.live || streams.isLive) {
        final hls = streams.hlsManifestUrl;
        if (hls == null) throw 'live video without an HLS manifest';
        row.hls = hls.toString().split('?').first;
        final response = await client.get(hls, headers: {'User-Agent': streams.userAgent}).timeout(const Duration(seconds: 15));
        row.rangeStatus = response.statusCode;
        row.ok = response.statusCode == 200 && response.body.startsWith('#EXTM3U');
        if (!row.ok) row.failure = 'HLS manifest answered ${response.statusCode}';
        continue;
      }
      final picked = pickFormats(streams, caps);
      final best = picked.video ?? picked.muxed;
      if (best == null) throw 'no format fits';
      row.pickedHeight = best.shortSide;
      row.codec = best.videoCodec?.name ?? '';
      final probe = await probeRange(client, best, streams.userAgent);
      row.rangeStatus = probe.status;
      final audio = picked.audio;
      if (audio != null && !(await probeRange(client, audio, streams.userAgent)).ok) {
        row.failure = 'audio range was not 206';
      }
      row.ok = probe.ok && row.failure == null && best.shortSide >= 1080;
      if (!probe.ok) row.failure = 'video range answered ${probe.status}';
      if (probe.ok && best.shortSide < 1080) row.failure = 'best is ${best.shortSide}p (< 1080p)';
    } catch (error) {
      row.failure = error is AllTiersFailed ? error.message : '$error';
    }
    stdout.writeln('${row.entry.kind.padRight(10)} ${row.id.padRight(12)} ${row.tier.padRight(9)} '
        '${row.pickedHeight ?? row.maxHeight ?? '-'}p range=${row.rangeStatus ?? '-'} ${row.ok ? 'OK' : 'FAIL ${row.failure}'}');
  }

  final passes = rows.where((r) => r.ok).length;
  final tiers = <String, int>{};
  for (final r in rows.where((r) => r.tier != '-')) {
    tiers[r.tier] = (tiers[r.tier] ?? 0) + 1;
  }
  final hd = rows.where((r) => (r.pickedHeight ?? 0) >= 1080).length;
  final summary = StringBuffer()
    ..writeln('## YouTube live panel')
    ..writeln()
    ..writeln('Pass: **$passes / ${rows.length}** (target >= 18). Resolved at >= 1080p: $hd. Tiers: ${jsonEncode(tiers)}.')
    ..writeln()
    ..writeln('| kind | video | tier | picked | max | codec | range | result |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final r in rows) {
    summary.writeln('| ${r.entry.kind} | `${r.id}` ${r.title.replaceAll('|', '/')} | ${r.tier} | '
        '${r.pickedHeight ?? '-'} | ${r.maxHeight ?? '-'} | ${r.codec} | ${r.rangeStatus ?? '-'} | '
        '${r.ok ? 'ok' : (r.failure ?? 'fail').replaceAll('|', '/')} |');
  }
  File('${outDir.path}/panel.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert([for (final r in rows) r.toJson()]));
  File('${outDir.path}/panel.md').writeAsStringSync(summary.toString());
  final step = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (step != null) File(step).writeAsStringSync(summary.toString(), mode: FileMode.append);
  stdout.writeln(summary);
  client.close();
  exit(0); // non-blocking: the verdict is in the summary
}

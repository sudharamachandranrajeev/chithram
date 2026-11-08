import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/features/torrents/downloads.dart';
import 'package:chithram/src/find/find_api.dart';
import 'package:chithram/src/find/find_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent/torrent.dart';

String hex(int n) => n.toRadixString(16).padLeft(40, '0');

FindResult result(String title, {int? seeders, int? size, String? hash, DateTime? published}) => FindResult(
      providerId: 'p',
      title: title,
      kind: ResultKind.torrent,
      seeders: seeders,
      sizeBytes: size,
      infoHash: hash,
      published: published,
    );

void main() {
  group('names', () {
    test('magnet dn', () {
      expect(magnetName('magnet:?xt=urn:btih:${hex(1)}&dn=Big+Buck%20Bunny'), 'Big Buck Bunny');
      expect(magnetName('magnet:?xt=urn:btih:${hex(1)}'), isNull);
      expect(magnetName('magnet:?dn=&xt=x'), isNull);
    });

    test('torrent name from bencode', () {
      final b = Uint8List.fromList(utf8.encode('d8:announce3:x:y4:infod6:lengthi5e4:name9:Film 2024ee'));
      expect(torrentName(b), 'Film 2024');
      expect(torrentName(Uint8List.fromList(utf8.encode('d4:infod6:lengthi5eee'))), isNull);
      expect(torrentName(Uint8List.fromList(utf8.encode('4:name99:short'))), isNull);
    });

    test('folder names are safe on Windows', () {
      expect(folderNameFor('A: B/C?*<>|"d. ', hex(3)), 'A B C d');
      expect(folderNameFor('...', hex(3)), hex(3).substring(0, 12));
      expect(folderNameFor('', 'abc'), 'abc');
      expect(folderNameFor('x' * 300, hex(3)).length, 120);
    });
  });

  test('limits parse and print', () {
    expect(parseLimit(''), 0);
    expect(parseLimit('500'), 500);
    expect(parseLimit('2m'), 2048);
    expect(parseLimit('1.5 MiB/s'), 1536);
    expect(parseLimit('fast'), isNull);
    expect(limitLabel(0), 'Unlimited');
    expect(limitLabel(500), '500 KiB/s');
    expect(limitLabel(2048), '2 MiB/s');
    expect(limitLabel(1536), '1.5 MiB/s');
  });

  test('a record survives the store', () async {
    final dir = await Directory.systemTemp.createTemp('chithram-dl-test');
    addTearDown(() => dir.delete(recursive: true));
    final store = DownloadStore(File('${dir.path}/downloads.json'));
    expect(await store.load(), isEmpty);
    final r = DownloadRecord(
      infoHash: hex(1),
      name: 'A',
      folder: '/d/A',
      magnet: 'magnet:?xt=urn:btih:${hex(1)}',
      paused: true,
      onlyFiles: const [0, 2],
      added: DateTime.utc(2026, 11, 8),
    );
    await store.save([r, DownloadRecord(infoHash: hex(2), name: 'B', folder: '/d/B')]);
    final back = await store.load();
    expect(back.map((x) => x.infoHash), [hex(1), hex(2)]);
    expect(back.first.paused, isTrue);
    expect(back.first.onlyFiles, [0, 2]);
    expect(back.first.added, DateTime.utc(2026, 11, 8));
    expect(back.last.magnet, isNull);
    final t = await store.saveTorrent(hex(2), Uint8List.fromList([1, 2, 3]));
    expect(await File(t).readAsBytes(), [1, 2, 3]);
    await File('${dir.path}/downloads.json').writeAsString('not json');
    expect(await store.load(), isEmpty);
  });

  test('download line', () {
    final d = Download(DownloadRecord(infoHash: hex(1), name: 'A', folder: '/d'));
    expect(downloadLine(d), 'Finding peers...');
    d.info = TorrentInfo(id: 1, name: 'A', files: const []);
    d.stats = const TorrentStats({
      'state': 'live',
      'progress_bytes': 512 * 1024 * 1024,
      'total_bytes': 1024 * 1024 * 1024,
      'uploaded_bytes': 0,
      'finished': false,
      'live': {
        'download_speed': {'mbps': 2.5},
        'upload_speed': {'mbps': 0.0},
        'time_remaining': {'human_readable': '3m'},
        'snapshot': {
          'peer_stats': {'live': 4},
        },
      },
    });
    final line = downloadLine(d);
    expect(line, contains('50.0%'));
    expect(line, contains('↓ 2.5 MiB/s'));
    expect(line, contains('3m left'));
    expect(line, contains('4 peers'));
    d.record = d.record.copyWith(paused: true);
    expect(downloadLine(d), startsWith('Paused'));
  });

  group('find results', () {
    test('sort by seeders, size, newest', () {
      final a = result('a', seeders: 5, size: 10, published: DateTime(2020));
      final b = result('b', seeders: 50, size: 1, published: DateTime(2025));
      final c = result('c', size: 100);
      expect(sortResults([a, b, c], FindSort.seeders).map((r) => r.title), ['b', 'a', 'c']);
      expect(sortResults([a, b, c], FindSort.size).map((r) => r.title), ['c', 'a', 'b']);
      expect(sortResults([a, b, c], FindSort.newest).map((r) => r.title), ['b', 'a', 'c']);
    });

    test('one row per torrent, the best seeded wins', () {
      final list = <FindResult>[];
      expect(mergeResult(list, result('x', seeders: 3, hash: hex(1).toUpperCase())), isTrue);
      expect(mergeResult(list, result('y', seeders: 1, hash: hex(1))), isFalse);
      expect(mergeResult(list, result('z', seeders: 9, hash: hex(1))), isTrue);
      expect(mergeResult(list, result('w')), isTrue);
      expect(list.map((r) => r.title), ['z', 'w']);
    });

    test('magnet from a hash', () {
      expect(resultMagnet(result('A B', hash: hex(2))), 'magnet:?xt=urn:btih:${hex(2)}&dn=A%20B');
      expect(resultMagnet(result('A')), isNull);
    });

    test('age', () {
      final now = DateTime(2026, 11, 8);
      expect(ageLabel(now, now), 'today');
      expect(ageLabel(DateTime(2026, 11, 3), now), '5d');
      expect(ageLabel(DateTime(2026, 5, 8), now), '6mo');
      expect(ageLabel(DateTime(2023, 11, 8), now), '3y');
    });
  });
}

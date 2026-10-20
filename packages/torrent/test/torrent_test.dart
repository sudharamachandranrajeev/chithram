import 'package:flutter_test/flutter_test.dart';
import 'package:torrent/torrent.dart';

void main() {
  test('package loads', () {
    expect(torrentPackageName, 'torrent');
  });

  test('parses add result', () {
    final info = TorrentInfo.fromJson({
      'ok': true,
      'id': 3,
      'name': 'Sintel',
      'files': [
        {'index': 0, 'path': 'sintel.mp4', 'length': 123, 'streamable': true},
        {'index': 1, 'path': 'readme.txt', 'length': 4, 'streamable': false},
      ],
    });
    expect(info.id, 3);
    expect(info.files.length, 2);
    expect(info.files[0].streamable, isTrue);
    expect(info.files[1].streamable, isFalse);
  });

  test('parses stats', () {
    final s = TorrentStats({
      'state': 'live',
      'progress_bytes': 10,
      'total_bytes': 100,
      'finished': false,
      'live': {
        'download_speed': {'mbps': 2.5, 'human_readable': '2.50 MiB/s'},
      },
    });
    expect(s.state, 'live');
    expect(s.progressBytes, 10);
    expect(s.downloadMibPerSec, 2.5);
  });
}

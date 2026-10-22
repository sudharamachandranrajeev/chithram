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
      'info_hash': 'AABBCCDDEEFF00112233445566778899AABBCCDD',
      'files': [
        {'index': 0, 'path': 'sintel.mp4', 'length': 123, 'streamable': true},
        {'index': 1, 'path': 'readme.txt', 'length': 4, 'streamable': false},
      ],
    });
    expect(info.id, 3);
    expect(info.infoHash, 'aabbccddeeff00112233445566778899aabbccdd');
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
        'snapshot': {
          'peer_stats': {'live': 7, 'queued': 3},
        },
      },
    });
    expect(s.state, 'live');
    expect(s.progressBytes, 10);
    expect(s.downloadMibPerSec, 2.5);
    expect(s.livePeers, 7);
  });
}

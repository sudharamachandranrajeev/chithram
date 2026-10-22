import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/features/torrents/torrent_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent/torrent.dart';

TorrentFile _f(int i, int len, {bool streamable = true}) =>
    TorrentFile(index: i, path: 'f$i', length: len, streamable: streamable);

void main() {
  group('btihFromMagnet', () {
    const hex = '0102030405060708090a0b0c0d0e0f1011121314';

    test('hex, any case', () {
      expect(btihFromMagnet('magnet:?xt=urn:btih:$hex&dn=x'), hex);
      expect(btihFromMagnet('magnet:?xt=urn:btih:${hex.toUpperCase()}'), hex);
    });

    test('base32', () {
      expect(btihFromMagnet('magnet:?dn=x&xt=urn:btih:AEBAGBAFAYDQQCIKBMGA2DQPCAIREEYU&tr=http://t/a'), hex);
      expect(btihFromMagnet('magnet:?xt=urn:btih:aebagbafaydqqcikbmga2dqpcaireeyu'), hex);
    });

    test('rejects the rest', () {
      expect(btihFromMagnet('magnet:?dn=nothing'), isNull);
      expect(btihFromMagnet('magnet:?xt=urn:btih:abc'), isNull);
      expect(btihFromMagnet('magnet:?xt=urn:btih:${hex}00'), isNull);
      expect(btihFromMagnet('magnet:?xt=urn:btih:AEBAGBAFAYDQQCIKBMGA2DQPCAIREE18'), isNull);
      expect(btihFromMagnet('https://example.com'), isNull);
    });
  });

  test('orderFiles: streamable first, largest first', () {
    final ordered = orderFiles([
      _f(0, 10, streamable: false),
      _f(1, 5),
      _f(2, 900, streamable: false),
      _f(3, 50),
      _f(4, 50),
    ]);
    expect(ordered.map((f) => f.index), [3, 4, 1, 2, 0]);
  });

  group('Socks5Address', () {
    test('accepts host:port, with or without credentials', () {
      final a = Socks5Address.tryParse(' socks5://127.0.0.1:1080 ')!;
      expect((a.host, a.port, a.url), ('127.0.0.1', 1080, 'socks5://127.0.0.1:1080'));
      expect(Socks5Address.tryParse('socks5://u:p@proxy.example:9050')!.url, 'socks5://u:p@proxy.example:9050');
      expect(Socks5Address.tryParse('socks5://[::1]:1080')!.host, '::1');
    });

    test('rejects the rest', () {
      for (final bad in [
        '',
        'socks5://host',
        'socks5://:1080',
        'socks5://host:0',
        'socks5://host:70000',
        'http://host:1080',
        'host:1080',
        'socks5://host:1080/path',
        'socks5://host:1080?x=1',
      ]) {
        expect(Socks5Address.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('NetworkGuard', () {
    test('starts unset and asks for a choice', () {
      final g = NetworkGuard(Prefs.memory());
      expect(g.choice.mode, NetworkMode.unset);
      expect(g.needsChoice, isTrue);
    });

    test('direct, then socks5, then reset', () async {
      final g = NetworkGuard(Prefs.memory());
      await g.useDirect();
      expect(g.choice.mode, NetworkMode.direct);
      expect(g.needsChoice, isFalse);
      await g.useSocks5('socks5://10.0.0.2:1080');
      expect(g.choice.mode, NetworkMode.socks5);
      expect(g.choice.socks5!.url, 'socks5://10.0.0.2:1080');
      await g.useDirect();
      expect(g.rememberedAddress, 'socks5://10.0.0.2:1080', reason: 'kept to prefill the dialog');
      await g.reset();
      expect(g.needsChoice, isTrue);
    });

    test('an invalid address throws and changes nothing', () async {
      final g = NetworkGuard(Prefs.memory());
      await expectLater(g.useSocks5('nonsense'), throwsFormatException);
      expect(g.needsChoice, isTrue);
    });

    test('a stored socks5 choice with a broken address is unset', () {
      final g = NetworkGuard(Prefs.memory({'torrent.network': 'socks5', 'torrent.socks5': 'x'}));
      expect(g.needsChoice, isTrue);
    });

    test('the signature changes with the choice, credentials masked in the label', () async {
      final g = NetworkGuard(Prefs.memory());
      await g.useSocks5('socks5://u:secret@h.example:1080');
      expect(g.choice.label, isNot(contains('secret')));
      final before = g.choice.signature;
      await g.useDirect();
      expect(g.choice.signature, isNot(before));
    });
  });

  test('quotaFor: min(2 GiB, a quarter of free), never 0', () {
    expect(quotaFor(null), 2 << 30);
    expect(quotaFor(100 << 30), 2 << 30);
    expect(quotaFor(4 << 30), 1 << 30);
    expect(quotaFor(0), greaterThan(0));
  });

  test('statusLine', () {
    expect(statusLine(null), 'Connecting...');
    expect(
      statusLine(TorrentStats({
        'state': 'live',
        'progress_bytes': 50,
        'total_bytes': 200,
        'live': {
          'download_speed': {'mbps': 2.25},
          'snapshot': {
            'peer_stats': {'live': 1},
          },
        },
      })),
      'Down 2.3 MiB/s | 1 peer | 25%',
    );
  });

  test('formatBytes and fileTitle', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KiB');
    expect(formatBytes(3 << 30), '3.0 GiB');
    expect(fileTitle('Show/S01/e1.mkv'), 'e1.mkv');
  });
}

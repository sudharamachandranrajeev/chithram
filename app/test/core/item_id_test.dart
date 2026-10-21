import 'package:chithram/src/core/item_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefixes', () {
    expect(ItemId.youtube('dQw4w9WgXcQ'), 'yt:dQw4w9WgXcQ');
    expect(ItemId.iptv('src1|bbc one'), 'iptv:src1|bbc one');
    expect(ItemId.source('m3u-1'), 'src:m3u-1');
  });

  test('torrent file ids lower-case the info hash', () {
    expect(ItemId.torrentFile('ABCDEF0123456789ABCDEF0123456789ABCDEF01', 3),
        'bt:abcdef0123456789abcdef0123456789abcdef01/3');
  });

  test('url ids ignore case of scheme and host, fragment and default port', () {
    final a = ItemId.url('HTTP://Example.COM:80/a/b.m3u8?x=1#frag');
    expect(a, ItemId.url('http://example.com/a/b.m3u8?x=1'));
    expect(a, matches(RegExp(r'^url:[0-9a-f]{16}$')));
    expect(ItemId.url('http://example.com/a/b.m3u8?x=2'), isNot(a));
    expect(ItemId.url('http://example.com:8080/a/b.m3u8?x=1'), isNot(a));
  });
}

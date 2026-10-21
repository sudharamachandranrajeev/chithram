import 'dart:convert';
import 'dart:typed_data';

import 'package:localsend_rx/src/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('acceptFile', () {
    Map<String, Object?> f(String name, int size, {String type = 'application/octet-stream', Object? preview, String id = 'a'}) =>
        {'id': id, 'fileName': name, 'size': size, 'fileType': type, 'preview': ?preview};

    test('message, txt file and torrent are accepted', () {
      expect(acceptFile(f('m.txt', 5, type: 'text/plain', preview: 'hello'))!.kind, FileKind.message);
      expect(acceptFile(f('m.txt', 5, type: 'text/plain; charset=utf-8', preview: 'hello'))!.kind, FileKind.message);
      expect(acceptFile(f('n.TXT', 5, type: 'text/plain'))!.kind, FileKind.textFile);
      expect(acceptFile(f('x.torrent', 100, type: 'application/x-bittorrent'))!.kind, FileKind.torrent);
      expect(acceptFile(f('X.TORRENT', 100))!.kind, FileKind.torrent);
    });

    test('everything else is refused', () {
      for (final name in ['a.png', 'a.mp4', 'a.apk', 'a.sh', 'a.torrent.exe', 'a', 'a.txt.html']) {
        expect(acceptFile(f(name, 10)), isNull, reason: name);
      }
      expect(acceptFile(f('a.png', 5, type: 'text/plain', preview: 'x')), isNotNull, reason: 'preview text is a message whatever the name');
      expect(acceptFile(f('a.png', 5, type: 'image/png', preview: 'x')), isNull);
      expect(acceptFile('nope'), isNull);
      expect(acceptFile(f('a.torrent', 10, id: 'bad id!')), isNull);
      expect(acceptFile(f('a.torrent', 10, id: '')), isNull);
      expect(acceptFile({'id': 'a', 'fileName': 'a.torrent', 'size': '10'}), isNull);
    });

    test('caps are inclusive', () {
      expect(acceptFile(f('a.torrent', maxTorrentBytes)), isNotNull);
      expect(acceptFile(f('a.torrent', maxTorrentBytes + 1)), isNull);
      expect(acceptFile(f('a.txt', maxMessageBytes, type: 'text/plain')), isNotNull);
      expect(acceptFile(f('a.txt', maxMessageBytes + 1, type: 'text/plain')), isNull);
      expect(acceptFile(f('m.txt', 1, type: 'text/plain', preview: 'a' * maxMessageBytes)), isNotNull);
      expect(acceptFile(f('m.txt', 1, type: 'text/plain', preview: 'a' * (maxMessageBytes + 1))), isNull);
      // Bytes, not characters.
      expect(acceptFile(f('m.txt', 1, type: 'text/plain', preview: 'é' * (maxMessageBytes ~/ 2 + 1))), isNull);
    });
  });

  test('looksLikeTorrent', () {
    expect(looksLikeTorrent(Uint8List.fromList(ascii.encode('d4:infod4:name1:aee'))), isTrue);
    expect(looksLikeTorrent(Uint8List.fromList(ascii.encode('l4:infoe'))), isFalse);
    expect(looksLikeTorrent(Uint8List.fromList(ascii.encode('d3:fooi1ee'))), isFalse);
    expect(looksLikeTorrent(Uint8List(0)), isFalse);
  });

  test('cleanLabel strips control and direction-override characters and caps length', () {
    expect(cleanLabel('a\nb\tc'), 'a b c');
    expect(cleanLabel('x${String.fromCharCode(0x202e)}y'), 'x y');
    expect(cleanLabel('a' * 100), hasLength(64));
    expect(cleanLabel(5), '');
  });

  group('PeerInfo.parse', () {
    test('needs alias, a 2.x version and a fingerprint', () {
      expect(PeerInfo.parse({'alias': 'A', 'version': '2.1', 'fingerprint': 'F'}), isNotNull);
      expect(PeerInfo.parse({'alias': 'A', 'version': '1.0', 'fingerprint': 'F'}), isNull);
      expect(PeerInfo.parse({'alias': ' ', 'version': '2.1', 'fingerprint': 'F'}), isNull);
      expect(PeerInfo.parse({'alias': 'A', 'version': '2.1'}), isNull);
      expect(PeerInfo.parse(null), isNull);
    });
  });
}

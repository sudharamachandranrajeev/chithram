import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
List<int> unhex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

void main() {
  group('blake2b512 (vectors from Python hashlib)', () {
    test('empty', () {
      expect(hex(blake2b512([])),
          '786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce');
    });
    test('abc', () {
      expect(hex(blake2b512(utf8.encode('abc'))),
          'ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923');
    });
    test('768 bytes', () {
      final d = Uint8List.fromList([for (var i = 0; i < 768; i++) i % 256]);
      expect(hex(blake2b512(d)),
          '323e97a7a859ee63c9013debb0ca995811e73117a2f574723416e596ebc184e37a59b66d2f597df4a7c1b0d1d41a1a7f28774f46a6864d56c57b9d6c5f7302fb');
    });
    test('exactly one block and one block + 1', () {
      expect(hex(blake2b512(Uint8List(128))),
          '865939e120e6805438478841afb739ae4250cf372653078a065cdcfffca4caf798e6d462b65d658fc165782640eded70963449ae1500fb0f24981d7727e22c41');
      expect(hex(blake2b512(Uint8List(129))),
          'a60edba343e7a6933c14d203d2e535f35e6deb6c8a4f8e624c1a6f6e2612860447cb4c37e5aa11bcf03b7c3eea7228eb8b998f922794f2d1b8f2dc63f03bd3fa');
    });
  });

  group('ed25519', () {
    test('RFC 8032 test 1 (empty message)', () {
      final pk = unhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a');
      final sig = unhex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
          '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b');
      expect(ed25519Verify(pk, const [], sig), isTrue);
      expect(ed25519Verify(pk, const [1], sig), isFalse);
      final bad = List<int>.of(sig)..[40] ^= 1;
      expect(ed25519Verify(pk, const [], bad), isFalse);
    });
    test('python-reference signature', () {
      final pk = unhex('ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c');
      final sig = unhex('819f36c92dbeb0ac6872eb65fcfb93116dc15f1798028175aa8240c84106457f'
          '67e20094c0ee12e0b07c4ad749410887c49d758787564033c82c9e6e11958702');
      expect(ed25519Verify(pk, utf8.encode('hello nova'), sig), isTrue);
      expect(ed25519Verify(pk, utf8.encode('hello novb'), sig), isFalse);
    });
  });

  group('minisign', () {
    final dir = Directory('test/fixtures/repo_a');
    test('verifies a signature made by the reference signer (and by real minisign in CI)', () {
      final pub = MinisignPublicKey.parse(File('${dir.path}/repo.pub').readAsStringSync());
      final msg = File('${dir.path}/plugins.json').readAsBytesSync();
      final sig = File('${dir.path}/plugins.json.minisig').readAsStringSync();
      minisignVerify(pub, msg, sig);
      final tampered = Uint8List.fromList(msg)..[10] ^= 1;
      expect(() => minisignVerify(pub, tampered, sig), throwsA(isA<MinisignException>()));
    });
    test('trusted comment is signed too', () {
      final pub = MinisignPublicKey.parse(File('${dir.path}/repo.pub').readAsStringSync());
      final msg = File('${dir.path}/plugins.json').readAsBytesSync();
      final sig = File('${dir.path}/plugins.json.minisig').readAsStringSync().replaceFirst('repo:a', 'repo:x');
      expect(() => minisignVerify(pub, msg, sig), throwsA(isA<MinisignException>()));
    });
  });
}

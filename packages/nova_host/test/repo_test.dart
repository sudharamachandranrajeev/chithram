import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

Directory repo(String n) => Directory('test/fixtures/repo_$n');
String text(String n, String f) => File('${repo(n).path}/$f').readAsStringSync();
List<int> bytes(String n, String f) => File('${repo(n).path}/$f').readAsBytesSync();

void main() {
  test('good repo verifies and pins the key on first use', () async {
    final pins = MemoryPinStore();
    final v = await PluginRepoClient(pins).verify(
      repoId: 'r',
      manifestBytes: bytes('a', 'plugins.json'),
      signatureText: text('a', 'plugins.json.minisig'),
      publicKeyText: text('a', 'repo.pub'),
    );
    expect(v.firstUse, isTrue);
    expect(v.manifest.plugins.map((p) => p.id), ['demo', 'adultdemo']);
    expect(v.manifest.plugins.firstWhere((p) => p.id == 'adultdemo').adult, isTrue);
    expect(await pins.get('r'), isNotNull);
    // Second fetch uses the pin, with no public key supplied.
    final v2 = await PluginRepoClient(pins).verify(
      repoId: 'r',
      manifestBytes: bytes('a', 'plugins.json'),
      signatureText: text('a', 'plugins.json.minisig'),
    );
    expect(v2.firstUse, isFalse);
  });

  test('tampered manifest is refused', () async {
    final m = Uint8List.fromList(bytes('a', 'plugins.json'));
    final i = utf8.decode(m).indexOf('"demo"');
    m[i + 2] = 'x'.codeUnitAt(0); // "demo" -> "dxmo"
    expect(
      PluginRepoClient(MemoryPinStore()).verify(
        repoId: 'r',
        manifestBytes: m,
        signatureText: text('a', 'plugins.json.minisig'),
        publicKeyText: text('a', 'repo.pub'),
      ),
      throwsA(isA<RepoError>().having((e) => e.kind, 'kind', RepoErrorKind.badSignature)),
    );
  });

  test('tampered plugin file is refused (sha256)', () async {
    final client = PluginRepoClient(MemoryPinStore());
    final v = await client.verify(
      repoId: 'r',
      manifestBytes: bytes('a', 'plugins.json'),
      signatureText: text('a', 'plugins.json.minisig'),
      publicKeyText: text('a', 'repo.pub'),
    );
    final entry = v.manifest.plugins.first;
    expect(client.engineFor(entry, bytes('a', 'demo.py')).id, 'demo');
    final evil = bytes('a', 'demo.py').toList()..addAll(utf8.encode('\nimport os\n'));
    expect(() => client.engineFor(entry, evil),
        throwsA(isA<RepoError>().having((e) => e.kind, 'kind', RepoErrorKind.hashMismatch)));
  });

  test('rotated key is refused even though the new signature is valid', () async {
    final pins = MemoryPinStore();
    final client = PluginRepoClient(pins);
    await client.verify(
      repoId: 'r',
      manifestBytes: bytes('a', 'plugins.json'),
      signatureText: text('a', 'plugins.json.minisig'),
      publicKeyText: text('a', 'repo.pub'),
    );
    // Same manifest bytes, signed by a different (valid) key B, with B's public key offered.
    expect(
      client.verify(
        repoId: 'r',
        manifestBytes: bytes('b', 'plugins.json'),
        signatureText: text('b', 'plugins.json.minisig'),
        publicKeyText: text('b', 'repo.pub'),
      ),
      throwsA(isA<RepoError>().having((e) => e.kind, 'kind', RepoErrorKind.keyChanged)),
    );
  });

  test('an unsigned single .py runs with a warning flag and honours the adult header', () {
    final u = UnsignedPlugin.fromSource('demo.py', '# chithram: adult=true hosts=a.example,b.example\nclass demo: pass\n');
    expect(u.warning, contains('Unsigned'));
    expect(u.engine.adult, isTrue);
    expect(u.engine.hosts, ['a.example', 'b.example']);
    expect(() => UnsignedPlugin.fromSource('../evil.py', ''), throwsA(isA<RepoError>()));
  });

  test('manifest rejects path traversal and bad ids', () {
    String m(String file, String id) =>
        '{"plugins":[{"id":"$id","file":"$file","sha256":"${'0' * 64}"}]}';
    expect(() => RepoManifest.parse(utf8.encode(m('../x.py', 'ok'))), throwsA(isA<RepoError>()));
    expect(() => RepoManifest.parse(utf8.encode(m('x.py', 'a b'))), throwsA(isA<RepoError>()));
    expect(RepoManifest.parse(utf8.encode(m('x.py', 'ok'))).plugins, hasLength(1));
  });
}

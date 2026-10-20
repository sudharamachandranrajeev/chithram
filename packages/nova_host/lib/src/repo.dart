import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

import 'host.dart';
import 'minisign.dart';

enum RepoErrorKind { malformed, badSignature, keyChanged, hashMismatch }

class RepoError implements Exception {
  RepoError(this.kind, this.message);
  final RepoErrorKind kind;
  final String message;
  @override
  String toString() => 'RepoError(${kind.name}): $message';
}

class PluginEntry {
  PluginEntry({
    required this.id,
    required this.name,
    required this.file,
    required this.sha256,
    required this.version,
    required this.hosts,
    required this.adult,
  });

  final String id;
  final String name;
  final String file;
  final String sha256;
  final String version;
  final List<String> hosts;

  /// `adult: true` in the manifest: the app gates and hides these.
  final bool adult;
}

class RepoManifest {
  RepoManifest(this.name, this.plugins);
  final String name;
  final List<PluginEntry> plugins;

  factory RepoManifest.parse(List<int> bytes) {
    if (bytes.length > 1024 * 1024) throw RepoError(RepoErrorKind.malformed, 'manifest over 1 MiB');
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw RepoError(RepoErrorKind.malformed, 'manifest is not JSON');
    }
    if (j is! Map || j['plugins'] is! List) throw RepoError(RepoErrorKind.malformed, 'no plugins list');
    final idRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$');
    final plugins = <PluginEntry>[];
    for (final p in (j['plugins'] as List).take(500)) {
      if (p is! Map) throw RepoError(RepoErrorKind.malformed, 'bad plugin entry');
      final id = '${p['id']}';
      final file = '${p['file']}';
      final hash = '${p['sha256']}'.toLowerCase();
      if (!idRe.hasMatch(id)) throw RepoError(RepoErrorKind.malformed, 'bad plugin id "$id"');
      if (file.contains('/') || file.contains('\\') || file.contains('..') || !file.endsWith('.py')) {
        throw RepoError(RepoErrorKind.malformed, 'bad plugin file "$file"');
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) throw RepoError(RepoErrorKind.malformed, 'bad sha256 for $id');
      plugins.add(PluginEntry(
        id: id,
        name: '${p['name'] ?? id}',
        file: file,
        sha256: hash,
        version: '${p['version'] ?? ''}',
        hosts: [for (final h in (p['hosts'] as List? ?? const [])) '$h'],
        adult: p['adult'] == true,
      ));
    }
    return RepoManifest('${j['name'] ?? ''}', plugins);
  }
}

class PinnedKey {
  PinnedKey(this.keyIdHex, this.publicKeyText);
  final String keyIdHex;
  final String publicKeyText;
  Map<String, String> toJson() => {'keyId': keyIdHex, 'pub': publicKeyText};
}

abstract class KeyPinStore {
  Future<PinnedKey?> get(String repoId);
  Future<void> set(String repoId, PinnedKey key);
}

class MemoryPinStore implements KeyPinStore {
  final Map<String, PinnedKey> _m = {};
  @override
  Future<PinnedKey?> get(String repoId) async => _m[repoId];
  @override
  Future<void> set(String repoId, PinnedKey key) async => _m[repoId] = key;
}

class FilePinStore implements KeyPinStore {
  FilePinStore(this.path);
  final String path;

  Map<String, Object?> _read() {
    final f = File(path);
    if (!f.existsSync()) return {};
    return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
  }

  @override
  Future<PinnedKey?> get(String repoId) async {
    final e = _read()[repoId];
    if (e is! Map) return null;
    return PinnedKey('${e['keyId']}', '${e['pub']}');
  }

  @override
  Future<void> set(String repoId, PinnedKey key) async {
    final m = _read()..[repoId] = key.toJson();
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(m));
  }
}

class VerifiedRepo {
  VerifiedRepo(this.manifest, this.keyId, this.firstUse);
  final RepoManifest manifest;
  final String keyId;

  /// True when this call pinned the key (Trust On First Use): show the key id to the user.
  final bool firstUse;
}

/// Plugin repository: `plugins.json` + `plugins.json.minisig` (+ `repo.pub` on first add).
class PluginRepoClient {
  PluginRepoClient(this.pins);
  final KeyPinStore pins;

  /// Verifies the manifest signature. After the first success the key is pinned
  /// and any other key is refused, even if it signs correctly.
  Future<VerifiedRepo> verify({
    required String repoId,
    required List<int> manifestBytes,
    required String signatureText,
    String? publicKeyText,
  }) async {
    final MinisignSignature sig;
    try {
      sig = MinisignSignature.parse(signatureText);
    } on MinisignException catch (e) {
      throw RepoError(RepoErrorKind.badSignature, e.message);
    }
    final pinned = await pins.get(repoId);
    final MinisignPublicKey key;
    if (pinned != null) {
      key = MinisignPublicKey.parse(pinned.publicKeyText);
      if (!_same(sig.keyId, key.keyId)) {
        throw RepoError(RepoErrorKind.keyChanged,
            'repo is now signed by key ${_hex(sig.keyId)}, pinned key is ${pinned.keyIdHex}; refusing');
      }
      if (publicKeyText != null) {
        final offered = MinisignPublicKey.parse(publicKeyText);
        if (offered.fingerprint != key.fingerprint) {
          throw RepoError(RepoErrorKind.keyChanged, 'repo offers a different public key than the pinned one; refusing');
        }
      }
    } else {
      if (publicKeyText == null) throw RepoError(RepoErrorKind.malformed, 'first use needs the repo public key');
      try {
        key = MinisignPublicKey.parse(publicKeyText);
      } on MinisignException catch (e) {
        throw RepoError(RepoErrorKind.malformed, e.message);
      }
    }
    try {
      minisignVerify(key, manifestBytes, signatureText);
    } on MinisignException catch (e) {
      throw RepoError(RepoErrorKind.badSignature, e.message);
    }
    final manifest = RepoManifest.parse(manifestBytes);
    if (pinned == null) {
      await pins.set(repoId, PinnedKey(key.id, publicKeyText!));
    }
    return VerifiedRepo(manifest, key.id, pinned == null);
  }

  /// Checks a downloaded plugin file against its manifest entry and returns a runnable engine.
  NovaEngine engineFor(PluginEntry entry, List<int> fileBytes) {
    final actual = sha256.convert(fileBytes).toString();
    if (actual != entry.sha256) {
      throw RepoError(RepoErrorKind.hashMismatch, '${entry.id}: sha256 $actual != manifest ${entry.sha256}');
    }
    return NovaEngine(
      id: entry.id,
      source: utf8.decode(fileBytes),
      hosts: entry.hosts,
      adult: entry.adult,
    );
  }

  bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _hex(List<int> k) => k.reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

/// A single `.py` file added without a repo: runs, but the UI must show [warning].
class UnsignedPlugin {
  UnsignedPlugin(this.engine, this.warning);
  final NovaEngine engine;
  final String warning;

  /// Optional header: `# chithram: adult=true hosts=a.example,b.example`.
  factory UnsignedPlugin.fromSource(String fileName, String source) {
    final id = fileName.replaceAll(RegExp(r'\.py$'), '');
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(id)) {
      throw RepoError(RepoErrorKind.malformed, 'file name "$fileName" is not a valid plugin id');
    }
    var adult = false;
    final hosts = <String>[];
    for (final line in const LineSplitter().convert(source).take(15)) {
      final m = RegExp(r'^#\s*chithram:\s*(.*)$').firstMatch(line);
      if (m == null) continue;
      for (final kv in m.group(1)!.split(RegExp(r'\s+'))) {
        final parts = kv.split('=');
        if (parts.length != 2) continue;
        if (parts[0] == 'adult') adult = parts[1] == 'true';
        if (parts[0] == 'hosts') hosts.addAll(parts[1].split(',').where((h) => h.isNotEmpty));
      }
    }
    return UnsignedPlugin(
      NovaEngine(id: id, source: source, hosts: hosts, adult: adult),
      'Unsigned plugin: not from a verified repository. It can only reach the site it declares, '
      'but you are trusting its author.',
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'paths.dart';

/// Where keys live (the TMDB key, Torznab API keys). Never prefs, the database
/// or logs.
abstract interface class SecretStore {
  Future<String?> read(String k);
  Future<void> write(String k, String v);
  Future<void> delete(String k);

  /// True when the system keyring is unavailable and secrets sit in a 0600
  /// file instead (Linux without a keyring). Settings shows a notice.
  bool get isFallback;
}

/// Nothing persists. Tests and previews.
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String> initial = const {}]) : _m = Map.of(initial);
  final Map<String, String> _m;

  @override
  Future<String?> read(String k) async => _m[k];
  @override
  Future<void> write(String k, String v) async => _m[k] = v;
  @override
  Future<void> delete(String k) async => _m.remove(k);
  @override
  bool get isFallback => false;
}

/// flutter_secure_storage (Android Keystore, Windows credential store, Linux
/// libsecret). On Linux, when the keyring cannot be used, falls back to a
/// `secrets.json` created with mode 0600 and stays on it.
class SystemSecretStore implements SecretStore {
  SystemSecretStore({
    required File fallbackFile,
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    bool? linux,
  })  : _file = fallbackFile,
        _storage = storage,
        _linux = linux ?? Platform.isLinux;

  final File _file;
  final FlutterSecureStorage _storage;
  final bool _linux;
  bool _fallback = false;

  @override
  bool get isFallback => _fallback;

  /// Runs [op] on the keyring; on Linux a keyring failure (no D-Bus, no
  /// secret service, plugin missing) switches to the file for good.
  Future<T?> _keyring<T>(Future<T> Function() op) async {
    if (_fallback) return null;
    try {
      return await op();
    } on PlatformException {
      if (!_linux) rethrow;
    } on MissingPluginException {
      if (!_linux) rethrow;
    }
    _fallback = true;
    return null;
  }

  @override
  Future<String?> read(String k) async {
    final v = await _keyring(() => _storage.read(key: k));
    return _fallback ? (await _load())[k] : v;
  }

  @override
  Future<void> write(String k, String v) async {
    await _keyring(() => _storage.write(key: k, value: v));
    if (_fallback) await _save((await _load())..[k] = v);
  }

  @override
  Future<void> delete(String k) async {
    await _keyring(() => _storage.delete(key: k));
    if (_fallback) await _save((await _load())..remove(k));
  }

  Future<Map<String, String>> _load() async {
    try {
      if (!await _file.exists()) return {};
      final j = jsonDecode(await _file.readAsString());
      if (j is Map) return {for (final e in j.entries) '${e.key}': '${e.value}'};
    } catch (_) {
      // Unreadable: treat as empty rather than fail.
    }
    return {};
  }

  /// Created empty and chmod 600 before any secret is written; replaced by
  /// rename, so the mode never widens.
  Future<void> _save(Map<String, String> m) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString('', flush: true);
    final r = await Process.run('chmod', ['600', tmp.path]);
    if (r.exitCode != 0) {
      await tmp.delete();
      throw FileSystemException('could not restrict ${tmp.path} to its owner', tmp.path);
    }
    await tmp.writeAsString(jsonEncode(m), flush: true);
    await tmp.rename(_file.path);
  }
}

/// The real store for [paths].
SecretStore openSecretStore(AppPaths paths) =>
    SystemSecretStore(fallbackFile: paths.supportFile('secrets.json'));

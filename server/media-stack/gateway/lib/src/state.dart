import 'dart:convert';
import 'dart:io';

import 'fsperm.dart';
import 'roles.dart';

class UserRec {
  UserRec(this.name, this.role);
  String name;
  Role role;
  Map<String, Object?> toJson() => {'name': name, 'role': role.name};
}

class DeviceRec {
  DeviceRec({
    required this.id,
    required this.userId,
    required this.name,
    required this.tokenHash,
    required this.createdMs,
  });
  final String id;
  final String userId;
  final String name;
  final String
  tokenHash; // sha256 hex of the device token; the token itself is never stored
  final int createdMs;
  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'tokenHash': tokenHash,
    'createdMs': createdMs,
  };
}

class CodeRec {
  CodeRec({
    required this.salt,
    required this.hash,
    required this.userId,
    required this.expiresMs,
    this.attempts = 0,
  });
  final String salt;
  final String hash; // sha256 hex of salt + code
  final String userId;
  final int expiresMs;
  int attempts;
  Map<String, Object?> toJson() => {
    'salt': salt,
    'hash': hash,
    'userId': userId,
    'expiresMs': expiresMs,
    'attempts': attempts,
  };
}

class GatewayState {
  final Map<String, UserRec> users =
      {}; // Jellyfin userId -> record (role lives here)
  final List<DeviceRec> devices = [];
  final List<CodeRec> codes = [];

  Map<String, Object?> toJson() => {
    'users': {for (final e in users.entries) e.key: e.value.toJson()},
    'devices': [for (final d in devices) d.toJson()],
    'codes': [for (final c in codes) c.toJson()],
  };

  static GatewayState fromJson(Object? j) {
    final s = GatewayState();
    if (j is! Map) return s;
    final users = j['users'];
    if (users is Map) {
      for (final e in users.entries) {
        final v = e.value;
        if (e.key is String && v is Map) {
          final r = Role.parse(v['role']);
          if (r != null && v['name'] is String)
            s.users[e.key as String] = UserRec(v['name'] as String, r);
        }
      }
    }
    final devices = j['devices'];
    if (devices is List) {
      for (final v in devices) {
        if (v is Map &&
            v['id'] is String &&
            v['userId'] is String &&
            v['name'] is String &&
            v['tokenHash'] is String &&
            v['createdMs'] is int) {
          s.devices.add(
            DeviceRec(
              id: v['id'] as String,
              userId: v['userId'] as String,
              name: v['name'] as String,
              tokenHash: v['tokenHash'] as String,
              createdMs: v['createdMs'] as int,
            ),
          );
        }
      }
    }
    final codes = j['codes'];
    if (codes is List) {
      for (final v in codes) {
        if (v is Map &&
            v['salt'] is String &&
            v['hash'] is String &&
            v['userId'] is String &&
            v['expiresMs'] is int) {
          s.codes.add(
            CodeRec(
              salt: v['salt'] as String,
              hash: v['hash'] as String,
              userId: v['userId'] as String,
              expiresMs: v['expiresMs'] as int,
              attempts: (v['attempts'] is int) ? v['attempts'] as int : 0,
            ),
          );
        }
      }
    }
    return s;
  }
}

/// One JSON file (mode 600) shared by the server and the admin CLI. Every read-modify-write
/// takes an exclusive lock on a sidecar lock file and writes atomically (tmp + rename).
class StateStore {
  StateStore(this.dir)
    : _file = File('$dir/state.json'),
      _lock = File('$dir/state.lock');
  final String dir;
  final File _file;
  final File _lock;

  GatewayState _read() {
    if (!_file.existsSync()) return GatewayState();
    try {
      return GatewayState.fromJson(jsonDecode(_file.readAsStringSync()));
    } on FormatException {
      throw StateError('state file is corrupt; refusing to continue');
    }
  }

  /// Read-only snapshot (shared lock).
  GatewayState read() => _withLock(FileLock.blockingShared, _read);

  /// Locked read-modify-write; always persists.
  T update<T>(T Function(GatewayState s) f) {
    return _withLock(FileLock.blockingExclusive, () {
      final s = _read();
      final r = f(s);
      _write(s);
      return r;
    });
  }

  T _withLock<T>(FileLock mode, T Function() f) {
    Directory(dir).createSync(recursive: true);
    if (!_lock.existsSync()) {
      _lock.createSync();
      _mustChmod(_lock.path);
    }
    final raf = _lock.openSync(mode: FileMode.append);
    try {
      raf.lockSync(mode);
      return f();
    } finally {
      raf.unlockSync();
      raf.closeSync();
    }
  }

  static void _mustChmod(String path) {
    if (!chmod600(path)) {
      throw FileSystemException('cannot restrict file permissions', path);
    }
  }

  void _write(GatewayState s) {
    final tmp = File('$dir/.state.$pid.tmp');
    tmp.createSync();
    _mustChmod(tmp.path);
    tmp.writeAsStringSync(jsonEncode(s.toJson()), flush: true);
    tmp.renameSync(_file.path);
  }
}

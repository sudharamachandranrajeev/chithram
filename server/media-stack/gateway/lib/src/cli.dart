import 'dart:io';

import 'config.dart';
import 'jellyfin.dart';
import 'net.dart';
import 'pairing.dart';
import 'roles.dart';
import 'seerr.dart';
import 'state.dart';
import 'tls.dart';

const usage = '''
gateway serve
gateway healthcheck
gateway fingerprint
gateway pair --user <jellyfinUser> --role <requester|viewer|admin>
gateway users list
gateway users remove <jellyfinUser|userId>
gateway users set-role --user <jellyfinUser> --role <requester|viewer|admin>
gateway devices list
gateway devices revoke <deviceId>
''';

String? _opt(List<String> a, String name) {
  final i = a.indexOf(name);
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : null;
}

/// Admin commands. Return the process exit code. Output never contains tokens or key values;
/// the pairing code is printed once, on purpose, for the admin to hand to the device.
///
/// [jellyfin] and [seerr] are injectable for tests. Role changes are all-or-nothing: when the
/// Seerr permission sync fails, the gateway state is restored and the command exits non-zero,
/// so the gateway role and the Seerr permissions can never silently disagree.
Future<int> runAdmin(
  List<String> args,
  Config cfg, {
  Jellyfin? jellyfin,
  Seerr? seerr,
}) async {
  final store = StateStore(cfg.stateDir);
  final jf = jellyfin ?? Jellyfin(cfg);
  final sr = seerr ?? Seerr(cfg);
  switch (args.first) {
    case 'fingerprint':
      stdout.writeln(certFingerprint(File(cfg.tlsCertPath).readAsStringSync()));
      return 0;
    case 'pair':
      final user = _opt(args, '--user');
      final role = Role.parse(_opt(args, '--role'));
      if (user == null || role == null) {
        stderr.writeln(usage);
        return 2;
      }
      final u = await _resolve(jf, user);
      if (u == null) return 1;
      late final UserRec? before;
      final code = store.update((s) {
        before = s.users[u.id];
        s.users[u.id] = UserRec(u.name, role);
        return issueCode(s, u.id, DateTime.now().millisecondsSinceEpoch);
      });
      if (!await _syncSeerr(sr, u.id, role)) {
        _restore(store, u.id, before, dropCodes: true);
        return 1;
      }
      stdout.writeln('Pairing code for ${u.name} (${role.name}): $code');
      stdout.writeln(
        'Valid 10 minutes, single use, 5 wrong attempts invalidate it.',
      );
      stdout.writeln(
        'Certificate SHA-256: ${certFingerprint(File(cfg.tlsCertPath).readAsStringSync())}',
      );
      return 0;
    case 'users':
      final sub = args.length > 1 ? args[1] : '';
      if (sub == 'list') {
        final s = store.read();
        for (final e in s.users.entries) {
          stdout.writeln('${e.key}  ${e.value.name}  ${e.value.role.name}');
        }
        return 0;
      }
      if (sub == 'set-role') {
        final user = _opt(args, '--user');
        final role = Role.parse(_opt(args, '--role'));
        if (user == null || role == null) {
          stderr.writeln(usage);
          return 2;
        }
        final u = await _resolve(jf, user);
        if (u == null) return 1;
        late final UserRec? before;
        store.update((s) {
          before = s.users[u.id];
          s.users[u.id] = UserRec(u.name, role);
        });
        if (!await _syncSeerr(sr, u.id, role)) {
          _restore(store, u.id, before, dropCodes: false);
          return 1;
        }
        stdout.writeln('${u.name} is now ${role.name}');
        return 0;
      }
      if (sub == 'remove' && args.length > 2) {
        // No Jellyfin lookup (works for deleted users). Takes all Seerr permissions from the
        // user first, then drops the role record, pending codes and every paired device.
        // If Seerr cannot be updated nothing is changed, so the command can be repeated.
        // Argument: Jellyfin id or name.
        final who = args[2].toLowerCase();
        final ids = [
          for (final e in store.read().users.entries)
            if (e.key == who || e.value.name.toLowerCase() == who) e.key,
        ];
        if (ids.isEmpty) {
          stdout.writeln('no such user');
          return 1;
        }
        for (final id in ids) {
          try {
            if (!await sr.revoke(id)) {
              stderr.writeln(
                'note: this is the Seerr owner; its Seerr permissions cannot be removed here',
              );
            }
          } on UpstreamException catch (e) {
            stderr.writeln(
              'Seerr permission removal failed (${e.what}); nothing was changed, try again',
            );
            return 1;
          }
        }
        store.update((s) {
          for (final id in ids) {
            s.users.remove(id);
            s.devices.removeWhere((d) => d.userId == id);
            s.codes.removeWhere((c) => c.userId == id);
          }
        });
        stdout.writeln('removed user and devices');
        return 0;
      }
      stderr.writeln(usage);
      return 2;
    case 'devices':
      final sub = args.length > 1 ? args[1] : '';
      if (sub == 'list') {
        final s = store.read();
        for (final d in s.devices) {
          final who = s.users[d.userId]?.name ?? '?';
          final when = DateTime.fromMillisecondsSinceEpoch(
            d.createdMs,
            isUtc: true,
          ).toIso8601String();
          stdout.writeln('${d.id}  $who  "${d.name}"  paired $when');
        }
        return 0;
      }
      if (sub == 'revoke' && args.length > 2) {
        final id = args[2];
        final n = store.update((s) {
          final before = s.devices.length;
          s.devices.removeWhere((d) => d.id == id);
          return before - s.devices.length;
        });
        stdout.writeln(n == 0 ? 'no such device' : 'revoked $id');
        return n == 0 ? 1 : 0;
      }
      stderr.writeln(usage);
      return 2;
  }
  stderr.writeln(usage);
  return 2;
}

Future<JfUser?> _resolve(Jellyfin jf, String name) async {
  try {
    final u = await jf.findByName(name);
    if (u == null) stderr.writeln('no such Jellyfin user');
    return u;
  } on UpstreamException catch (e) {
    stderr.writeln('Jellyfin unavailable: ${e.what}');
    return null;
  }
}

/// True when Seerr now matches [role]. On failure prints why and returns false.
Future<bool> _syncSeerr(Seerr seerr, String jfId, Role role) async {
  try {
    await seerr.ensureUser(jfId, role);
    return true;
  } on UpstreamException catch (e) {
    stderr.writeln(
      'Seerr permission sync failed (${e.what}); the change was rolled back in the gateway',
    );
    return false;
  }
}

void _restore(
  StateStore store,
  String userId,
  UserRec? before, {
  required bool dropCodes,
}) {
  store.update((s) {
    if (before == null) {
      s.users.remove(userId);
    } else {
      s.users[userId] = before;
    }
    if (dropCodes) s.codes.removeWhere((c) => c.userId == userId);
  });
}

Future<int> healthcheck(Config cfg) async {
  final c = HttpClient()
    ..badCertificateCallback = ((_, _, _) => true)
    ..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await c.getUrl(
      Uri.parse('https://127.0.0.1:${cfg.port}/healthz'),
    );
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode == 200 ? 0 : 1;
  } catch (_) {
    return 1;
  } finally {
    c.close(force: true);
  }
}

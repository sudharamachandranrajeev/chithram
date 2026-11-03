import 'state.dart';
import 'util.dart';

const codeTtlMs = 10 * 60 * 1000;
const maxCodeAttempts = 5;

/// Creates a single-use code for [userId]; any earlier open code for that user is replaced.
/// Returns the plain code (shown once on the admin terminal, stored only salted+hashed).
String issueCode(GatewayState s, String userId, int now) {
  s.codes.removeWhere((c) => c.userId == userId);
  final code = newCode();
  final salt = newId();
  s.codes.add(
    CodeRec(
      salt: salt,
      hash: sha256Hex('$salt$code'),
      userId: userId,
      expiresMs: now + codeTtlMs,
    ),
  );
  return code;
}

class PairResult {
  PairResult(this.token, this.device);
  final String token; // returned once, never stored
  final DeviceRec device;
}

/// Tries to redeem [code]. On success the code is consumed and a device is created.
/// On failure every live code gets one more failed attempt; codes reaching
/// [maxCodeAttempts] are deleted, so a locked code stays dead even if guessed later.
PairResult? redeemCode(
  GatewayState s,
  String code,
  String deviceName,
  int now,
) {
  s.codes.removeWhere(
    (c) => c.expiresMs <= now || c.attempts >= maxCodeAttempts,
  );
  CodeRec? hit;
  for (final c in s.codes) {
    // no early exit: constant work over all live codes
    if (constantTimeEquals(c.hash, sha256Hex('${c.salt}$code'))) hit ??= c;
  }
  if (hit == null) {
    for (final c in s.codes) {
      c.attempts++;
    }
    s.codes.removeWhere((c) => c.attempts >= maxCodeAttempts);
    return null;
  }
  s.codes.remove(hit);
  if (!s.users.containsKey(hit.userId))
    return null; // user removed meanwhile: no device
  final token = newToken();
  final dev = DeviceRec(
    id: _freshDeviceId(s),
    userId: hit.userId,
    name: deviceName,
    tokenHash: sha256Hex(token),
    createdMs: now,
  );
  s.devices.add(dev);
  return PairResult(token, dev);
}

String _freshDeviceId(GatewayState s) {
  while (true) {
    final id = newId();
    if (!s.devices.any((d) => d.id == id)) return id;
  }
}

/// Looks up the device for a bearer token. Compares against every stored hash (no early exit).
DeviceRec? authenticate(GatewayState s, String token) {
  final h = sha256Hex(token);
  DeviceRec? hit;
  for (final d in s.devices) {
    if (constantTimeEquals(d.tokenHash, h)) hit = d;
  }
  return hit;
}

/// Sliding-window limiter for pairing attempts across all callers.
class Throttle {
  Throttle(this.max, this.windowMs);
  final int max;
  final int windowMs;
  final List<int> _hits = [];

  bool idle(int now) => _hits.every((t) => now - t >= windowMs);

  bool allow(int now) {
    _hits.removeWhere((t) => now - t >= windowMs);
    if (_hits.length >= max) return false;
    _hits.add(now);
    return true;
  }
}

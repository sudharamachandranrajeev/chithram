import 'dart:io';

/// 10/8, 172.16/12 and 192.168/16.
bool isPrivateV4(InternetAddress a) {
  if (a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
}

/// Tunnels and VPNs: never listen on them.
final _skippedInterface = RegExp(r'^(tun|wg|ppp|utun|tap|ipsec)', caseSensitive: false);

class PrivateInterface {
  const PrivateInterface(this.interface, this.address);

  final NetworkInterface interface;
  final InternetAddress address;
}

/// One entry per private IPv4 address on a non-tunnel interface.
Future<List<PrivateInterface>> privateInterfaces() async {
  final out = <PrivateInterface>[];
  try {
    for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      if (_skippedInterface.hasMatch(ni.name)) continue;
      for (final a in ni.addresses) {
        if (isPrivateV4(a)) out.add(PrivateInterface(ni, a));
      }
    }
  } on SocketException {
    // No interfaces readable: nothing to listen on.
  }
  return out;
}

/// Compares without stopping at the first difference.
bool constantTimeEquals(String a, String b) {
  var diff = a.length ^ b.length;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Counts wrong PINs per address. [maxFailures] wrong tries within [window]
/// lock that address out until the oldest one ages out.
class PinGuard {
  PinGuard({this.maxFailures = 5, this.window = const Duration(minutes: 10), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int maxFailures;
  final Duration window;
  final DateTime Function() _clock;
  final _failures = <String, List<DateTime>>{};

  void _prune(String ip) {
    final cutoff = _clock().subtract(window);
    final list = _failures[ip];
    if (list == null) return;
    list.removeWhere((t) => !t.isAfter(cutoff));
    if (list.isEmpty) _failures.remove(ip);
  }

  bool limited(String ip) {
    _prune(ip);
    return (_failures[ip]?.length ?? 0) >= maxFailures;
  }

  void fail(String ip) {
    // Bounded: a hostile LAN cannot grow this without limit.
    if (_failures.length > 256) _failures.remove(_failures.keys.first);
    (_failures[ip] ??= []).add(_clock());
  }
}

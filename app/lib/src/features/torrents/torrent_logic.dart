import 'dart:io';
import 'dart:math' as math;

import 'package:torrent/torrent.dart';

import '../../core/prefs.dart';
import '../../core/redact.dart';

/// Pure parts of the torrents feature: no engine, no widgets.

final _btihInMagnet = RegExp(r'xt=urn:btih:([0-9a-fA-F]{40}|[A-Za-z2-7]{32})(?:&|$)', caseSensitive: false);

/// The info hash of a magnet link as 40 lower-case hex characters. Accepts a
/// 40-character hex hash or a 32-character base32 one. Null when there is none.
String? btihFromMagnet(String magnet) {
  final m = _btihInMagnet.firstMatch(magnet.trim());
  if (m == null) return null;
  final h = m.group(1)!;
  if (h.length == 40) return h.toLowerCase();
  return _base32ToHex(h);
}

String? _base32ToHex(String s) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0;
  var value = 0;
  final out = StringBuffer();
  for (final c in s.toUpperCase().codeUnits) {
    final i = alphabet.indexOf(String.fromCharCode(c));
    if (i < 0) return null;
    value = (value << 5) | i;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.write(((value >> bits) & 0xff).toRadixString(16).padLeft(2, '0'));
      value &= (1 << bits) - 1;
    }
  }
  return out.toString();
}

/// Streamable files first, the largest first within each group.
List<TorrentFile> orderFiles(Iterable<TorrentFile> files) {
  final list = files.toList();
  list.sort((a, b) {
    if (a.streamable != b.streamable) return a.streamable ? -1 : 1;
    final bySize = b.length.compareTo(a.length);
    return bySize != 0 ? bySize : a.index.compareTo(b.index);
  });
  return list;
}

/// A validated `socks5://[user:pass@]host:port`.
class Socks5Address {
  const Socks5Address._(this.host, this.port, this.url);

  final String host;
  final int port;

  /// The normalised address, as the engine takes it (credentials included).
  final String url;

  /// Null when [raw] is not a SOCKS5 address with a host and a port.
  static Socks5Address? tryParse(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || u.scheme != 'socks5' || u.host.isEmpty || !u.hasPort) return null;
    if (u.port < 1 || u.port > 65535) return null;
    if ((u.path.isNotEmpty && u.path != '/') || u.hasQuery || u.hasFragment) return null;
    final url = Uri(scheme: 'socks5', userInfo: u.userInfo.isEmpty ? null : u.userInfo, host: u.host, port: u.port);
    return Socks5Address._(u.host, u.port, url.toString());
  }
}

enum NetworkMode { unset, socks5, direct }

/// What the user chose for torrent traffic.
class NetworkChoice {
  const NetworkChoice(this.mode, [this.socks5]);

  static const unset = NetworkChoice(NetworkMode.unset);

  final NetworkMode mode;

  /// Set when [mode] is socks5.
  final Socks5Address? socks5;

  /// Equal when the engine would have to start the same way.
  String get signature => '${mode.name}|${socks5?.url ?? ''}';

  /// For the UI: credentials masked.
  String get label => switch (mode) {
        NetworkMode.unset => 'not set',
        NetworkMode.direct => 'direct, no protection',
        NetworkMode.socks5 => 'SOCKS5 ${maskUrlCredentials(socks5!.url)}',
      };
}

/// The network-choice guard: unset until the user picks SOCKS5 or direct, kept
/// in prefs. A stored SOCKS5 choice with a broken address counts as unset.
class NetworkGuard {
  NetworkGuard(this.prefs);

  static const modeKey = 'torrent.network';
  static const addressKey = 'torrent.socks5';

  final Prefs prefs;

  NetworkChoice get choice {
    switch (prefs.getString(modeKey)) {
      case 'direct':
        return const NetworkChoice(NetworkMode.direct);
      case 'socks5':
        final a = Socks5Address.tryParse(prefs.getString(addressKey) ?? '');
        return a == null ? NetworkChoice.unset : NetworkChoice(NetworkMode.socks5, a);
    }
    return NetworkChoice.unset;
  }

  bool get needsChoice => choice.mode == NetworkMode.unset;

  /// The last SOCKS5 address entered, to prefill the dialog.
  String? get rememberedAddress => prefs.getString(addressKey);

  /// Throws [FormatException] when [address] is not `socks5://host:port`.
  Future<void> useSocks5(String address) async {
    final a = Socks5Address.tryParse(address);
    if (a == null) throw const FormatException('Use the form socks5://host:port');
    await prefs.set(addressKey, a.url);
    await prefs.set(modeKey, 'socks5');
  }

  Future<void> useDirect() => prefs.set(modeKey, 'direct');

  /// Back to unset: the next torrent action asks again.
  Future<void> reset() => prefs.set(modeKey, null);
}

/// A 2 s TCP connect to a SOCKS5 server. True when something answers.
Future<bool> probeSocks5(Socks5Address a) async {
  try {
    final s = await Socket.connect(a.host, a.port, timeout: const Duration(seconds: 2));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

const _gib = 1 << 30;

/// The cache quota: 2 GiB, or a quarter of the free space when that is less.
/// Never 0, which the engine reads as unlimited.
int quotaFor(int? freeBytes) {
  if (freeBytes == null) return 2 * _gib;
  return math.max(64 << 20, math.min(2 * _gib, freeBytes ~/ 4));
}

/// Free bytes on the volume holding [dir] (which must exist), or null when the
/// platform will not say.
Future<int?> freeSpaceBytes(Directory dir) async {
  try {
    if (Platform.isWindows) {
      final drive = dir.absolute.path.substring(0, 1);
      final r = await Process.run('powershell', ['-NoProfile', '-Command', "(Get-PSDrive -Name '$drive').Free"]);
      return int.tryParse('${r.stdout}'.trim());
    }
    final r = await Process.run('df', ['-Pk', dir.path]);
    final lines = '${r.stdout}'.trim().split('\n');
    if (lines.length < 2) return null;
    final kb = int.tryParse(lines.last.trim().split(RegExp(r'\s+'))[3]);
    return kb == null ? null : kb * 1024;
  } catch (_) {
    return null;
  }
}

String formatBytes(int b) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return i == 0 ? '$b B' : '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

/// One line for the files page and the player's status line.
String statusLine(TorrentStats? s) {
  if (s == null) return 'Connecting...';
  if (s.error != null) return 'Error: ${s.error}';
  final parts = <String>[];
  final speed = s.downloadMibPerSec;
  parts.add(speed == null ? s.state : 'Down ${speed.toStringAsFixed(1)} MiB/s');
  final peers = s.livePeers;
  if (peers != null) parts.add('$peers ${peers == 1 ? 'peer' : 'peers'}');
  if (s.totalBytes > 0) parts.add('${(s.progressBytes * 100 ~/ s.totalBytes)}%');
  return parts.join(' | ');
}

/// The last path segment of a torrent file path, for titles.
String fileTitle(String path) => path.split(RegExp(r'[\\/]')).last;

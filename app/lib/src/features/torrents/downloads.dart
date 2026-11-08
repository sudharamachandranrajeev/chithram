// Kept downloads: torrents saved to a folder of the user's, outside the
// stream cache. They survive a restart (downloads.json lists them; a .torrent
// added from a file is kept beside it), can be paused, narrowed to some files,
// and seed while the app is open unless seeding is off.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:torrent/torrent.dart';

import '../../core/paths.dart';
import '../../core/prefs.dart';
import 'torrent_logic.dart';

/// Prefs for downloads.
abstract final class DownloadPrefs {
  /// Base folder; empty = [defaultDownloadsBase].
  static const folder = 'torrent.downloads.folder';

  /// Speed limits in KiB/s; 0 or missing = unlimited.
  static const downKib = 'torrent.limit.down';
  static const upKib = 'torrent.limit.up';

  /// Keep sharing finished downloads while the app is open (default on).
  static const seed = 'torrent.seed';

  static int limitBps(Prefs p, String key) => ((p.getInt(key) ?? 0).clamp(0, 4 * 1024 * 1024)) * 1024;
}

/// The Downloads folder on a desktop, the app's external files on Android,
/// else the support folder: always somewhere the app may write.
Future<Directory> defaultDownloadsBase(AppPaths paths) async {
  Directory? dir;
  try {
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
      if (dir != null) dir = Directory('${dir.path}${Platform.pathSeparator}Downloads');
    } else {
      final d = await getDownloadsDirectory();
      if (d != null) dir = Directory('${d.path}${Platform.pathSeparator}Chithram');
    }
  } catch (_) {
    // Not on this platform.
  }
  return dir ?? Directory('${paths.support.path}${Platform.pathSeparator}downloads');
}

/// One kept download as stored.
class DownloadRecord {
  const DownloadRecord({
    required this.infoHash,
    required this.name,
    required this.folder,
    this.magnet,
    this.torrentFile,
    this.paused = false,
    this.onlyFiles,
    this.added,
  });

  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
        infoHash: '${j['infoHash']}',
        name: '${j['name'] ?? ''}',
        folder: '${j['folder']}',
        magnet: j['magnet'] as String?,
        torrentFile: j['torrentFile'] as String?,
        paused: j['paused'] == true,
        onlyFiles: j['onlyFiles'] is List ? [for (final i in j['onlyFiles'] as List) (i as num).toInt()] : null,
        added: DateTime.tryParse('${j['added'] ?? ''}'),
      );

  final String infoHash;
  final String name;

  /// Where its files are (the engine's output folder).
  final String folder;

  /// One of these says how to add it again.
  final String? magnet;
  final String? torrentFile;

  final bool paused;

  /// The chosen files (all when null).
  final List<int>? onlyFiles;
  final DateTime? added;

  DownloadRecord copyWith({String? name, bool? paused, List<int>? onlyFiles}) => DownloadRecord(
        infoHash: infoHash,
        name: name ?? this.name,
        folder: folder,
        magnet: magnet,
        torrentFile: torrentFile,
        paused: paused ?? this.paused,
        onlyFiles: onlyFiles ?? this.onlyFiles,
        added: added,
      );

  Map<String, dynamic> toJson() => {
        'infoHash': infoHash,
        'name': name,
        'folder': folder,
        if (magnet != null) 'magnet': magnet,
        if (torrentFile != null) 'torrentFile': torrentFile,
        if (paused) 'paused': true,
        if (onlyFiles != null) 'onlyFiles': onlyFiles,
        if (added != null) 'added': added!.toIso8601String(),
      };
}

/// A kept download while the app runs: what is stored, plus the engine's view.
class Download {
  Download(this.record, {this.info, this.stats, this.error});

  DownloadRecord record;

  /// Null until the engine knows the torrent (a magnet still resolving).
  TorrentInfo? info;
  TorrentStats? stats;
  String? error;

  String get infoHash => record.infoHash;
  String get name => (info?.name?.isNotEmpty ?? false) ? info!.name! : record.name;
  bool get paused => record.paused;
  bool get finished => stats?.finished ?? false;

  double get progress {
    final s = stats;
    if (s == null || s.totalBytes <= 0) return 0;
    return (s.progressBytes / s.totalBytes).clamp(0.0, 1.0);
  }
}

/// downloads.json in the support folder.
class DownloadStore {
  DownloadStore(this.file);

  final File file;

  Future<List<DownloadRecord>> load() async {
    try {
      if (!await file.exists()) return [];
      final j = jsonDecode(await file.readAsString());
      if (j is! List) return [];
      return [
        for (final e in j)
          if (e is Map<String, dynamic> && e['infoHash'] is String && e['folder'] is String) DownloadRecord.fromJson(e),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<DownloadRecord> records) =>
      writeFileAtomic(file, const JsonEncoder.withIndent(' ').convert([for (final r in records) r.toJson()]));

  /// Keeps a .torrent beside the list so the download can be added again.
  Future<String> saveTorrent(String infoHash, Uint8List bytes) async {
    final f = File('${file.parent.path}${Platform.pathSeparator}torrents${Platform.pathSeparator}$infoHash.torrent');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }
}

/// The `dn` (display name) of a magnet, or null.
String? magnetName(String magnet) {
  final q = magnet.indexOf('?');
  if (q < 0) return null;
  for (final kv in magnet.substring(q + 1).split('&')) {
    if (kv.startsWith('dn=')) {
      try {
        final v = Uri.decodeQueryComponent(kv.substring(3)).trim();
        if (v.isNotEmpty) return v;
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

/// The `name` in a .torrent's info dictionary (the first `4:name` string),
/// or null. Good enough to name the folder before the engine reads it.
String? torrentName(Uint8List bytes) {
  const key = [0x34, 0x3a, 0x6e, 0x61, 0x6d, 0x65]; // 4:name
  outer:
  for (var i = 0; i + key.length < bytes.length; i++) {
    for (var k = 0; k < key.length; k++) {
      if (bytes[i + k] != key[k]) continue outer;
    }
    var j = i + key.length, len = 0;
    while (j < bytes.length && bytes[j] >= 0x30 && bytes[j] <= 0x39) {
      len = len * 10 + bytes[j] - 0x30;
      j++;
    }
    if (j >= bytes.length || bytes[j] != 0x3a || len == 0 || j + 1 + len > bytes.length) return null;
    try {
      return utf8.decode(bytes.sublist(j + 1, j + 1 + len)).trim();
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// A folder name from a torrent's name: no path separators or characters
/// Windows refuses, no trailing dots or spaces, at most 120 characters.
String folderNameFor(String name, String infoHash) {
  var s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'[. ]+$'), '');
  if (s.length > 120) s = s.substring(0, 120).trim();
  if (s.isEmpty || s == '.' || s == '..') s = infoHash.substring(0, infoHash.length.clamp(0, 12));
  return s;
}

/// A speed limit for Settings: "Unlimited", "500 KiB/s", "2.5 MiB/s".
String limitLabel(int kib) {
  if (kib <= 0) return 'Unlimited';
  if (kib < 1024) return '$kib KiB/s';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib == mib.roundToDouble() ? 0 : 1)} MiB/s';
}

/// A typed speed limit in KiB/s: empty or 0 = unlimited; "2m" or "2 MiB" are
/// MiB/s. Null when it is not a number.
int? parseLimit(String text) {
  final t = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (t.isEmpty) return 0;
  final m = RegExp(r'^(\d+(?:\.\d+)?)(k|kb|kib|kib/s|kb/s|m|mb|mib|mib/s|mb/s)?$').firstMatch(t);
  if (m == null) return null;
  final n = double.parse(m.group(1)!);
  final mega = (m.group(2) ?? 'k').startsWith('m');
  return (mega ? n * 1024 : n).round().clamp(0, 4 * 1024 * 1024);
}

/// One line for a download row: state, speeds, peers, progress, time left.
String downloadLine(Download d) {
  if (d.error != null) return 'Error: ${d.error}';
  final s = d.stats;
  if (d.info == null) return d.paused ? 'Paused' : 'Finding peers...';
  if (s == null) return d.paused ? 'Paused' : 'Starting...';
  if (s.error != null) return 'Error: ${s.error}';
  final pct = '${(d.progress * 100).toStringAsFixed(d.progress >= 1 ? 0 : 1)}%';
  final size = '${formatBytes(s.progressBytes)} of ${formatBytes(s.totalBytes)}';
  if (d.paused || s.paused) return 'Paused · $pct · $size';
  final parts = <String>[];
  if (s.finished) {
    parts.add('Done · ${formatBytes(s.totalBytes)}');
    final up = s.uploadMibPerSec;
    if (up != null && up > 0.01) parts.add('Seeding ${up.toStringAsFixed(1)} MiB/s');
  } else {
    parts.add(pct);
    parts.add(size);
    final down = s.downloadMibPerSec;
    if (down != null) parts.add('↓ ${down.toStringAsFixed(1)} MiB/s');
    final up = s.uploadMibPerSec;
    if (up != null && up > 0.01) parts.add('↑ ${up.toStringAsFixed(1)} MiB/s');
    final eta = s.timeRemaining;
    if (eta != null && eta.isNotEmpty) parts.add('$eta left');
  }
  final peers = s.livePeers;
  if (peers != null) parts.add('$peers ${peers == 1 ? 'peer' : 'peers'}');
  if (s.uploadedBytes > 0 && s.totalBytes > 0) {
    parts.add('ratio ${(s.uploadedBytes / s.totalBytes).toStringAsFixed(2)}');
  }
  return parts.join(' · ');
}

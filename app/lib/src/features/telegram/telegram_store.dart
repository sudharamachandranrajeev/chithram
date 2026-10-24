import 'dart:convert';
import 'dart:io';

import '../../core/paths.dart';

/// A file Chithram asked TDLib to download, kept so old ones can be removed.
class TgDownload {
  const TgDownload({required this.fileId, required this.size, required this.touched});

  factory TgDownload.fromJson(Map<String, dynamic> j) => TgDownload(
        fileId: (j['id'] as num).toInt(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        touched: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0, isUtc: true),
      );

  final int fileId;
  final int size;

  /// When it was received or last played.
  final DateTime touched;

  Map<String, dynamic> toJson() => {'id': fileId, 'size': size, 'at': touched.millisecondsSinceEpoch};
}

/// Which downloads to delete: everything not touched for [maxAge], then the
/// oldest until the rest fit in [maxBytes]. [keep] (the file now playing) is
/// never chosen.
List<TgDownload> planCleanup(
  Iterable<TgDownload> items, {
  required DateTime now,
  Duration maxAge = const Duration(days: 7),
  int maxBytes = 4 * 1024 * 1024 * 1024,
  Set<int> keep = const {},
}) {
  final byAge = items.where((d) => !keep.contains(d.fileId)).toList()..sort((a, b) => a.touched.compareTo(b.touched));
  final drop = <TgDownload>[];
  final rest = <TgDownload>[];
  for (final d in byAge) {
    (now.difference(d.touched) > maxAge ? drop : rest).add(d);
  }
  var total = items.where((d) => !drop.contains(d)).fold<int>(0, (n, d) => n + d.size);
  for (final d in rest) {
    if (total <= maxBytes) break;
    drop.add(d);
    total -= d.size;
  }
  return drop;
}

/// `telegram_downloads.json`: the files Chithram downloaded and when. With no
/// file, it lives in memory only (tests).
class TelegramStore {
  TelegramStore(this._file);

  final File? _file;
  final _items = <int, TgDownload>{};
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final file = _file;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString());
      if (j is List) {
        for (final e in j.whereType<Map>()) {
          final d = TgDownload.fromJson(e.cast<String, dynamic>());
          _items[d.fileId] = d;
        }
      }
    } catch (_) {
      // Unreadable: start empty. The files stay in TDLib's own database.
    }
  }

  Future<List<TgDownload>> all() async {
    await _load();
    return _items.values.toList();
  }

  Future<void> touch(int fileId, int size, DateTime now) async {
    await _load();
    _items[fileId] = TgDownload(fileId: fileId, size: size, touched: now);
    await _save();
  }

  Future<void> remove(Iterable<int> ids) async {
    await _load();
    for (final id in ids) {
      _items.remove(id);
    }
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    _loaded = true;
    final file = _file;
    if (file != null && await file.exists()) await file.delete();
  }

  Future<void> _save() async {
    final file = _file;
    if (file != null) await writeFileAtomic(file, jsonEncode([for (final d in _items.values) d.toJson()]));
  }
}

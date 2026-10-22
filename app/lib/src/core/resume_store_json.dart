import 'dart:convert';
import 'dart:io';

import 'paths.dart';
import 'resume_store.dart';

/// [ResumeStore] in one `resume.json`, written atomically. The database
/// replaces it in 0.3.0 and imports the file.
class JsonResumeStore implements ResumeStore {
  JsonResumeStore._(this._file, this._entries);

  /// Most items kept; the least recently updated go first.
  static const maxEntries = 500;

  /// A position this close to the end counts as watched and is forgotten.
  static const watchedFraction = 0.95;

  /// Loads [file]; a missing or unreadable file starts empty.
  static Future<JsonResumeStore> load(File file) async {
    final entries = <String, _Entry>{};
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map<String, dynamic>) {
          for (final e in j.entries) {
            final v = e.value;
            if (v is Map<String, dynamic> && v['pos'] is int && v['at'] is int) {
              entries[e.key] = _Entry(v['pos'] as int, v['at'] as int);
            }
          }
        }
      }
    } catch (_) {
      // Corrupt file: start over rather than fail to launch.
    }
    return JsonResumeStore._(file, entries);
  }

  final File _file;
  final Map<String, _Entry> _entries;
  Future<void> _writing = Future.value();

  @override
  Future<Duration?> get(String itemId) async {
    final e = _entries[itemId];
    return e == null ? null : Duration(milliseconds: e.posMs);
  }

  @override
  Future<void> put(String itemId, Duration pos, Duration dur) {
    final watched = dur > Duration.zero && pos.inMilliseconds >= dur.inMilliseconds * watchedFraction;
    if (watched || pos <= Duration.zero) {
      if (_entries.remove(itemId) == null) return Future.value();
    } else {
      _entries[itemId] = _Entry(pos.inMilliseconds, DateTime.now().millisecondsSinceEpoch);
      if (_entries.length > maxEntries) {
        final oldest = _entries.entries.reduce((a, b) => a.value.atMs <= b.value.atMs ? a : b);
        _entries.remove(oldest.key);
      }
    }
    return _save();
  }

  @override
  Future<void> clear(String itemId) {
    if (_entries.remove(itemId) == null) return Future.value();
    return _save();
  }

  // Writes queue up so two puts never race on the temporary file.
  Future<void> _save() {
    final json = jsonEncode({
      for (final e in _entries.entries) e.key: {'pos': e.value.posMs, 'at': e.value.atMs},
    });
    return _writing = _writing.then((_) => writeFileAtomic(_file, json)).catchError((Object _) {});
  }
}

class _Entry {
  _Entry(this.posMs, this.atMs);
  final int posMs;
  final int atMs;
}

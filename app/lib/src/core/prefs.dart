import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

/// Small settings store: one `prefs.json`, written atomically. Values are
/// JSON scalars. Listeners fire after every change.
class Prefs extends ChangeNotifier {
  Prefs._(this._file, this._data);

  /// Loads [file]; a missing or unreadable file starts empty.
  static Future<Prefs> load(File file) async {
    var data = <String, Object?>{};
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map<String, dynamic>) data = j;
      }
    } catch (_) {
      // Corrupt file: start over rather than fail to launch.
    }
    return Prefs._(file, data);
  }

  /// Nothing is written. For tests and previews.
  factory Prefs.memory([Map<String, Object?> initial = const {}]) =>
      Prefs._(null, Map.of(initial));

  final File? _file;
  final Map<String, Object?> _data;

  String? getString(String key) => _data[key] as String?;
  bool getBool(String key, {bool fallback = false}) => _data[key] as bool? ?? fallback;
  int? getInt(String key) => _data[key] as int?;

  /// Stores [value] (null removes the key).
  Future<void> set(String key, Object? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    notifyListeners();
    final file = _file;
    if (file != null) await writeFileAtomic(file, jsonEncode(_data));
  }
}

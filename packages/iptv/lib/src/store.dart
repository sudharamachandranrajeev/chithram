import 'dart:convert';
import 'dart:io';

import 'health.dart';
import 'sources.dart';

/// Persistence seam.
///
/// Chosen over bundling sqlite3/drift here: the package stays pure Dart (no
/// native lib, no codegen, `dart test` works anywhere) and the app, which
/// already uses drift per docs/decisions.md, implements this interface on top
/// of its database. [InMemoryIptvStore] backs tests; [JsonFileIptvStore] is a
/// dependency-free on-disk implementation for CLIs and small installs.
abstract class IptvStore {
  Future<List<Source>> sources();
  Future<void> saveSource(Source s);
  Future<void> deleteSource(String id);

  Future<List<StoredChannel>> channels(String sourceId);

  /// Replaces all channels of [sourceId] (merge decisions are made upstream).
  Future<void> replaceChannels(String sourceId, List<StoredChannel> channels);

  Future<Map<String, ProbeResult>> probes();
  Future<void> saveProbes(Map<String, ProbeResult> probes);
}

class InMemoryIptvStore implements IptvStore {
  final _sources = <String, Source>{};
  final _channels = <String, List<StoredChannel>>{};
  var _probes = <String, ProbeResult>{};

  @override
  Future<List<Source>> sources() async => _sources.values.toList();
  @override
  Future<void> saveSource(Source s) async => _sources[s.id] = s;
  @override
  Future<void> deleteSource(String id) async {
    _sources.remove(id);
    _channels.remove(id);
  }

  @override
  Future<List<StoredChannel>> channels(String sourceId) async =>
      List.of(_channels[sourceId] ?? const []);
  @override
  Future<void> replaceChannels(String sourceId, List<StoredChannel> c) async =>
      _channels[sourceId] = List.of(c);
  @override
  Future<Map<String, ProbeResult>> probes() async => Map.of(_probes);
  @override
  Future<void> saveProbes(Map<String, ProbeResult> p) async =>
      _probes = Map.of(p);
}

/// One JSON file per collection under [dir]; writes are atomic (tmp + rename).
/// Xtream passwords are NOT persisted here (see [Source.toJson]).
class JsonFileIptvStore implements IptvStore {
  JsonFileIptvStore(this.dir) {
    dir.createSync(recursive: true);
  }
  final Directory dir;

  File _f(String name) => File('${dir.path}/$name.json');

  Future<Object?> _read(String name) async {
    final f = _f(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } on FormatException {
      return null; // corrupt file: start empty rather than crash
    }
  }

  Future<void> _write(String name, Object data) async {
    final tmp = File('${_f(name).path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(_f(name).path);
  }

  @override
  Future<List<Source>> sources() async {
    final j = await _read('sources');
    return [
      if (j is List)
        for (final e in j)
          if (e is Map) Source.fromJson(e.cast<String, dynamic>()),
    ];
  }

  @override
  Future<void> saveSource(Source s) async {
    final all = await sources();
    final i = all.indexWhere((x) => x.id == s.id);
    if (i >= 0) {
      all[i] = s;
    } else {
      all.add(s);
    }
    await _write('sources', [for (final x in all) x.toJson()]);
  }

  @override
  Future<void> deleteSource(String id) async {
    final all = await sources()
      ..removeWhere((x) => x.id == id);
    await _write('sources', [for (final x in all) x.toJson()]);
    final f = _f('channels_${_safe(id)}');
    if (await f.exists()) await f.delete();
  }

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  @override
  Future<List<StoredChannel>> channels(String sourceId) async {
    final j = await _read('channels_${_safe(sourceId)}');
    return [
      if (j is List)
        for (final e in j)
          if (e is Map) StoredChannel.fromJson(e.cast<String, dynamic>()),
    ];
  }

  @override
  Future<void> replaceChannels(String sourceId, List<StoredChannel> c) =>
      _write('channels_${_safe(sourceId)}', [for (final x in c) x.toJson()]);

  @override
  Future<Map<String, ProbeResult>> probes() async {
    final j = await _read('probes');
    return {
      if (j is Map)
        for (final e in j.entries)
          if (e.value is Map)
            '${e.key}': ProbeResult.fromJson((e.value as Map).cast<String, dynamic>()),
    };
  }

  @override
  Future<void> saveProbes(Map<String, ProbeResult> p) =>
      _write('probes', {for (final e in p.entries) e.key: e.value.toJson()});
}

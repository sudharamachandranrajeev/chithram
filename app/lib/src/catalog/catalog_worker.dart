import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:tmdb/tmdb.dart';

/// One lazy, long-lived isolate owns HTTP, decompression, JSON and the limiter.
/// Creating this object has no IO and is safe before the first frame.
class CatalogWorker {
  CatalogWorker({this.base});
  final Uri? base;
  Future<SendPort>? _starting;
  Isolate? _isolate;
  bool _closed = false;
  final Completer<void> _closedSignal = Completer<void>();
  Future<SendPort> _start() => _starting ??= () async {
    if (_closed) throw const TmdbException('Metadata service is closed.');
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(_workerMain, [
      ready.sendPort,
      base?.toString(),
    ]);
    final port = await ready.first as SendPort;
    ready.close();
    return port;
  }();

  Future<dynamic> _call(Map<String, Object?> message) async {
    if (_closed) throw const TmdbException('Metadata service is closed.');
    final port = await _start();
    if (_closed) throw const TmdbException('Metadata service is closed.');
    final reply = ReceivePort();
    port.send({...message, 'reply': reply.sendPort});
    try {
      final result = await Future.any<dynamic>([
        reply.first,
        _closedSignal.future.then(
          (_) => throw const TmdbException('Metadata service is closed.'),
        ),
      ]).timeout(const Duration(seconds: 90)) as Map;
      if (result['error'] case final TmdbException error) throw error;
      return result['value'];
    } on TimeoutException {
      throw const TmdbException('Metadata request timed out.');
    } finally {
      reply.close();
    }
  }

  Future<WorkerResult> fetch({
    required String key,
    required String path,
    Map<String, String> query = const {},
    String parser = 'raw',
    MediaKind? kind,
    bool list = false,
    String? etag,
    String? lastModified,
  }) async => await _call({
    'op': 'fetch',
    'key': key,
    'path': path,
    'query': query,
    'parser': parser,
    'kind': kind,
    'list': list,
    'etag': etag,
    'lastModified': lastModified,
  }) as WorkerResult;

  Future<dynamic> decode(Uint8List body, String parser, MediaKind? kind) =>
      _call({'op': 'decode', 'body': body, 'parser': parser, 'kind': kind});

  Future<void> reset() async {
    if (_starting != null) await _call({'op': 'reset'});
  }

  Future<void> close() async {
    _closed = true;
    if (!_closedSignal.isCompleted) _closedSignal.complete();
    if (_starting != null) {
      try {
        await _starting;
      } catch (_) {}
    }
    _isolate?.kill(priority: Isolate.immediate);
  }
}

class WorkerResult {
  const WorkerResult(this.value, this.body, this.status, this.headers);
  final dynamic value;
  final Uint8List body;
  final int status;
  final Map<String, String> headers;
}

void _workerMain(List<dynamic> arguments) {
  final requests = ReceivePort();
  (arguments[0] as SendPort).send(requests.sendPort);
  final base = arguments[1] == null ? null : Uri.parse(arguments[1] as String);
  final limiter = RequestLimiter();
  TmdbClient? client;
  requests.listen((dynamic input) async {
    final m = input as Map;
    final reply = m['reply'] as SendPort;
    try {
      if (m['op'] == 'reset') {
        client?.close();
        client = null;
        reply.send({'value': null});
        return;
      }
      final parser = m['parser'] as String;
      final kind = m['kind'] as MediaKind?;
      if (m['op'] == 'decode') {
        final json = decodeBody(m['body'] as Uint8List);
        reply.send({'value': _parse(json, parser, kind)});
        return;
      }
      final key = m['key'] as String;
      if (client?.key != key) {
        client?.close();
        client = TmdbClient(key: key, base: base, limiter: limiter);
      }
      final response = await client!.get(
        m['path'] as String,
        query: (m['query'] as Map).cast<String, String>(),
        list: m['list'] == true,
        etag: m['etag'] as String?,
        lastModified: m['lastModified'] as String?,
      );
      final json = response.body;
      reply.send({
        'value': WorkerResult(
          json == null ? null : _parse(json, parser, kind),
          json == null ? Uint8List(0) : encodeBody(json),
          response.status,
          response.headers,
        ),
      });
    } on TmdbException catch (e) {
      reply.send({'error': e});
    } catch (_) {
      reply.send({
        'error': const TmdbException(
          'Could not read metadata. Try refreshing.',
        ),
      });
    }
  });
}

// Kept in the worker even for cache hits: large bodies never parse on the UI.
Uint8List encodeBody(Map<String, dynamic> json) =>
    Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(json))));
Map<String, dynamic> decodeBody(Uint8List body) =>
    (jsonDecode(utf8.decode(gzip.decode(body))) as Map).cast<String, dynamic>();
dynamic _parse(Map<String, dynamic> json, String parser, MediaKind? kind) =>
    switch (parser) {
      'details' => parseDetails(json, kind!),
      'season' => parseSeason(json),
      'tiles' => parseTiles(json, kind),
      'genres' => parseGenres(json),
      _ => json,
    };

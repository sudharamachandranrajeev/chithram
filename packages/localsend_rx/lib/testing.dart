/// A minimal LocalSend sender for tests and the loopback tool. Not exported by
/// `localsend_rx.dart`; the app never links it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'src/identity.dart';
import 'src/protocol.dart';

class LsTestResponse {
  const LsTestResponse(this.status, this.body);

  final int status;
  final String body;

  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

/// Talks to a receiver over HTTPS, accepting only [fingerprint] (any
/// certificate when it is null).
class LsTestSender {
  LsTestSender({
    required this.host,
    required this.port,
    this.fingerprint,
    this.alias = 'Test phone',
    this.model = 'Test model',
    this.senderFingerprint = 'TESTSENDERFINGERPRINT',
  });

  final String host;
  final int port;
  final String? fingerprint;
  final String alias;
  final String model;
  final String senderFingerprint;

  Map<String, Object?> get _me => {
        'alias': alias,
        'version': protocolVersion,
        'deviceModel': model,
        'deviceType': 'mobile',
        'fingerprint': senderFingerprint,
        'port': 53317,
        'protocol': 'https',
        'download': false,
      };

  Future<LsTestResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    List<int>? body,
    String contentType = 'application/json',
    bool chunked = false,
  }) async {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (cert, h, p) =>
          fingerprint == null || LsIdentity.fingerprintOf(cert.der) == fingerprint!.toUpperCase();
    try {
      final req = await client.openUrl(
        method,
        Uri(scheme: 'https', host: host, port: port, path: '$apiBase$path', queryParameters: query),
      );
      if (body != null) {
        req.headers.contentType = ContentType.parse(contentType);
        if (!chunked) req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      return LsTestResponse(res.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Future<LsTestResponse> info() => _send('GET', '/info');

  Future<LsTestResponse> register() => _send('POST', '/register', body: utf8.encode(jsonEncode(_me)));

  /// One entry per file: `{id, fileName, size, fileType, preview?, sha256?}`.
  Future<LsTestResponse> prepare(List<Map<String, Object?>> files, {String? pin, List<int>? rawBody}) {
    return _send(
      'POST',
      '/prepare-upload',
      query: pin == null ? null : {'pin': pin},
      body: rawBody ?? utf8.encode(jsonEncode({'info': _me, 'files': {for (final f in files) f['id'] as String: f}})),
    );
  }

  Future<LsTestResponse> upload(String sessionId, String fileId, String token, List<int> bytes) => _send(
        'POST',
        '/upload',
        query: {'sessionId': sessionId, 'fileId': fileId, 'token': token},
        body: bytes,
        contentType: 'application/octet-stream',
      );

  Future<LsTestResponse> cancel(String sessionId) => _send('POST', '/cancel', query: {'sessionId': sessionId});

  /// The text-message shape LocalSend phones use: one `text/plain` file whose
  /// text is in `preview`.
  static Map<String, Object?> textFile(String text, {String id = 'msg1'}) => {
        'id': id,
        'fileName': '$id.txt',
        'size': utf8.encode(text).length,
        'fileType': 'text/plain',
        'preview': text,
      };

  static Map<String, Object?> binaryFile(String id, String name, Uint8List bytes, {String type = 'application/octet-stream'}) => {
        'id': id,
        'fileName': name,
        'size': bytes.length,
        'fileType': type,
        'sha256': sha256.convert(bytes).toString(),
      };

  /// Sends [text] and returns the status of `prepare-upload`.
  Future<int> sendText(String text) async => (await prepare([textFile(text)])).status;

  /// Sends one file end to end; returns the upload status (or the prepare
  /// status when that failed).
  Future<int> sendFile(String name, Uint8List bytes, {String type = 'application/octet-stream'}) async {
    final prep = await prepare([binaryFile('f1', name, bytes, type: type)]);
    if (prep.status != 200) return prep.status;
    final j = prep.json! as Map<String, dynamic>;
    final token = (j['files'] as Map)['f1'] as String;
    return (await upload(j['sessionId'] as String, 'f1', token, bytes)).status;
  }
}

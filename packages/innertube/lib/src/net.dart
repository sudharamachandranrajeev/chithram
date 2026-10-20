import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'errors.dart';

const browserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

/// Thin HTTP helper over an injectable [http.Client] (tests pass a fake).
class Net {
  Net([http.Client? client]) : client = client ?? http.Client();
  final http.Client client;

  Map<String, String> _headers(Map<String, String>? extra) => {
        'User-Agent': browserAgent,
        'Accept-Language': 'en-US,en;q=0.8',
        ...?extra,
      };

  Future<String> getText(Uri uri, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 20)}) async {
    final response = await client.get(uri, headers: _headers(headers)).timeout(timeout);
    _check(response);
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<Object?> postJson(Uri uri, Object body,
      {Map<String, String>? headers, Duration timeout = const Duration(seconds: 20)}) async {
    final response = await client
        .post(uri,
            headers: _headers({'Content-Type': 'application/json', 'Accept': 'application/json', ...?headers}),
            body: jsonEncode(body))
        .timeout(timeout);
    _check(response);
    return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  void _check(http.Response response) {
    if (response.statusCode >= 400) {
      throw HttpStatusException(response.statusCode, response.request?.url.host ?? 'the site');
    }
  }
}

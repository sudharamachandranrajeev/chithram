import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:http/http.dart' as http;

enum AuthMode { v3, bearer }

AuthMode authMode(String key) {
  if (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(key)) return AuthMode.v3;
  if (key.startsWith('eyJ') && !key.contains(RegExp(r'\s'))) {
    return AuthMode.bearer;
  }
  throw const TmdbException('Enter a valid API key or read access token.');
}

class TmdbException implements Exception {
  const TmdbException(this.message, {this.status, this.retryAfter});
  final String message;
  final int? status;
  final Duration? retryAfter;
  @override
  String toString() => message;
}

/// Shared by every operation in the worker. Starts are spaced at 8/s and at
/// most four requests can be active. Clock and delay are injectable for tests.
class RequestLimiter {
  RequestLimiter({
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : now = now ?? DateTime.now,
       sleep = sleep ?? Future<void>.delayed;
  final DateTime Function() now;
  final Future<void> Function(Duration) sleep;
  Future<void> _starts = Future.value();
  DateTime? _next;
  int _active = 0;
  final List<Completer<void>> _slots = [];

  Future<T> run<T>(Future<T> Function() operation) async {
    if (_active >= 4) {
      final slot = Completer<void>();
      _slots.add(slot);
      await slot.future;
    } else {
      _active++;
    }
    try {
      final start = _starts.then((_) async {
        final wait = _next?.difference(now()) ?? Duration.zero;
        if (wait > Duration.zero) await sleep(wait);
        _next = now().add(const Duration(milliseconds: 125));
      });
      _starts = start;
      await start;
      return await operation();
    } finally {
      if (_slots.isNotEmpty) {
        _slots.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }
}

class TmdbResponse {
  const TmdbResponse(this.status, this.body, this.headers);
  final int status;
  final Map<String, dynamic>? body;
  final Map<String, String> headers;
}

class TmdbClient {
  TmdbClient({
    required this.key,
    http.Client? client,
    Uri? base,
    RequestLimiter? limiter,
    DateTime Function()? now,
    double Function()? random,
  }) : client = client ?? http.Client(),
       base = base ?? Uri.parse('https://api.themoviedb.org/3/'),
       limiter = limiter ?? RequestLimiter(),
       now = now ?? DateTime.now,
       random = random ?? Random().nextDouble {
    authMode(key);
  }
  final String key;
  final http.Client client;
  final Uri base;
  final RequestLimiter limiter;
  final DateTime Function() now;
  final double Function() random;
  DateTime? _blockedUntil;
  int _failures = 0;

  /// Stable and deliberately independent of credentials.
  static String cacheKey(String path, Map<String, String> query) {
    final keys = query.keys.where((k) => k != 'api_key').toList()..sort();
    return 'tmdb:/$path?${Uri(queryParameters: {for (final k in keys) k: query[k]!}).query}';
  }

  Future<TmdbResponse> get(
    String path, {
    Map<String, String> query = const {},
    String? etag,
    String? lastModified,
    bool list = false,
  }) async {
    if (_blockedUntil case final until? when until.isAfter(now())) {
      throw TmdbException(
        'Metadata service is temporarily unavailable.',
        retryAfter: until.difference(now()),
      );
    }
    return limiter.run(() async {
      if (_blockedUntil case final until? when until.isAfter(now())) {
        throw TmdbException(
          'Metadata service is temporarily unavailable.',
          retryAfter: until.difference(now()),
        );
      }
      final params = {...query, if (list) 'include_adult': 'false'};
      final headers = <String, String>{
        'accept': 'application/json',
        'If-None-Match': ?etag,
        'If-Modified-Since': ?lastModified,
      };
      if (authMode(key) == AuthMode.v3) {
        params['api_key'] = key;
      } else {
        headers['Authorization'] = 'Bearer $key';
      }
      try {
        final request =
            http.Request(
                'GET',
                base.resolve(path).replace(queryParameters: params),
              )
              ..headers.addAll(headers)
              ..followRedirects = false;
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 20));
        // Bound streamed input before collecting or decoding it.
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 20),
        )) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const TmdbException('Metadata response is too large.');
          }
          bytes.addAll(chunk);
        }
        final status = response.statusCode;
        if (status == 401 || status == 403) {
          throw TmdbException('The metadata key was rejected.', status: status);
        }
        if (status == 429 || status >= 500) {
          final raw = response.headers['retry-after'];
          final seconds = int.tryParse(raw ?? '');
          DateTime? date;
          try {
            if (raw != null) date = HttpDate.parse(raw);
          } catch (_) {}
          // HTTP dates use RFC 1123 rather than ISO; parsed below when needed.
          final retry = seconds != null
              ? Duration(seconds: seconds)
              : date?.difference(now());
          _failures++;
          final backoff = Duration(
            milliseconds: min(
              21600000,
              60000 * pow(2, min(_failures - 1, 16)) * (0.8 + random() * 0.4),
            ).round(),
          );
          final delay = retry != null && retry > backoff ? retry : backoff;
          _blockedUntil = now().add(delay);
          throw TmdbException(
            'Metadata service is temporarily unavailable.',
            status: status,
            retryAfter: delay,
          );
        }
        if (status != 200 && status != 304) {
          throw TmdbException('Metadata request failed.', status: status);
        }
        _failures = 0;
        return TmdbResponse(
          status,
          status == 304
              ? null
              : (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>(),
          response.headers,
        );
      } on TmdbException {
        rethrow;
      } catch (_) {
        _failures++;
        final backoff = Duration(
          milliseconds: min(
            21600000,
            60000 * pow(2, min(_failures - 1, 16)) * (0.8 + random() * 0.4),
          ).round(),
        );
        _blockedUntil = now().add(backoff);
        throw TmdbException(
          'Could not load metadata. Check your connection.',
          retryAfter: backoff,
        );
      }
    });
  }

  void close() => client.close();
}

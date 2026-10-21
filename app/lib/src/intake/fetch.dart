import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Fetches up to [maxBytes] of [uri] (http or https only). Null when the
/// request fails, times out, or answers with an error status. A body longer
/// than [maxBytes] is cut when [truncate] is set and refused otherwise.
typedef IntakeFetch = Future<Uint8List?> Function(
  Uri uri, {
  required int maxBytes,
  required Duration timeout,
  bool truncate,
});

/// Replaced by tests; the app uses [fetchLimited].
IntakeFetch intakeFetch = fetchLimited;

Future<Uint8List?> fetchLimited(
  Uri uri, {
  required int maxBytes,
  required Duration timeout,
  bool truncate = false,
}) async {
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = 'Chithram';
  try {
    return await () async {
      final req = await client.getUrl(uri);
      req.followRedirects = true;
      req.maxRedirects = 3;
      final res = await req.close();
      if (res.statusCode != 200) return null;
      if (!truncate && res.contentLength > maxBytes) return null;
      final out = BytesBuilder(copy: false);
      await for (final chunk in res) {
        out.add(chunk);
        if (out.length > maxBytes) {
          if (!truncate) return null;
          return Uint8List.sublistView(out.takeBytes(), 0, maxBytes);
        }
      }
      return out.takeBytes();
    }()
        .timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

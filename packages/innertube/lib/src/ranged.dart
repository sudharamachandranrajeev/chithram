import 'package:http/http.dart' as http;

import 'models.dart';

/// Headers for a googlevideo link. ALWAYS send a Range header: a GET with no
/// Range is throttled to about real time (Paattu measured 7.5 MB in 224 s
/// against 5-6 MB/s ranged). ExoPlayer sends no Range on its first request,
/// so give it `bytes=0-` (it replaces the header on seeks). Do NOT pass this
/// to mpv: ffmpeg's http protocol sends no Range of its own when a user header
/// has one, so seeks would re-request from byte 0 (the media_kit engine drops it).
Map<String, String> rangedHeaders(String userAgent, {int from = 0, int? to}) => {
      'User-Agent': userAgent,
      'Range': 'bytes=$from-${to ?? ''}',
    };

class RangeProbe {
  const RangeProbe(this.status, this.bytes);
  final int status;
  final int bytes;

  /// 206 Partial Content: the server honours ranges (full speed).
  bool get ok => status == 206;
}

/// Asks [format] for its first [length] bytes.
Future<RangeProbe> probeRange(http.Client client, StreamFormat format, String userAgent,
    {int length = 1024, Duration timeout = const Duration(seconds: 10)}) =>
    probeUrl(client, format.url, userAgent, length: length, timeout: timeout);

Future<RangeProbe> probeUrl(http.Client client, Uri url, String userAgent,
    {int length = 1024, Duration timeout = const Duration(seconds: 10)}) async {
  final request = http.Request('GET', url)..headers.addAll(rangedHeaders(userAgent, to: length - 1));
  final response = await client.send(request).timeout(timeout);
  var bytes = 0;
  await for (final chunk in response.stream.timeout(timeout)) {
    bytes += chunk.length;
    if (bytes >= length) break;
  }
  return RangeProbe(response.statusCode, bytes);
}

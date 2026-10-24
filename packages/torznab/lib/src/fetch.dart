import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One HTTP answer: status and the (size-capped) body.
class TorznabResponse {
  const TorznabResponse(this.status, this.body, {this.retryAfter});
  final int status;
  final Uint8List body;

  /// From a 429's `Retry-After`, when it was given in seconds.
  final Duration? retryAfter;
}

/// GETs [url]. Never put the URL (it holds the API key) into an error message.
typedef TorznabFetch = Future<TorznabResponse> Function(Uri url);

/// A failure with a message that is safe to show and log: it never contains
/// the request URL or the API key.
class TorznabException implements Exception {
  TorznabException(this.message, {this.code, this.retryAfter});
  final String message;
  final String? code;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

const maxResponseBytes = 5 * 1024 * 1024;
const requestTimeout = Duration(seconds: 15);

String decodeBody(Uint8List b) => utf8.decode(b, allowMalformed: true);

/// True for hosts on the user's own network: loopback, RFC 1918, link-local,
/// unique-local, `localhost`, `.local`, `.lan`, `.home.arpa`, and bare names
/// (no dot) such as a Docker service name.
bool isPrivateHost(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  if (h.isEmpty) return false;
  final ip = InternetAddress.tryParse(h);
  if (ip != null) {
    if (ip.isLoopback || ip.isLinkLocal) return true;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
    }
    return (b[0] & 0xfe) == 0xfc; // fc00::/7
  }
  return h == 'localhost' || !h.contains('.') || h.endsWith('.local') || h.endsWith('.lan') || h.endsWith('.home.arpa');
}

/// Null when [u] may be used as an endpoint; else the reason. HTTPS, or HTTP
/// to a host on the user's own network.
String? endpointProblem(Uri u) {
  if (!u.hasAuthority || u.host.isEmpty) return 'Enter a full address, like http://192.168.1.5:9117/api';
  if (u.userInfo.isNotEmpty) return 'Put the API key in its own field, not in the address';
  if (u.scheme == 'https') return null;
  if (u.scheme == 'http') return isPrivateHost(u.host) ? null : 'Use https:// for an indexer outside your network';
  return 'Use http:// or https://';
}

/// Plain `dart:io` GET: timeout, 5 MiB cap, up to 3 redirects each re-checked
/// with [endpointProblem]. Errors are rewritten without the URL.
Future<TorznabResponse> fetchDirect(Uri url, {HttpClient? client}) async {
  final c = client ?? HttpClient();
  c.connectionTimeout = requestTimeout;
  try {
    return await _follow(c, url).timeout(requestTimeout);
  } on TimeoutException {
    throw TorznabException('The indexer did not answer in ${requestTimeout.inSeconds} s');
  } on TorznabException {
    rethrow;
  } on HandshakeException {
    throw TorznabException('The indexer\'s certificate was not accepted');
  } on SocketException {
    throw TorznabException('Could not connect to the indexer');
  } on HttpException {
    throw TorznabException('The indexer sent a bad answer');
  } finally {
    if (client == null) c.close(force: true);
  }
}

Future<TorznabResponse> _follow(HttpClient c, Uri url) async {
  for (var hop = 0; hop < 4; hop++) {
    final problem = endpointProblem(url);
    if (problem != null) throw TorznabException(problem);
    final req = await c.getUrl(url);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, 'application/rss+xml, application/xml, text/xml');
    final res = await req.close();
    if (const {301, 302, 303, 307, 308}.contains(res.statusCode)) {
      final loc = res.headers.value(HttpHeaders.locationHeader);
      await res.drain<void>();
      if (loc == null) throw TorznabException('The indexer sent a redirect with no target');
      url = url.resolve(loc);
      continue;
    }
    final declared = res.contentLength;
    if (declared > maxResponseBytes) {
      await res.drain<void>();
      throw TorznabException('The answer is larger than 5 MiB');
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in res) {
      out.add(chunk);
      if (out.length > maxResponseBytes) throw TorznabException('The answer is larger than 5 MiB');
    }
    final ra = int.tryParse(res.headers.value(HttpHeaders.retryAfterHeader) ?? '');
    return TorznabResponse(res.statusCode, out.takeBytes(), retryAfter: ra == null ? null : Duration(seconds: ra));
  }
  throw TorznabException('Too many redirects');
}

import 'dart:async';
import 'dart:convert';

import 'package:iptv/src/http.dart';

typedef Handler = IptvResponse Function(Uri uri, Map<String, String> headers);

/// In-memory IptvHttp. Hosts are always *.example.test: no real network.
class FakeHttp implements IptvHttp {
  FakeHttp(this.routes);
  final Map<String, Handler> routes; // matched on uri.toString() prefix
  final requests = <Uri>[];
  final headersSeen = <Map<String, String>>[];
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<IptvResponse> open(Uri uri,
      {Map<String, String> headers = const {},
      Duration timeout = const Duration(seconds: 15)}) async {
    requests.add(uri);
    headersSeen.add(headers);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      for (final e in routes.entries) {
        if (uri.toString().startsWith(e.key)) return e.value(uri, headers);
      }
      return reply(404, '');
    } finally {
      inFlight--;
    }
  }
}

IptvResponse reply(int status, Object body,
    {Map<String, String> headers = const {}}) {
  final bytes = body is List<int> ? body : utf8.encode('$body');
  return IptvResponse(
    status: status,
    headers: headers,
    body: Stream.value(bytes),
    ttfb: const Duration(milliseconds: 5),
  );
}

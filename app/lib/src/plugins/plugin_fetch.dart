import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'backoff.dart';
import 'plugin_models.dart';

/// Answer to a GET. [notModified] (304) has no body.
class FetchResult {
  const FetchResult(this.status, this.body, {this.etag, this.retryAfter});

  final int status;
  final Uint8List body;
  final String? etag;
  final Duration? retryAfter;

  bool get ok => status == 200;
  bool get notModified => status == 304;
}

/// Downloads plugin files and repo manifests. Replaced by tests.
abstract interface class PluginFetcher {
  /// GET [url] (conditional on [etag] when given). A body over [maxBytes] is
  /// an error, not a truncation. Throws [PluginInstallError] (fetch, tooLarge)
  /// when the request cannot be completed; other statuses come back in the result.
  Future<FetchResult> get(Uri url, {required int maxBytes, String? etag});
}

/// HTTPS only (HTTP when [allowInsecure], which the end-to-end builds set for
/// their local fixture server), at most 3 redirects, each one re-checked, no
/// credentials in the URL, 15 s per request.
class HttpPluginFetcher implements PluginFetcher {
  HttpPluginFetcher({this.allowInsecure = false, this.timeout = const Duration(seconds: 15), HttpClient Function()? client})
      : _client = client ?? HttpClient.new;

  final bool allowInsecure;
  final Duration timeout;
  final HttpClient Function() _client;

  bool _schemeOk(Uri u) => u.scheme == 'https' || (allowInsecure && u.scheme == 'http');

  @override
  Future<FetchResult> get(Uri url, {required int maxBytes, String? etag}) async {
    final client = _client()
      ..connectionTimeout = timeout
      ..userAgent = 'Chithram';
    try {
      return await _get(client, url, maxBytes, etag).timeout(timeout * 2);
    } on PluginInstallError {
      rethrow;
    } on TimeoutException {
      throw PluginInstallError(InstallErrorKind.fetch, 'Timed out reaching ${url.host}');
    } on SocketException catch (e) {
      throw PluginInstallError(InstallErrorKind.fetch, 'Could not reach ${url.host}: ${e.message}');
    } on HttpException catch (e) {
      throw PluginInstallError(InstallErrorKind.fetch, 'Bad answer from ${url.host}: ${e.message}');
    } on TlsException catch (e) {
      throw PluginInstallError(InstallErrorKind.fetch, 'Secure connection to ${url.host} failed: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<FetchResult> _get(HttpClient client, Uri url, int maxBytes, String? etag) async {
    var current = url;
    for (var hop = 0; hop <= 3; hop++) {
      if (!_schemeOk(current)) {
        throw PluginInstallError(InstallErrorKind.fetch, 'Only https addresses are accepted (${current.scheme}://${current.host})');
      }
      if (current.userInfo.isNotEmpty || current.host.isEmpty) {
        throw PluginInstallError(InstallErrorKind.fetch, 'That address is not valid');
      }
      final req = await client.getUrl(current);
      req.followRedirects = false;
      if (etag != null && hop == 0) req.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      final res = await req.close();
      if (const {301, 302, 303, 307, 308}.contains(res.statusCode)) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (loc == null) throw PluginInstallError(InstallErrorKind.fetch, 'Redirect without a location');
        current = current.resolve(loc);
        continue;
      }
      final retry = parseRetryAfter(res.headers.value(HttpHeaders.retryAfterHeader));
      final tag = res.headers.value(HttpHeaders.etagHeader);
      if (res.statusCode == 304) {
        await res.drain<void>();
        return FetchResult(304, Uint8List(0), etag: etag, retryAfter: retry);
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        return FetchResult(res.statusCode, Uint8List(0), retryAfter: retry);
      }
      if (res.contentLength > maxBytes) {
        await res.drain<void>().catchError((_) {});
        throw PluginInstallError(InstallErrorKind.tooLarge, '${current.pathSegments.lastOrNull ?? 'file'} is larger than $maxBytes bytes');
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in res) {
        out.add(chunk);
        if (out.length > maxBytes) {
          throw PluginInstallError(InstallErrorKind.tooLarge, '${current.pathSegments.lastOrNull ?? 'file'} is larger than $maxBytes bytes');
        }
      }
      return FetchResult(200, out.takeBytes(), etag: tag, retryAfter: retry);
    }
    throw PluginInstallError(InstallErrorKind.fetch, 'Too many redirects');
  }
}

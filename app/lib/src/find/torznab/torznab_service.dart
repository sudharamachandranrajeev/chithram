import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:nova_host/nova_host.dart' show BrokerDenied, BrokerPolicy, HostAllowlist, HttpBroker, Socks5Config;
import 'package:torznab/torznab.dart';

import '../../core/secrets.dart';
import '../../data/database.dart';
import '../../features/torrents/torrent_logic.dart';

/// One endpoint the user added. The API key is in SecretStore under
/// [secretKey].
class TorznabEndpoint {
  const TorznabEndpoint({
    required this.id,
    required this.name,
    required this.url,
    required this.enabled,
    this.caps,
    this.capsAt,
  });

  final String id, name;
  final Uri url;
  final bool enabled;
  final TorznabCaps? caps;
  final DateTime? capsAt;

  String get secretKey => 'torznab.key.$id';

  TorznabEndpoint copyWith({bool? enabled, TorznabCaps? caps, DateTime? capsAt}) => TorznabEndpoint(
    id: id,
    name: name,
    url: url,
    enabled: enabled ?? this.enabled,
    caps: caps ?? this.caps,
    capsAt: capsAt ?? this.capsAt,
  );
}

/// What the last calls to an endpoint did (in memory; shown in Settings).
class EndpointHealth {
  const EndpointHealth({this.lastOk, this.lastError, this.failures = 0, this.retryAt});
  final DateTime? lastOk;
  final String? lastError;
  final int failures;

  /// Calls before this time are not sent (backoff).
  final DateTime? retryAt;
}

/// The user's Torznab endpoints: add (with a capabilities check), test,
/// enable, remove, and every call to them.
///
/// Etiquette (every call): at most one request per [minGap] per endpoint,
/// exponential backoff with +-20% jitter capped at 6 h after a failure, a 429's
/// Retry-After honoured. Torznab answers carry no validators worth keeping, so
/// there are no conditional requests; callers cache (the popular lists are kept
/// for hours).
///
/// Traffic: hosts on the user's network are reached directly; a public host
/// goes through the HTTP broker and the SOCKS5 proxy when the torrent network
/// choice is SOCKS5, else directly.
class TorznabService extends ChangeNotifier {
  TorznabService({
    required this.db,
    required this.secrets,
    required this.network,
    TorznabFetch? fetch,
    DateTime Function()? clock,
    math.Random? random,
    this.minGap = const Duration(seconds: 2),
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? math.Random(),
       _fetchOverride = fetch;

  final AppDatabase db;
  final SecretStore secrets;

  /// The torrent network choice, read at each call.
  final NetworkChoice Function() network;
  final DateTime Function() _clock;
  final math.Random _random;
  final TorznabFetch? _fetchOverride;
  final Duration minGap;

  static const maxBackoff = Duration(hours: 6);
  static const _baseBackoff = Duration(seconds: 30);

  var _endpoints = const <TorznabEndpoint>[];
  final _health = <String, EndpointHealth>{};
  final _lastCall = <String, DateTime>{};
  Future<void>? _loading;

  List<TorznabEndpoint> get endpoints => _endpoints;
  List<TorznabEndpoint> get enabled => [
    for (final e in _endpoints)
      if (e.enabled) e,
  ];
  EndpointHealth health(String id) => _health[id] ?? const EndpointHealth();

  /// Reads the endpoints from the database (once).
  Future<void> load() => _loading ??= () async {
    final rows = await db.torznabDao.all();
    _endpoints = [
      for (final r in rows)
        TorznabEndpoint(
          id: r.id,
          name: r.name,
          url: Uri.parse(r.baseUrl),
          enabled: r.enabled,
          caps: r.caps == null ? null : TorznabCaps.fromJson(r.caps!),
          capsAt: r.capsAt,
        ),
    ];
    notifyListeners();
  }();

  Future<String?> _key(TorznabEndpoint e) => secrets.read(e.secretKey);

  /// Adds an endpoint after a successful `t=caps`. Throws [TorznabException]
  /// with a message safe to show.
  Future<TorznabEndpoint> add({required String name, required String url, String? apiKey}) async {
    await load();
    final uri = Uri.tryParse(url.trim());
    final problem = uri == null ? 'Enter a full address, like http://192.168.1.5:9117/api' : endpointProblem(uri);
    if (problem != null) throw TorznabException(problem);
    final key = apiKey?.trim();
    final TorznabCaps caps;
    try {
      caps = await _client(uri!).caps(uri, apiKey: key);
    } on TorznabException {
      rethrow;
    } catch (_) {
      // Other errors may carry the address, which holds the key.
      throw TorznabException('Could not reach the indexer');
    }
    final now = _clock();
    final id = 'tz-${now.microsecondsSinceEpoch.toRadixString(36)}';
    final endpoint = TorznabEndpoint(
      id: id,
      name: name.trim().isEmpty ? uri.host : name.trim(),
      url: uri,
      enabled: true,
      caps: caps,
      capsAt: now,
    );
    if (key != null && key.isNotEmpty) await secrets.write(endpoint.secretKey, key);
    await db.torznabDao.upsert(
      TorznabEndpointRow(
        id: id,
        name: endpoint.name,
        baseUrl: uri.toString(),
        caps: caps.toJson(),
        enabled: true,
        capsAt: now,
      ),
    );
    _endpoints = [..._endpoints, endpoint];
    _health[id] = EndpointHealth(lastOk: now);
    notifyListeners();
    return endpoint;
  }

  /// Asks the endpoint for its capabilities again; updates health and caps.
  /// Not held back by backoff: the user asked.
  Future<TorznabCaps> test(String id) async {
    final e = _byId(id);
    final caps = await _call(e, (client, key) => client.caps(e.url, apiKey: key), force: true);
    final now = _clock();
    await db.torznabDao.setCaps(id, caps.toJson(), now);
    _replace(e.copyWith(caps: caps, capsAt: now));
    return caps;
  }

  Future<void> setEnabled(String id, bool value) async {
    final e = _byId(id);
    await db.torznabDao.setEnabled(id, value);
    _replace(e.copyWith(enabled: value));
  }

  Future<void> remove(String id) async {
    final e = _byId(id);
    await db.torznabDao.remove(id);
    await secrets.delete(e.secretKey);
    _endpoints = [
      for (final x in _endpoints)
        if (x.id != id) x,
    ];
    _health.remove(id);
    _lastCall.remove(id);
    notifyListeners();
  }

  /// A search on [endpoint] with the politeness rules. Throws [TorznabException].
  Future<List<TorznabItem>> search(
    TorznabEndpoint endpoint, {
    String? query,
    List<int> cats = const [],
    int limit = 100,
    int? season,
    int? episode,
    String? imdbId,
    int? tvdbId,
  }) => _call(
    endpoint,
    (client, key) => client.search(
      endpoint.url,
      apiKey: key,
      query: query,
      cats: cats,
      limit: limit,
      season: season,
      episode: episode,
      imdbId: imdbId,
      tvdbId: tvdbId,
    ),
  );

  /// The .torrent behind an item's link, at most 2 MiB, through the same
  /// route as searches.
  Future<Uint8List> fetchTorrent(TorznabEndpoint endpoint, String url) async {
    final uri = Uri.tryParse(url);
    final problem = uri == null ? 'Bad torrent link' : endpointProblem(uri);
    if (problem != null) throw TorznabException(problem);
    final r = await _fetchFor(uri!)(uri);
    if (r.status < 200 || r.status >= 300) throw TorznabException('The indexer answered ${r.status}');
    if (r.body.length > 2 * 1024 * 1024) throw TorznabException('The torrent file is larger than 2 MiB');
    return r.body;
  }

  TorznabEndpoint _byId(String id) => _endpoints.firstWhere((e) => e.id == id);

  void _replace(TorznabEndpoint e) {
    _endpoints = [for (final x in _endpoints) x.id == e.id ? e : x];
    notifyListeners();
  }

  TorznabClient _client(Uri url) => HttpTorznabClient(fetch: _fetchFor(url));

  TorznabFetch _fetchFor(Uri url) {
    final override = _fetchOverride;
    if (override != null) return override;
    final choice = network();
    final socks = choice.socks5;
    if (isPrivateHost(url.host) || choice.mode != NetworkMode.socks5 || socks == null) return fetchDirect;
    return (u) => _brokerFetch(u, socks);
  }

  static Future<TorznabResponse> _brokerFetch(Uri url, Socks5Address socks) async {
    final auth = Uri.parse(socks.url).userInfo.split(':');
    final broker = HttpBroker(
      allowlist: HostAllowlist([url.host]),
      policy: BrokerPolicy(
        requestTimeout: requestTimeout,
        maxBodyBytes: maxResponseBytes,
        maxRedirects: 3,
        socks5: Socks5Config(
          socks.host,
          socks.port,
          user: auth.first.isEmpty ? null : Uri.decodeComponent(auth.first),
          password: auth.length > 1 ? Uri.decodeComponent(auth.skip(1).join(':')) : null,
        ),
      ),
    );
    try {
      final r = await broker.fetch('GET', url.toString(), const {}, null);
      final ra = r.headers.entries.where((e) => e.key.toLowerCase() == 'retry-after').firstOrNull?.value;
      final secs = int.tryParse(ra ?? '');
      return TorznabResponse(r.status, r.body, retryAfter: secs == null ? null : Duration(seconds: secs));
    } on BrokerDenied catch (e) {
      // The reason never holds the URL.
      throw TorznabException('The SOCKS5 route refused the request: ${e.reason}');
    } on TimeoutException {
      throw TorznabException('The indexer did not answer in ${requestTimeout.inSeconds} s');
    } catch (_) {
      throw TorznabException('Could not reach the indexer through SOCKS5');
    }
  }

  Future<T> _call<T>(
    TorznabEndpoint e,
    Future<T> Function(TorznabClient client, String? key) run, {
    bool force = false,
  }) async {
    final h = health(e.id);
    final now = _clock();
    if (!force && h.retryAt != null && now.isBefore(h.retryAt!)) {
      throw TorznabException('${e.name} is backing off after an error: ${h.lastError ?? 'unreachable'}');
    }
    // One request per minGap per endpoint.
    final last = _lastCall[e.id];
    final slot = last != null && last.add(minGap).isAfter(now) ? last.add(minGap) : now;
    _lastCall[e.id] = slot;
    if (slot.isAfter(now)) await Future<void>.delayed(slot.difference(now));
    try {
      final result = await run(_client(e.url), await _key(e));
      _health[e.id] = EndpointHealth(lastOk: _clock(), lastError: null);
      notifyListeners();
      return result;
    } on TorznabException catch (x) {
      _fail(e.id, x.message, x.retryAfter);
      rethrow;
    } catch (_) {
      _fail(e.id, 'Unexpected error', null);
      throw TorznabException('Unexpected error talking to ${e.name}');
    }
  }

  void _fail(String id, String message, Duration? retryAfter) {
    final prev = health(id);
    final n = prev.failures + 1;
    var delay = _baseBackoff * math.pow(2, n - 1).toInt().clamp(1, 1 << 20);
    if (delay > maxBackoff) delay = maxBackoff;
    delay = Duration(milliseconds: (delay.inMilliseconds * (0.8 + _random.nextDouble() * 0.4)).round());
    if (retryAfter != null && retryAfter > delay) delay = retryAfter;
    if (delay > maxBackoff) delay = maxBackoff;
    _health[id] = EndpointHealth(lastOk: prev.lastOk, lastError: message, failures: n, retryAt: _clock().add(delay));
    notifyListeners();
  }
}

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/prefs.dart';
import 'gateway_client.dart';
import 'media_config.dart';
import 'models.dart';
import 'stream_proxy.dart';
import 'token_store.dart';

typedef GatewayFactory = GatewayClient Function(GatewayHost host, String fingerprint, String? token);

GatewayClient _realClient(GatewayHost host, String fingerprint, String? token) =>
    GatewayClient(host: host, fingerprint: fingerprint, token: token);

/// The Media section's state: the flag, the pinned address, the device token
/// and who the gateway says we are. Nothing here touches the network until a
/// screen asks, and nothing at all while the flag is off.
class MediaService extends ChangeNotifier {
  MediaService({required this._prefs, required this._tokens, GatewayFactory? factory})
      : _factory = factory ?? _realClient {
    _prefs.addListener(_prefsChanged);
    _wasEnabled = enabled;
  }

  final Prefs _prefs;
  final TokenStore _tokens;
  final GatewayFactory _factory;

  bool _wasEnabled = false;
  bool _loaded = false;
  String? _token;
  Me? _me;
  GatewayClient? _client;
  final Set<StreamProxy> _proxies = {};

  /// The feature flag (`media.enabled`, off by default).
  bool get enabled => mediaEnabled(_prefs);

  MediaConfig get config => MediaConfig.read(_prefs);

  /// A token is stored and the pin is known.
  bool get paired => enabled && _token != null && config.configured;

  /// The token has been read from secure storage.
  bool get loaded => _loaded;

  Me? get me => _me;
  MediaRole? get role => _me?.role;

  /// Turns the section on or off. Off also drops the connection and the
  /// in-memory token, but keeps the pairing.
  Future<void> setEnabled(bool on) => _prefs.set(mediaEnabledPref, on);

  void _prefsChanged() {
    final now = enabled;
    if (now == _wasEnabled) return;
    _wasEnabled = now;
    if (!now) _drop();
    notifyListeners();
  }

  void _drop() {
    // Playback proxies hold the token's authority: they die with the pairing.
    for (final p in _proxies.toList()) {
      unawaited(p.close());
    }
    _proxies.clear();
    _client?.close();
    _client = null;
    _token = null;
    _me = null;
    _loaded = false;
    _images.clear();
    _imageBytes = 0;
  }

  /// Reads the token from secure storage (once). Call when the section is
  /// first shown, never at launch.
  Future<void> load() async {
    if (!enabled || _loaded) return;
    _token = await _tokens.read();
    _loaded = true;
    notifyListeners();
  }

  GatewayClient? _clientFor() {
    final cfg = config;
    final token = _token;
    if (!enabled || !cfg.configured || token == null) return null;
    return _client ??= _factory(cfg.host!, cfg.fingerprint!, token);
  }

  /// Validates the typed [address], [fingerprint] and 6-digit [code], pins the
  /// certificate, and trades the code for a device token. The pin is stored
  /// only after the gateway accepted the code.
  Future<void> pair({required String address, required String fingerprint, required String code}) async {
    if (!enabled) throw const GatewayException(GatewayErrorKind.invalidInput, 'Media is switched off.');
    final host = parseGatewayHost(address);
    if (host == null) {
      throw const GatewayException(
        GatewayErrorKind.invalidInput,
        'Enter the server as a host name or IP address, optionally with :port. No http:// and no path.',
      );
    }
    final fp = normalizeFingerprint(fingerprint);
    if (fp == null) {
      throw const GatewayException(
        GatewayErrorKind.invalidInput,
        'The fingerprint is 64 hex digits (the gateway prints it as AA:BB:...).',
      );
    }
    final c = code.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(c)) {
      throw const GatewayException(GatewayErrorKind.invalidInput, 'The pairing code is 6 digits.');
    }
    final client = _factory(host, fp, null);
    try {
      final r = await client.pair(c, 'Chithram on ${Platform.operatingSystem}');
      await _tokens.write(r.token);
      await MediaConfig.save(_prefs, host: host, fingerprint: fp);
      _client?.close();
      _client = null;
      _token = r.token;
      _loaded = true;
      _me = Me(user: r.user, role: r.role);
      notifyListeners();
    } finally {
      client.close();
    }
  }

  /// Forgets the token and the pin on this device. (The gateway admin removes
  /// the device on the server side.)
  Future<void> unpair() async {
    await _tokens.clear();
    await MediaConfig.clear(_prefs);
    _drop();
    _loaded = true;
    notifyListeners();
  }

  /// Runs [op] with the paired client. A 401 means the token is dead: the
  /// device unpairs and the error still reaches the caller.
  Future<T> call<T>(Future<T> Function(GatewayClient c) op) async {
    final c = _clientFor();
    if (c == null) {
      throw const GatewayException(GatewayErrorKind.unauthorized, 'This device is not paired.');
    }
    try {
      return await op(c);
    } on GatewayException catch (e) {
      if (e.kind == GatewayErrorKind.unauthorized && identical(c, _client)) await unpair();
      rethrow;
    }
  }

  /// Fetches who we are and our role; keeps it.
  Future<Me> refreshMe() async {
    final m = await call((c) => c.me());
    _me = m;
    notifyListeners();
    return m;
  }

  // ------------------------------------------------------------------ images

  static const _imageBudget = 24 * 1024 * 1024;
  static const _imageParallel = 4;

  final LinkedHashMap<String, Uint8List> _images = LinkedHashMap();
  final Map<String, Future<Uint8List>> _imageInFlight = {};
  int _imageBytes = 0;
  int _imageRunning = 0;
  final Queue<Completer<void>> _imageWaiting = Queue();

  /// A gateway image, cached in memory (bounded), at most 4 fetches at once.
  Future<Uint8List> image(String path) {
    final hit = _images.remove(path);
    if (hit != null) {
      _images[path] = hit;
      return Future.value(hit);
    }
    return _imageInFlight[path] ??= _fetchImage(path).whenComplete(() {
      // A block body: returning the removed future would make it wait on itself.
      _imageInFlight.remove(path);
    });
  }

  Future<Uint8List> _fetchImage(String path) async {
    if (_imageRunning >= _imageParallel) {
      final w = Completer<void>();
      _imageWaiting.add(w);
      await w.future;
    }
    _imageRunning++;
    try {
      final bytes = await call((c) => c.image(path));
      _images[path] = bytes;
      _imageBytes += bytes.length;
      while (_imageBytes > _imageBudget && _images.length > 1) {
        final oldest = _images.keys.first;
        _imageBytes -= _images.remove(oldest)!.length;
      }
      return bytes;
    } finally {
      _imageRunning--;
      if (_imageWaiting.isNotEmpty) _imageWaiting.removeFirst().complete();
    }
  }

  /// The paired client for the player proxy, or null.
  GatewayClient? get clientForStream => _clientFor();

  /// Starts a loopback playback proxy for [itemId], or null when not paired.
  /// A 401 on the stream unpairs; unpairing or switching Media off closes it.
  Future<StreamProxy?> startStream(String itemId) async {
    final c = _clientFor();
    if (c == null) return null;
    final proxy = await StreamProxy.start(
      c,
      itemId,
      onUnauthorized: () => unawaited(unpair()),
      onClosed: _proxies.remove,
    );
    _proxies.add(proxy);
    return proxy;
  }

  @override
  void dispose() {
    _prefs.removeListener(_prefsChanged);
    for (final p in _proxies.toList()) {
      unawaited(p.close());
    }
    _client?.close();
    super.dispose();
  }
}

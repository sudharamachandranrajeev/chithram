import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_rx/localsend_rx.dart';
import 'package:tdlib/tdlib.dart';

import '../../core/paths.dart';
import '../../core/prefs.dart';
import '../../core/secrets.dart';
import '../../player/play_request.dart';
import '../receive/receive_prompt.dart';
import 'telegram_store.dart';
import 'tg_range_server.dart';

/// The Telegram app id and hash this build was made with (repo secrets
/// CHITHRAM_TG_API_ID / CHITHRAM_TG_API_HASH, passed as --dart-define). Empty
/// in builds made without them.
const _buildApiId = String.fromEnvironment('TG_API_ID');
const _buildApiHash = String.fromEnvironment('TG_API_HASH');

/// Prefs keys and the secret key.
abstract final class TelegramPrefs {
  /// True once signed in; false after Sign out. Decides whether the client
  /// starts with the app.
  static const enabled = 'telegram.enabled';
  static const dbKey = 'telegram.dbkey';
}

enum TelegramStatus {
  /// No app id in this build, or no TDLib library for this platform.
  unavailable,
  signedOut,
  starting,
  qr,
  phone,
  code,
  password,
  ready,
  loggingOut,
  error,
}

class TelegramState {
  const TelegramState(this.status, {this.qrLink, this.phone, this.hint, this.message});

  final TelegramStatus status;

  /// `tg://login?token=...` while [status] is [TelegramStatus.qr].
  final String? qrLink;
  final String? phone;

  /// The 2FA password hint.
  final String? hint;

  /// Why it is unavailable or failed.
  final String? message;

  bool get signingIn =>
      status == TelegramStatus.starting ||
      status == TelegramStatus.qr ||
      status == TelegramStatus.phone ||
      status == TelegramStatus.code ||
      status == TelegramStatus.password;
}

/// A file from Saved Messages in the Receive list.
class TelegramItem {
  const TelegramItem({required this.media, required this.file, this.fromHistory = false});

  final TgMedia media;

  /// Download progress.
  final TgFile file;

  /// Offered on start, not received while running.
  final bool fromHistory;

  String get name => media.name;
  int get fileId => media.fileId;
  int get size => file.size;
  bool get isComplete => file.isComplete;

  /// 0..1; null when nothing has been fetched.
  double? get progress => size <= 0 ? null : (file.isComplete ? 1 : (file.downloadedSize / size).clamp(0, 1).toDouble());

  TelegramItem withFile(TgFile f) => TelegramItem(media: media, file: f, fromHistory: fromHistory);
}

typedef TelegramClientFactory = Future<TelegramClient> Function();

/// Receives media sent to the user's own Saved Messages through TDLib, with
/// the user's Telegram account: downloads it and plays it while it downloads.
/// Nothing else in Telegram is read.
class TelegramService extends ChangeNotifier {
  TelegramService({
    required this.navigatorKey,
    required this.paths,
    required this.prefs,
    required this.secrets,
    int? apiId,
    String? apiHash,
    TelegramClientFactory? clientFactory,
    bool Function()? isForeground,
    DateTime Function()? clock,
    Future<void> Function(BuildContext, PlayRequest)? player,
    TelegramStore? store,
    this.historyCount = 20,
    this.maxAge = const Duration(days: 7),
    this.maxBytes = 4 * 1024 * 1024 * 1024,
  })  : apiId = apiId ?? int.tryParse(_buildApiId),
        apiHash = apiHash ?? (_buildApiHash.isEmpty ? null : _buildApiHash),
        _factory = clientFactory ?? TdClient.openNative,
        _isForeground = isForeground ?? _appForeground,
        _clock = clock ?? DateTime.now,
        _player = player ?? openPlayer,
        _store = store ?? TelegramStore(paths.supportFile('telegram_downloads.json'));

  final GlobalKey<NavigatorState> navigatorKey;
  final AppPaths paths;
  final Prefs prefs;
  final SecretStore secrets;
  final int? apiId;
  final String? apiHash;
  final int historyCount;
  final Duration maxAge;
  final int maxBytes;
  final TelegramClientFactory _factory;
  final bool Function() _isForeground;
  final DateTime Function() _clock;
  final Future<void> Function(BuildContext, PlayRequest) _player;
  final TelegramStore _store;

  static bool _appForeground() {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  bool get hasAppId => apiId != null && apiHash != null && apiHash!.isNotEmpty;

  final _state = ValueNotifier(const TelegramState(TelegramStatus.signedOut));
  ValueListenable<TelegramState> get state => _state;

  final _items = <int, TelegramItem>{}; // by message id
  List<TelegramItem> _sorted = const [];

  /// Newest first. Notifies as files arrive and download.
  List<TelegramItem> get items => _sorted;

  TelegramClient? _client;
  TgRangeServer? _server;
  Future<void>? _booting;
  final _subs = <StreamSubscription<Object?>>[];
  late DateTime _startedAt;
  bool _prompting = false;
  Timer? _throttle;
  bool _cleaning = false;
  int? _playingFile;

  /// Starts the client at app launch when the user signed in before.
  Future<void> resume() async {
    if (!prefs.getBool(TelegramPrefs.enabled) || !hasAppId) {
      _publishUnavailable();
      return;
    }
    await start();
  }

  /// Starts the client (the Settings > Telegram screen calls this to sign in).
  Future<void> start() => _booting ??= _boot().whenComplete(() => _booting = null);

  void _publishUnavailable() {
    if (!hasAppId) {
      _state.value = const TelegramState(
        TelegramStatus.unavailable,
        message: 'This build has no Telegram app id.',
      );
    }
  }

  Future<void> _boot() async {
    if (_client != null) return;
    if (!hasAppId) {
      _publishUnavailable();
      return;
    }
    _startedAt = _clock();
    _state.value = const TelegramState(TelegramStatus.starting);
    try {
      final client = await _factory();
      _client = client;
      _subs
        ..add(client.authStates.listen(_onAuth))
        ..add(client.newMedia.listen((m) => unawaited(_onLive(m))))
        ..add(client.fileUpdates.listen(_onFile));
      final dir = '${paths.support.path}/telegram';
      await Directory('$dir/db').create(recursive: true);
      await Directory('$dir/files').create(recursive: true);
      await client.start(
        apiId: apiId!,
        apiHash: apiHash!,
        databaseDirectory: '$dir/db',
        filesDirectory: '$dir/files',
        encryptionKey: await _key(),
      );
    } on TdUnavailable catch (e) {
      _client = null;
      _state.value = TelegramState(TelegramStatus.unavailable, message: e.message);
    } catch (e) {
      await _drop();
      _state.value = TelegramState(TelegramStatus.error, message: 'Could not start Telegram: $e');
    }
  }

  /// The database key, made once and kept in the secret store.
  Future<Uint8List> _key() async {
    final known = await secrets.read(TelegramPrefs.dbKey);
    if (known != null) {
      final bytes = Uint8List.fromList([
        for (var i = 0; i + 1 < known.length; i += 2) int.parse(known.substring(i, i + 2), radix: 16),
      ]);
      if (bytes.length == 32) return bytes;
    }
    final r = Random.secure();
    final bytes = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    await secrets.write(TelegramPrefs.dbKey, bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
    return bytes;
  }

  Future<void> _drop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final c = _client;
    _client = null;
    try {
      await c?.close();
    } catch (_) {}
    await _server?.close();
    _server = null;
  }

  // ---- sign-in -----------------------------------------------------------

  void _onAuth(TgAuthState s) {
    switch (s) {
      case TgAuthWaitParameters():
      case TgAuthClosing():
        break;
      case TgAuthWaitPhone():
        // QR first: best on a TV. The phone number path is offered next to it.
        _state.value = const TelegramState(TelegramStatus.starting);
        unawaited(_requestQr());
      case TgAuthWaitQr(:final link):
        _state.value = TelegramState(TelegramStatus.qr, qrLink: link);
      case TgAuthWaitCode(:final phoneNumber):
        _state.value = TelegramState(TelegramStatus.code, phone: phoneNumber);
      case TgAuthWaitPassword(:final hint):
        _state.value = TelegramState(TelegramStatus.password, hint: hint);
      case TgAuthReady():
        _state.value = const TelegramState(TelegramStatus.ready);
        unawaited(prefs.set(TelegramPrefs.enabled, true));
        unawaited(_loadHistory());
        unawaited(cleanUp());
      case TgAuthLoggingOut():
        _state.value = const TelegramState(TelegramStatus.loggingOut);
      case TgAuthClosed():
        unawaited(_afterClosed());
      case TgAuthUnsupported(:final type):
        _state.value = TelegramState(
          TelegramStatus.error,
          message: 'Telegram asks for a step Chithram cannot do yet ($type). Finish signing in with the Telegram app.',
        );
    }
  }

  Future<void> _requestQr() async {
    try {
      await _client?.requestQrLogin();
    } on TdError catch (e) {
      _state.value = TelegramState(TelegramStatus.phone, message: e.message);
    }
  }

  /// Switches the sign-in from the QR code to a phone number.
  void usePhoneNumber() {
    if (_state.value.status == TelegramStatus.qr) _state.value = const TelegramState(TelegramStatus.phone);
  }

  Future<String?> submitPhone(String phone) => _guard(() => _client!.submitPhone(phone.trim()));
  Future<String?> submitCode(String code) => _guard(() => _client!.submitCode(code.trim()));
  Future<String?> submitPassword(String password) => _guard(() => _client!.submitPassword(password));

  /// Runs a sign-in step; returns TDLib's error message, or null.
  Future<String?> _guard(Future<void> Function() step) async {
    if (_client == null) return 'Telegram is not running.';
    try {
      await step();
      return null;
    } on TdError catch (e) {
      return e.message;
    }
  }

  /// Signs out of Telegram and wipes TDLib's database and files.
  Future<void> signOut() async {
    final c = _client;
    if (c == null) {
      await _wipe();
      return;
    }
    _state.value = const TelegramState(TelegramStatus.loggingOut);
    try {
      await c.logOut();
    } on TdError {
      await _afterClosed();
    }
  }

  Future<void> _afterClosed() async {
    await _drop();
    await _wipe();
  }

  Future<void> _wipe() async {
    final dir = Directory('${paths.support.path}/telegram');
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Files still open on Windows: gone on the next sign-out.
    }
    await _store.clear();
    await prefs.set(TelegramPrefs.enabled, false);
    await secrets.delete(TelegramPrefs.dbKey);
    _items.clear();
    _publishItems();
    _state.value = hasAppId
        ? const TelegramState(TelegramStatus.signedOut)
        : const TelegramState(TelegramStatus.unavailable, message: 'This build has no Telegram app id.');
  }

  // ---- receiving ---------------------------------------------------------

  Future<void> _loadHistory() async {
    final c = _client;
    if (c == null) return;
    try {
      for (final m in await c.recentSavedMedia(historyCount)) {
        _items.putIfAbsent(m.messageId, () => TelegramItem(media: m, file: m.file, fromHistory: true));
      }
      _publishItems();
    } on TdError {
      // The list stays as it is; new files still arrive.
    }
  }

  /// A file arrived in Saved Messages while the client runs: download it, then
  /// play it (or ask, if something is playing).
  Future<void> _onLive(TgMedia m) async {
    if (_items.containsKey(m.messageId)) return;
    // TDLib replays what came in while the app was closed: a list entry only.
    final old = m.date.isBefore(_startedAt.subtract(const Duration(minutes: 1)));
    final item = TelegramItem(media: m, file: m.file, fromHistory: old);
    _items[m.messageId] = item;
    _publishItems();
    if (old) return;
    await _startDownload(item);
    if (!_isForeground()) return;
    if (PlayerActivity.idle) {
      await play(item);
    } else {
      await _ask(item);
    }
  }

  Future<void> _startDownload(TelegramItem item) async {
    final c = _client;
    if (c == null) return;
    await _store.touch(item.fileId, item.size, _clock());
    try {
      await c.downloadFile(item.fileId);
    } on TdError {
      // Retried when played.
    }
    unawaited(cleanUp());
  }

  Future<void> _ask(TelegramItem item) async {
    final context = navigatorKey.currentContext;
    if (_prompting || context == null || !context.mounted) return;
    _prompting = true;
    try {
      final offer = LsOffer(
        senderAlias: 'Telegram',
        senderAddress: 'Saved Messages',
        files: [LsOfferedFile(id: '${item.fileId}', name: item.name, size: item.size, type: item.media.mime)],
      );
      final yes = await showReceivePrompt(
        context,
        offer,
        dismiss: ChangeNotifier(),
        title: 'New from Telegram',
        acceptLabel: 'Play',
      );
      if (yes) await play(item);
    } finally {
      _prompting = false;
    }
  }

  void _onFile(TgFile f) {
    var changed = false;
    for (final e in _items.entries) {
      if (e.value.fileId == f.id) {
        _items[e.key] = e.value.withFile(f);
        changed = true;
      }
    }
    if (!changed) return;
    // Progress updates come many times a second.
    _throttle ??= Timer(const Duration(milliseconds: 400), () {
      _throttle = null;
      _publishItems();
    });
  }

  void _publishItems() {
    _sorted = _items.values.toList()..sort((a, b) => b.media.date.compareTo(a.media.date));
    notifyListeners();
  }

  // ---- playing -----------------------------------------------------------

  /// Plays [item] while it downloads.
  Future<void> play(TelegramItem item) async {
    final c = _client;
    if (c == null) return;
    final server = _server ??= TgRangeServer(c);
    await _store.touch(item.fileId, item.size, _clock());
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _playingFile = item.fileId;
    try {
      await _player(
        context,
        PlayRequest(
          itemId: 'tg:${item.media.messageId}',
          title: item.name,
          subtitle: 'From Telegram',
          resolve: () async => MediaSpec(videoUrl: await server.urlFor(item.fileId, item.name, mime: item.media.mime)),
        ),
      );
    } finally {
      _playingFile = null;
    }
  }

  // ---- storage -----------------------------------------------------------

  /// Deletes downloads older than [maxAge], then the oldest while the total is
  /// over [maxBytes].
  Future<void> cleanUp() async {
    final c = _client;
    if (c == null || _cleaning) return;
    _cleaning = true;
    try {
      final drop = planCleanup(
        await _store.all(),
        now: _clock(),
        maxAge: maxAge,
        maxBytes: maxBytes,
        keep: {?_playingFile},
      );
      await _delete(c, drop.map((d) => d.fileId));
    } finally {
      _cleaning = false;
    }
  }

  /// "Clear Telegram downloads": removes every downloaded file (the list keeps
  /// its entries; playing one fetches it again).
  Future<void> clearDownloads() async {
    final c = _client;
    final all = await _store.all();
    if (c != null) await _delete(c, all.map((d) => d.fileId));
    await _store.clear();
  }

  Future<void> _delete(TelegramClient c, Iterable<int> ids) async {
    final done = <int>[];
    for (final id in ids) {
      try {
        await c.deleteFile(id);
        done.add(id);
      } on TdError {
        // Already gone.
        done.add(id);
      }
    }
    await _store.remove(done);
    for (final e in _items.entries.toList()) {
      if (done.contains(e.value.fileId)) {
        _items[e.key] = e.value.withFile(e.value.file.copyWith(isComplete: false, prefixSize: 0, downloadOffset: 0, downloadedSize: 0, isDownloading: false));
      }
    }
    _publishItems();
  }

  /// Total bytes of the downloads kept, for Settings.
  Future<int> downloadedBytes() async => (await _store.all()).fold<int>(0, (n, d) => n + d.size);

  @override
  void dispose() {
    _throttle?.cancel();
    unawaited(_drop());
    super.dispose();
  }
}

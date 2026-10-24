import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';
import 'native.dart';
import 'transport.dart';

/// What the app needs from Telegram: sign in, see new media in Saved Messages,
/// download and read files. [TdClient] is the real one (TDLib); tests use
/// `FakeTelegramClient`.
abstract interface class TelegramClient {
  /// The current sign-in step; [authStates] announces changes.
  TgAuthState get authState;
  Stream<TgAuthState> get authStates;

  /// A video, audio or media document that arrived in Saved Messages while
  /// the client runs (only Saved Messages is read, no other chat).
  Stream<TgMedia> get newMedia;

  /// Every file change (download progress), for all files.
  Stream<TgFile> get fileUpdates;

  /// Opens the database and connects. Sign-in steps follow on [authStates].
  Future<void> start({
    required int apiId,
    required String apiHash,
    required String databaseDirectory,
    required String filesDirectory,
    required Uint8List encryptionKey,
  });

  /// Asks Telegram for a login QR code: the next state is [TgAuthWaitQr].
  Future<void> requestQrLogin();
  Future<void> submitPhone(String phone);
  Future<void> submitCode(String code);
  Future<void> submitPassword(String password);

  /// Signs out of Telegram; the state ends at [TgAuthClosed].
  Future<void> logOut();

  /// The newest [limit] media messages in Saved Messages, newest first.
  Future<List<TgMedia>> recentSavedMedia(int limit);

  Future<TgFile> getFile(int fileId);

  /// Starts (or moves) a download at [offset]; [limit] 0 means to the end.
  /// Returns at once with the file as it stands.
  Future<TgFile> downloadFile(int fileId, {int priority = 32, int offset = 0, int limit = 0});

  /// Reads [count] bytes at [offset] from what TDLib has on disk.
  Future<Uint8List> readFilePart(int fileId, int offset, int count);

  /// Removes the local copy.
  Future<void> deleteFile(int fileId);

  /// Closes the client (keeps the sign-in).
  Future<void> close();
}

/// [TelegramClient] over TDLib's JSON interface. Only the ~20 objects in
/// models.dart are read.
class TdClient implements TelegramClient {
  TdClient(this._transport) {
    _sub = _transport.updates.listen(_onUpdate);
  }

  /// A client on the native TDLib library; throws [TdUnavailable] when this
  /// build has none.
  static Future<TdClient> openNative() async => TdClient(await NativeTdTransport.open());

  final TdTransport _transport;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  final _auth = StreamController<TgAuthState>.broadcast();
  final _media = StreamController<TgMedia>.broadcast();
  final _files = StreamController<TgFile>.broadcast();
  TgAuthState? _last;
  int? _me;
  Map<String, dynamic>? _params;

  @override
  TgAuthState get authState => _last ?? const TgAuthWaitParameters();
  @override
  Stream<TgAuthState> get authStates => _auth.stream;
  @override
  Stream<TgMedia> get newMedia => _media.stream;
  @override
  Stream<TgFile> get fileUpdates => _files.stream;

  @override
  Future<void> start({
    required int apiId,
    required String apiHash,
    required String databaseDirectory,
    required String filesDirectory,
    required Uint8List encryptionKey,
  }) async {
    _params = {
      '@type': 'setTdlibParameters',
      'use_test_dc': false,
      'database_directory': databaseDirectory,
      'files_directory': filesDirectory,
      'database_encryption_key': base64Encode(encryptionKey),
      'use_file_database': true,
      'use_chat_info_database': true,
      'use_message_database': true,
      'use_secret_chats': false,
      'api_id': apiId,
      'api_hash': apiHash,
      'system_language_code': 'en',
      'device_model': 'Chithram',
      'system_version': '',
      'application_version': '1',
    };
    // TDLib sends its first authorization state on its own; if that came
    // before the parameters were known, answer it now, else ask for it.
    if (_last is TgAuthWaitParameters) {
      unawaited(_transport.request(_params!).then((_) {}, onError: (_) {}));
      return;
    }
    unawaited(_transport.request({'@type': 'getAuthorizationState'}).then(
      (o) => _setState(TgAuthState.fromJson(o)),
      onError: (_) {},
    ));
  }

  void _setState(TgAuthState s) {
    final last = _last;
    // The nudge and the update both report the same step; QR, code and
    // password steps carry data, so those always pass.
    final carries = s is TgAuthWaitQr || s is TgAuthWaitCode || s is TgAuthWaitPassword;
    if (last != null && last.runtimeType == s.runtimeType && !carries) return;
    _last = s;
    if (s is TgAuthWaitParameters && _params != null) {
      unawaited(_transport.request(_params!).then((_) {}, onError: (_) {}));
    }
    if (s is TgAuthReady) unawaited(_resolveMe().then((_) {}, onError: (_) {}));
    if (!_auth.isClosed) _auth.add(s);
  }

  Future<int> _resolveMe() async {
    final known = _me;
    if (known != null) return known;
    final me = await _transport.request({'@type': 'getMe'});
    final id = (me['id'] as num).toInt();
    _me = id;
    // Makes sure the Saved Messages chat is loaded.
    try {
      await _transport.request({'@type': 'createPrivateChat', 'user_id': id, 'force': false});
    } on TdError {
      // History loading retries it.
    }
    return id;
  }

  void _onUpdate(Map<String, dynamic> u) {
    switch (u['@type']) {
      case 'updateAuthorizationState':
        _setState(TgAuthState.fromJson((u['authorization_state'] as Map).cast<String, dynamic>()));
      case 'updateFile':
        final f = u['file'];
        if (f is Map) _files.add(TgFile.fromJson(f.cast<String, dynamic>()));
      case 'updateNewMessage':
        final m = u['message'];
        if (m is Map) unawaited(_onMessage(m.cast<String, dynamic>()));
    }
  }

  Future<void> _onMessage(Map<String, dynamic> m) async {
    final media = TgMedia.fromMessage(m);
    if (media == null) return;
    // Only Saved Messages: the chat of the user's own id.
    int me;
    try {
      me = await _resolveMe();
    } on TdError {
      return;
    }
    if (media.chatId == me && !_media.isClosed) _media.add(media);
  }

  @override
  Future<void> requestQrLogin() async {
    await _transport.request({'@type': 'requestQrCodeAuthentication', 'other_user_ids': <int>[]});
  }

  @override
  Future<void> submitPhone(String phone) async {
    await _transport.request({'@type': 'setAuthenticationPhoneNumber', 'phone_number': phone, 'settings': null});
  }

  @override
  Future<void> submitCode(String code) async {
    await _transport.request({'@type': 'checkAuthenticationCode', 'code': code});
  }

  @override
  Future<void> submitPassword(String password) async {
    await _transport.request({'@type': 'checkAuthenticationPassword', 'password': password});
  }

  @override
  Future<void> logOut() async {
    await _transport.request({'@type': 'logOut'});
  }

  @override
  Future<List<TgMedia>> recentSavedMedia(int limit) async {
    final me = await _resolveMe();
    final found = <TgMedia>[];
    var from = 0;
    // Pages of 50, newest first, until enough media (or 6 pages: a chat full
    // of text should not keep this busy).
    for (var page = 0; page < 6 && found.length < limit; page++) {
      final h = await _transport.request({
        '@type': 'getChatHistory',
        'chat_id': me,
        'from_message_id': from,
        'offset': 0,
        'limit': 50,
        'only_local': false,
      });
      final messages = (h['messages'] as List?)?.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() ?? const [];
      if (messages.isEmpty) break;
      for (final m in messages) {
        final media = TgMedia.fromMessage(m);
        if (media != null && media.chatId == me) found.add(media);
        if (found.length >= limit) break;
      }
      from = (messages.last['id'] as num).toInt();
    }
    return found;
  }

  @override
  Future<TgFile> getFile(int fileId) async =>
      TgFile.fromJson(await _transport.request({'@type': 'getFile', 'file_id': fileId}));

  @override
  Future<TgFile> downloadFile(int fileId, {int priority = 32, int offset = 0, int limit = 0}) async =>
      TgFile.fromJson(await _transport.request({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': priority,
        'offset': offset,
        'limit': limit,
        'synchronous': false,
      }));

  @override
  Future<Uint8List> readFilePart(int fileId, int offset, int count) async {
    final o = await _transport.request({'@type': 'readFilePart', 'file_id': fileId, 'offset': offset, 'count': count});
    return base64Decode('${o['data'] ?? ''}');
  }

  @override
  Future<void> deleteFile(int fileId) async {
    await _transport.request({'@type': 'deleteFile', 'file_id': fileId});
  }

  @override
  Future<void> close() async {
    // After a log out TDLib is already closed and would never answer.
    if (_last is! TgAuthClosed) {
      try {
        await _transport.request({'@type': 'close'}).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Closing anyway.
      }
    }
    await _sub.cancel();
    _transport.close();
    await _auth.close();
    await _media.close();
    await _files.close();
  }
}

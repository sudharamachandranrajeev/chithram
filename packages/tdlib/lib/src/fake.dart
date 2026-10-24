import 'dart:async';
import 'dart:typed_data';

import 'client.dart';
import 'models.dart';

/// A [TelegramClient] with no Telegram behind it, for tests: drive the
/// sign-in with [emitAuth], deliver media with [receive], and file bytes come
/// from [content] with download progress under the test's control.
class FakeTelegramClient implements TelegramClient {
  FakeTelegramClient({this.autoDownload = false});

  /// When true a started download completes at once; otherwise the test calls
  /// [advance].
  final bool autoDownload;

  final _auth = StreamController<TgAuthState>.broadcast();
  final _media = StreamController<TgMedia>.broadcast();
  final _files = StreamController<TgFile>.broadcast();
  TgAuthState _state = const TgAuthWaitParameters();

  /// Saved Messages history, newest first.
  final history = <TgMedia>[];

  /// The bytes of each file by id.
  final content = <int, Uint8List>{};

  final _files0 = <int, TgFile>{};
  final calls = <String>[];
  bool started = false;
  bool closed = false;
  String? lastPhone;
  String? lastCode;
  String? lastPassword;
  int? apiId;
  Uint8List? encryptionKey;
  String? databaseDirectory;

  /// Offsets passed to [downloadFile], in order.
  final downloadOffsets = <int>[];
  final deleted = <int>[];

  /// What the next [readFilePart] fails with, if set.
  Object? readError;

  /// What sign-in submissions fail with, if set (a wrong code, say).
  TdError? submitError;

  @override
  TgAuthState get authState => _state;
  @override
  Stream<TgAuthState> get authStates => _auth.stream;
  @override
  Stream<TgMedia> get newMedia => _media.stream;
  @override
  Stream<TgFile> get fileUpdates => _files.stream;

  void emitAuth(TgAuthState s) {
    _state = s;
    _auth.add(s);
  }

  /// A media message arrives in Saved Messages. Registers its file.
  void receive(TgMedia m, {Uint8List? bytes}) {
    _register(m, bytes);
    _media.add(m);
  }

  /// Puts a message in the history without announcing it.
  void addHistory(TgMedia m, {Uint8List? bytes}) {
    _register(m, bytes);
    history.insert(0, m);
  }

  void _register(TgMedia m, Uint8List? bytes) {
    if (bytes != null) content[m.fileId] = bytes;
    _files0[m.fileId] = m.file.copyWith(size: content[m.fileId]?.length ?? m.file.size);
  }

  /// Moves the active download of [fileId] on to [prefix] contiguous bytes
  /// (from its download offset); the whole file when null.
  void advance(int fileId, {int? prefix}) {
    final f = _files0[fileId]!;
    final avail = f.size - f.downloadOffset;
    final p = (prefix ?? avail).clamp(0, avail);
    final done = f.downloadOffset + p >= f.size;
    final next = f.copyWith(prefixSize: p, isComplete: done || f.isComplete, isDownloading: !done, downloadedSize: f.downloadedSize < p ? p : null);
    _files0[fileId] = next;
    _files.add(next);
  }

  @override
  Future<void> start({
    required int apiId,
    required String apiHash,
    required String databaseDirectory,
    required String filesDirectory,
    required Uint8List encryptionKey,
  }) async {
    started = true;
    this.apiId = apiId;
    this.encryptionKey = encryptionKey;
    this.databaseDirectory = databaseDirectory;
    calls.add('start');
  }

  @override
  Future<void> requestQrLogin() async {
    calls.add('qr');
    emitAuth(const TgAuthWaitQr('tg://login?token=fake'));
  }

  @override
  Future<void> submitPhone(String phone) async {
    calls.add('phone');
    if (submitError != null) throw submitError!;
    lastPhone = phone;
    emitAuth(TgAuthWaitCode(phone));
  }

  @override
  Future<void> submitCode(String code) async {
    calls.add('code');
    if (submitError != null) throw submitError!;
    lastCode = code;
    emitAuth(const TgAuthReady());
  }

  @override
  Future<void> submitPassword(String password) async {
    calls.add('password');
    if (submitError != null) throw submitError!;
    lastPassword = password;
    emitAuth(const TgAuthReady());
  }

  @override
  Future<void> logOut() async {
    calls.add('logOut');
    emitAuth(const TgAuthLoggingOut());
    emitAuth(const TgAuthClosed());
  }

  @override
  Future<List<TgMedia>> recentSavedMedia(int limit) async => history.take(limit).toList();

  @override
  Future<TgFile> getFile(int fileId) async => _files0[fileId] ?? (throw const TdError(400, 'Wrong file identifier'));

  @override
  Future<TgFile> downloadFile(int fileId, {int priority = 32, int offset = 0, int limit = 0}) async {
    calls.add('download:$fileId@$offset');
    downloadOffsets.add(offset);
    final f = _files0[fileId] ?? (throw const TdError(400, 'Wrong file identifier'));
    if (f.isComplete) return f;
    _files0[fileId] = f.copyWith(downloadOffset: offset, prefixSize: 0, isDownloading: true);
    if (autoDownload) advance(fileId);
    return _files0[fileId]!;
  }

  @override
  Future<Uint8List> readFilePart(int fileId, int offset, int count) async {
    final e = readError;
    if (e != null) throw e;
    final f = _files0[fileId] ?? (throw const TdError(400, 'Wrong file identifier'));
    if (!f.covers(offset, count) && !f.covers(offset, 1)) return Uint8List(0);
    final all = content[fileId] ?? Uint8List(0);
    final end = (offset + count).clamp(0, all.length);
    final have = f.isComplete ? end : (f.downloadOffset + f.prefixSize).clamp(0, end);
    if (offset >= have) return Uint8List(0);
    return Uint8List.sublistView(all, offset, have);
  }

  @override
  Future<void> deleteFile(int fileId) async {
    calls.add('delete:$fileId');
    deleted.add(fileId);
    final f = _files0[fileId];
    if (f != null) _files0[fileId] = f.copyWith(isComplete: false, prefixSize: 0, downloadOffset: 0, isDownloading: false, downloadedSize: 0);
  }

  @override
  Future<void> close() async {
    closed = true;
    calls.add('close');
  }
}

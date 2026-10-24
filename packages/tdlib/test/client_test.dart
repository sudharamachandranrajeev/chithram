import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tdlib/tdlib.dart';

/// Answers requests from a table and lets the test push updates.
class ScriptedTransport implements TdTransport {
  ScriptedTransport(this.handlers) {
    _router = TdRequestRouter((req) {
      sent.add(req);
      final h = handlers[req['@type']];
      scheduleMicrotask(() {
        if (h == null) {
          _router.handle({'@type': 'ok', '@extra': req['@extra']});
          return;
        }
        final Map<String, dynamic> out;
        try {
          out = h(req);
        } on TdError catch (e) {
          _router.handle({'@type': 'error', 'code': e.code, 'message': e.message, '@extra': req['@extra']});
          return;
        }
        _router.handle({...out, '@extra': req['@extra']});
      });
    });
  }

  final Map<String, Map<String, dynamic> Function(Map<String, dynamic>)> handlers;
  final sent = <Map<String, dynamic>>[];
  late final TdRequestRouter _router;

  void push(Map<String, dynamic> update) => _router.handle(update);

  @override
  Stream<Map<String, dynamic>> get updates => _router.updates;
  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> request) => _router.request(request);
  @override
  void close() => _router.close();
}

Map<String, dynamic> videoMessage({int chat = 42, int id = 1000, String mime = 'video/mp4', String name = 'a.mp4', int fileId = 7}) => {
      '@type': 'message',
      'id': id,
      'chat_id': chat,
      'date': 1700000000,
      'content': {
        '@type': 'messageVideo',
        'video': {
          'file_name': name,
          'mime_type': mime,
          'duration': 60,
          'video': {
            '@type': 'file',
            'id': fileId,
            'size': 5000,
            'expected_size': 5000,
            'local': {'path': '', 'can_be_downloaded': true},
          },
        },
      },
    };

Map<String, dynamic> documentMessage(String name, String mime, {int chat = 42, int id = 2000, int fileId = 8}) => {
      '@type': 'message',
      'id': id,
      'chat_id': chat,
      'date': 1700000100,
      'content': {
        '@type': 'messageDocument',
        'document': {
          'file_name': name,
          'mime_type': mime,
          'document': {'@type': 'file', 'id': fileId, 'size': 100, 'local': {}},
        },
      },
    };

void main() {
  late ScriptedTransport t;
  late TdClient client;

  setUp(() {
    t = ScriptedTransport({
      'getMe': (_) => {'@type': 'user', 'id': 42},
      'getAuthorizationState': (_) => {'@type': 'authorizationStateWaitTdlibParameters'},
    });
    client = TdClient(t);
  });
  tearDown(() => client.close());

  test('sends tdlib parameters with the key as base64 when asked', () async {
    final states = <TgAuthState>[];
    client.authStates.listen(states.add);
    await client.start(
      apiId: 123,
      apiHash: 'hash',
      databaseDirectory: '/d/db',
      filesDirectory: '/d/files',
      encryptionKey: Uint8List.fromList(List.generate(32, (i) => i)),
    );
    await pumpEventQueue();
    final p = t.sent.firstWhere((r) => r['@type'] == 'setTdlibParameters');
    expect(p['api_id'], 123);
    expect(p['api_hash'], 'hash');
    expect(p['use_message_database'], true);
    expect(p['use_file_database'], true);
    expect(p['database_directory'], '/d/db');
    expect(base64Decode(p['database_encryption_key'] as String), hasLength(32));
    // The nudge and the update both say WaitTdlibParameters: parameters go once.
    t.push({'@type': 'updateAuthorizationState', 'authorization_state': {'@type': 'authorizationStateWaitTdlibParameters'}});
    await pumpEventQueue();
    expect(t.sent.where((r) => r['@type'] == 'setTdlibParameters'), hasLength(1));
    expect(states.whereType<TgAuthWaitParameters>(), hasLength(1));
  });

  test('parameters go out even when TDLib asked before start()', () async {
    t.push({'@type': 'updateAuthorizationState', 'authorization_state': {'@type': 'authorizationStateWaitTdlibParameters'}});
    await pumpEventQueue();
    expect(t.sent.where((r) => r['@type'] == 'setTdlibParameters'), isEmpty);
    await client.start(
      apiId: 1,
      apiHash: 'h',
      databaseDirectory: '/d',
      filesDirectory: '/f',
      encryptionKey: Uint8List(32),
    );
    await pumpEventQueue();
    expect(t.sent.where((r) => r['@type'] == 'setTdlibParameters'), hasLength(1));
  });

  test('walks the QR, code and password states', () async {
    final states = <TgAuthState>[];
    client.authStates.listen(states.add);
    void auth(Map<String, dynamic> s) => t.push({'@type': 'updateAuthorizationState', 'authorization_state': s});
    auth({'@type': 'authorizationStateWaitPhoneNumber'});
    await client.requestQrLogin();
    expect(t.sent.last['@type'], 'requestQrCodeAuthentication');
    auth({'@type': 'authorizationStateWaitOtherDeviceConfirmation', 'link': 'tg://login?token=abc'});
    auth({'@type': 'authorizationStateWaitCode', 'code_info': {'phone_number': '+353123'}});
    auth({'@type': 'authorizationStateWaitPassword', 'password_hint': 'dog'});
    auth({'@type': 'authorizationStateReady'});
    await pumpEventQueue();
    expect(states.map((s) => s.runtimeType), [
      TgAuthWaitPhone,
      TgAuthWaitQr,
      TgAuthWaitCode,
      TgAuthWaitPassword,
      TgAuthReady,
    ]);
    expect((states[1] as TgAuthWaitQr).link, 'tg://login?token=abc');
    expect((states[3] as TgAuthWaitPassword).hint, 'dog');
    await client.submitPhone('+353123');
    await client.submitCode('12345');
    await client.submitPassword('pw');
    expect(t.sent.map((r) => r['@type']).toList().sublist(t.sent.length - 3),
        ['setAuthenticationPhoneNumber', 'checkAuthenticationCode', 'checkAuthenticationPassword']);
  });

  test('only Saved Messages (the chat of the own user id) yields new media', () async {
    final got = <TgMedia>[];
    client.newMedia.listen(got.add);
    t.push({'@type': 'updateAuthorizationState', 'authorization_state': {'@type': 'authorizationStateReady'}});
    await pumpEventQueue();
    t.push({'@type': 'updateNewMessage', 'message': videoMessage(chat: 999, id: 1)});
    t.push({'@type': 'updateNewMessage', 'message': videoMessage(chat: 42, id: 2, name: 'mine.mp4')});
    await pumpEventQueue();
    expect(got.map((m) => m.name), ['mine.mp4']);
    expect(got.single.fileId, 7);
    expect(got.single.file.size, 5000);
  });

  test('documents count by mime type or extension; text and images do not', () async {
    expect(TgMedia.fromMessage(documentMessage('x.bin', 'video/x-matroska')), isNotNull);
    expect(TgMedia.fromMessage(documentMessage('x.mkv', 'application/octet-stream')), isNotNull);
    expect(TgMedia.fromMessage(documentMessage('song.FLAC', '')), isNotNull);
    expect(TgMedia.fromMessage(documentMessage('notes.pdf', 'application/pdf')), isNull);
    expect(TgMedia.fromMessage({'@type': 'message', 'id': 1, 'chat_id': 1, 'date': 1, 'content': {'@type': 'messageText'}}), isNull);
    final audio = TgMedia.fromMessage({
      '@type': 'message',
      'id': 3,
      'chat_id': 1,
      'date': 5,
      'content': {
        '@type': 'messageAudio',
        'audio': {
          'file_name': '',
          'title': 'Song',
          'performer': 'Band',
          'mime_type': 'audio/mpeg',
          'audio': {'@type': 'file', 'id': 9, 'size': 10, 'local': {}},
        },
      },
    })!;
    expect(audio.kind, TgMediaKind.audio);
    expect(audio.name, 'Band - Song');
  });

  test('recent history keeps the newest media and skips the rest', () async {
    t.handlers['getChatHistory'] = (req) {
      final from = req['from_message_id'] as int;
      if (from == 0) {
        return {
          'messages': [
            {'@type': 'message', 'id': 30, 'chat_id': 42, 'date': 3, 'content': {'@type': 'messageText'}},
            videoMessage(id: 20, name: 'new.mp4', fileId: 1),
            videoMessage(id: 10, name: 'old.mp4', fileId: 2),
          ],
        };
      }
      return {'messages': <dynamic>[]};
    };
    t.push({'@type': 'updateAuthorizationState', 'authorization_state': {'@type': 'authorizationStateReady'}});
    await pumpEventQueue();
    final recent = await client.recentSavedMedia(20);
    expect(recent.map((m) => m.name), ['new.mp4', 'old.mp4']);
    expect((await client.recentSavedMedia(1)).map((m) => m.name), ['new.mp4']);
  });

  test('file requests map to TDLib calls and objects', () async {
    t.handlers['downloadFile'] = (req) => {
          '@type': 'file',
          'id': req['file_id'],
          'size': 1000,
          'local': {'download_offset': req['offset'], 'downloaded_prefix_size': 0, 'is_downloading_active': true},
        };
    t.handlers['readFilePart'] = (req) => {'@type': 'filePart', 'data': base64Encode([1, 2, 3])};
    final f = await client.downloadFile(5, offset: 400);
    expect(t.sent.last['priority'], 32);
    expect(t.sent.last['offset'], 400);
    expect(f.downloadOffset, 400);
    expect(f.covers(400, 1), isFalse);
    expect(await client.readFilePart(5, 400, 3), [1, 2, 3]);
    await client.deleteFile(5);
    expect(t.sent.last['@type'], 'deleteFile');
  });

  test('updateFile reaches fileUpdates; TDLib errors throw TdError', () async {
    final files = <TgFile>[];
    client.fileUpdates.listen(files.add);
    t.push({
      '@type': 'updateFile',
      'file': {
        '@type': 'file',
        'id': 3,
        'size': 100,
        'local': {'download_offset': 0, 'downloaded_prefix_size': 60, 'is_downloading_completed': false},
      },
    });
    await pumpEventQueue();
    expect(files.single.covers(0, 60), isTrue);
    expect(files.single.covers(0, 61), isFalse);
    t.handlers['getFile'] = (_) => throw const TdError(400, 'Wrong file identifier');
    await expectLater(client.getFile(1), throwsA(isA<TdError>().having((e) => e.code, 'code', 400)));
  });

  test('a completed file covers every range', () {
    final f = TgFile.fromJson({
      'id': 1,
      'size': 10,
      'local': {'is_downloading_completed': true, 'path': '/x'},
    });
    expect(f.covers(0, 10), isTrue);
  });

  test('missing native library is reported, not thrown as an ArgumentError', () {
    expect(
      () => NativeTdTransport.open(),
      // The test host has no TDLib unless CHITHRAM_TDLIB_LIB is set.
      anyOf(throwsA(isA<TdUnavailable>()), returnsNormally),
    );
  });
}

import 'dart:io';

import 'package:chithram/src/features/telegram/telegram_service.dart';
import 'package:chithram/src/features/telegram/telegram_store.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tdlib/tdlib.dart';

import 'support.dart';

void main() {
  group('without an app id', () {
    test('says so and never starts a client', () async {
      final rig = Rig(apiId: null, apiHash: null);
      addTearDown(rig.dispose);
      await rig.service.start();
      await rig.service.resume();
      final s = rig.service.state.value;
      expect(s.status, TelegramStatus.unavailable);
      expect(s.message, contains('no Telegram app id'));
      expect(rig.fake.started, isFalse);
    });

    test('a hash alone is not enough', () async {
      final rig = Rig(apiId: 5, apiHash: '');
      addTearDown(rig.dispose);
      await rig.service.start();
      expect(rig.service.state.value.status, TelegramStatus.unavailable);
    });
  });

  group('sign-in', () {
    test('QR first, then the phone number, code and password', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      final seen = <TelegramStatus>[];
      rig.service.state.addListener(() => seen.add(rig.service.state.value.status));
      await rig.service.start();
      expect(rig.fake.started, isTrue);
      expect(rig.fake.apiId, 1);
      expect(rig.fake.encryptionKey, hasLength(32));
      // The key is made once and reused.
      expect(await rig.secrets.read(TelegramPrefs.dbKey), isNotNull);

      rig.fake.emitAuth(const TgAuthWaitPhone());
      await pumpEventQueue();
      expect(rig.fake.calls, contains('qr'));
      expect(rig.service.state.value.status, TelegramStatus.qr);
      expect(rig.service.state.value.qrLink, 'tg://login?token=fake');

      rig.service.usePhoneNumber();
      expect(rig.service.state.value.status, TelegramStatus.phone);
      expect(await rig.service.submitPhone(' +353861234567 '), isNull);
      expect(rig.fake.lastPhone, '+353861234567');
      await pumpEventQueue();
      expect(rig.service.state.value.status, TelegramStatus.code);

      rig.fake.emitAuth(const TgAuthWaitPassword('dog'));
      await pumpEventQueue();
      expect(rig.service.state.value.status, TelegramStatus.password);
      expect(rig.service.state.value.hint, 'dog');
      expect(await rig.service.submitPassword('secret'), isNull);
      expect(rig.fake.lastPassword, 'secret');
      await pumpEventQueue();
      expect(rig.service.state.value.status, TelegramStatus.ready);
      expect(rig.prefs.getBool(TelegramPrefs.enabled), isTrue);
    });

    test('a wrong code is reported, not thrown', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.start();
      rig.fake.emitAuth(const TgAuthWaitCode('+353'));
      await pumpEventQueue();
      expect(rig.service.state.value.status, TelegramStatus.code);
      rig.fake.submitError = const TdError(400, 'PHONE_CODE_INVALID');
      expect(await rig.service.submitCode('1'), 'PHONE_CODE_INVALID');
      expect(rig.service.state.value.status, TelegramStatus.code);
    });

    test('steps Chithram cannot do end in a clear error', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.start();
      rig.fake.emitAuth(const TgAuthUnsupported('authorizationStateWaitEmailAddress'));
      await pumpEventQueue();
      expect(rig.service.state.value.status, TelegramStatus.error);
      expect(rig.service.state.value.message, contains('WaitEmailAddress'));
    });

    test('resume starts the client only if the user signed in before', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.resume();
      expect(rig.fake.started, isFalse);
      await rig.prefs.set(TelegramPrefs.enabled, true);
      await rig.service.resume();
      expect(rig.fake.started, isTrue);
    });

    test('sign out wipes the TDLib directory, the key and the list', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.signIn();
      rig.fake.addHistory(media(1));
      // History loads on sign-in only; trigger again through a fresh Ready.
      final marker = File('${rig.paths.support.path}/telegram/db/marker')..createSync(recursive: true);
      await rig.service.signOut();
      await pumpEventQueue(times: 50);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(rig.fake.calls, contains('logOut'));
      expect(marker.existsSync(), isFalse);
      expect(rig.prefs.getBool(TelegramPrefs.enabled), isFalse);
      expect(await rig.secrets.read(TelegramPrefs.dbKey), isNull);
      expect(rig.service.state.value.status, TelegramStatus.signedOut);
      expect(rig.service.items, isEmpty);
    });
  });

  group('receiving', () {
    test('lists the last 20 on start, without downloading or playing', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      for (var i = 1; i <= 25; i++) {
        rig.fake.addHistory(media(i, date: DateTime.utc(2026, 10, 1, 0, i)));
      }
      await rig.signIn();
      await pumpEventQueue(times: 20);
      expect(rig.service.items, hasLength(20));
      expect(rig.service.items.first.media.messageId, 25);
      expect(rig.service.items.every((i) => i.fromHistory), isTrue);
      expect(rig.fake.calls.where((c) => c.startsWith('download')), isEmpty);
      expect(rig.played, isEmpty);
    });

    test('a new file starts downloading at once', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.signIn();
      rig.foreground = false; // no navigator here: only the download is checked
      rig.fake.receive(media(7, date: DateTime.utc(2026, 10, 24, 12, 4)), bytes: bytes(1000));
      await pumpEventQueue(times: 20);
      expect(rig.fake.calls, contains('download:70@0'));
      expect(rig.service.items.single.fromHistory, isFalse);
    });

    test('what TDLib replays from before the app started is listed, not fetched', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.signIn();
      rig.fake.receive(media(8, date: DateTime.utc(2026, 10, 23)), bytes: bytes(10));
      await pumpEventQueue(times: 20);
      expect(rig.service.items.single.fromHistory, isTrue);
      expect(rig.fake.calls.where((c) => c.startsWith('download')), isEmpty);
    });

    test('download progress reaches the list', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.signIn();
      rig.foreground = false;
      rig.fake.receive(media(7, date: DateTime.utc(2026, 10, 24, 12, 4)), bytes: bytes(1000));
      await pumpEventQueue(times: 20);
      rig.fake.advance(70);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(rig.service.items.single.isComplete, isTrue);
      expect(rig.service.items.single.progress, 1);
    });
  });

  group('storage', () {
    final now = DateTime.utc(2026, 10, 24);
    TgDownload d(int id, int size, int daysAgo) =>
        TgDownload(fileId: id, size: size, touched: now.subtract(Duration(days: daysAgo)));

    test('files older than 7 days go', () {
      final drop = planCleanup([d(1, 10, 8), d(2, 10, 6), d(3, 10, 30)], now: now);
      expect(drop.map((x) => x.fileId).toSet(), {1, 3});
    });

    test('over the size limit the oldest go first, until it fits', () {
      final drop = planCleanup([d(1, 40, 1), d(2, 40, 3), d(3, 40, 2)], now: now, maxBytes: 100);
      expect(drop.map((x) => x.fileId), [2]);
      final more = planCleanup([d(1, 40, 1), d(2, 40, 3), d(3, 40, 2)], now: now, maxBytes: 50);
      expect(more.map((x) => x.fileId), [2, 3]);
    });

    test('the file now playing is never chosen', () {
      final drop = planCleanup([d(1, 10, 20)], now: now, keep: {1});
      expect(drop, isEmpty);
    });

    test('cleanUp deletes expired files through TDLib', () async {
      var t = DateTime.utc(2026, 10, 1);
      final rig = Rig(clock: () => t);
      addTearDown(rig.dispose);
      await rig.signIn();
      rig.foreground = false;
      rig.fake.receive(media(1, date: DateTime.utc(2026, 10, 1)), bytes: bytes(500));
      await pumpEventQueue(times: 20);
      t = DateTime.utc(2026, 10, 12); // 11 days later
      await rig.service.cleanUp();
      expect(rig.fake.deleted, [10]);
    });

    test('cleanUp keeps the total under the limit', () async {
      final t = DateTime.utc(2026, 10, 24, 12, 5);
      final rig = Rig(clock: () => t, maxBytes: 1500);
      addTearDown(rig.dispose);
      await rig.signIn();
      rig.foreground = false;
      for (var i = 1; i <= 3; i++) {
        rig.fake.receive(media(i, date: DateTime.utc(2026, 10, 24, 12, 4), size: 1000), bytes: bytes(1000));
        await pumpEventQueue(times: 20);
        rig.clock = () => t.add(Duration(minutes: i));
      }
      await rig.service.cleanUp();
      expect(rig.fake.deleted.toSet(), {10, 20});
    });

    test('Clear Telegram downloads removes every file', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.signIn();
      rig.foreground = false;
      rig.fake.receive(media(1, date: DateTime.utc(2026, 10, 24, 12, 4)), bytes: bytes(500));
      rig.fake.receive(media(2, date: DateTime.utc(2026, 10, 24, 12, 4)), bytes: bytes(500));
      await pumpEventQueue(times: 20);
      await rig.service.clearDownloads();
      expect(rig.fake.deleted.toSet(), {10, 20});
      expect(await rig.service.downloadedBytes(), 0);
    });
  });

  group('auto-play', () {
    Future<Rig> signedInApp(WidgetTester t) async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await t.pumpWidget(MaterialApp(navigatorKey: rig.navigatorKey, home: const Scaffold(body: Text('home'))));
      await t.runAsync(rig.signIn);
      return rig;
    }

    final fresh = DateTime.utc(2026, 10, 24, 12, 4);

    testWidgets('plays at once when the app is in front and nothing plays', (t) async {
      final rig = await signedInApp(t);
      await t.runAsync(() async {
        rig.fake.receive(media(7, name: 'Film.mkv', date: fresh), bytes: bytes(1000));
        await pumpEventQueue(times: 30);
      });
      await t.pump();
      expect(rig.played, hasLength(1));
      expect(rig.played.single.title, 'Film.mkv');
      expect(rig.played.single.itemId, 'tg:7');
      expect(rig.fake.calls, contains('download:70@0'));
    });

    testWidgets('asks instead when something is playing', (t) async {
      final rig = await signedInApp(t);
      PlayerActivity.open.value = 1;
      addTearDown(() => PlayerActivity.open.value = 0);
      await t.runAsync(() async {
        rig.fake.receive(media(7, name: 'Film.mkv', date: fresh), bytes: bytes(1000));
        await pumpEventQueue(times: 30);
      });
      await t.pump();
      expect(rig.played, isEmpty);
      expect(find.text('New from Telegram'), findsOneWidget);
      expect(find.textContaining('Film.mkv'), findsOneWidget);
      await t.tap(find.text('Play'));
      await t.runAsync(() => pumpEventQueue(times: 30));
      await t.pump();
      expect(rig.played, hasLength(1));
    });

    testWidgets('Reject leaves it in the list', (t) async {
      final rig = await signedInApp(t);
      PlayerActivity.open.value = 1;
      addTearDown(() => PlayerActivity.open.value = 0);
      await t.runAsync(() async {
        rig.fake.receive(media(7, date: fresh), bytes: bytes(1000));
        await pumpEventQueue(times: 30);
      });
      await t.pump();
      await t.tap(find.text('Reject'));
      await t.runAsync(() => pumpEventQueue(times: 30));
      await t.pump();
      expect(rig.played, isEmpty);
      expect(rig.service.items, hasLength(1));
    });

    testWidgets('nothing happens in the background (the file still downloads)', (t) async {
      final rig = await signedInApp(t);
      rig.foreground = false;
      await t.runAsync(() async {
        rig.fake.receive(media(7, date: fresh), bytes: bytes(1000));
        await pumpEventQueue(times: 30);
      });
      await t.pump();
      expect(rig.played, isEmpty);
      expect(find.text('New from Telegram'), findsNothing);
      expect(rig.fake.calls, contains('download:70@0'));
    });
  });

  group('playing', () {
    testWidgets('the player gets a loopback URL on the range server', (t) async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await t.pumpWidget(MaterialApp(navigatorKey: rig.navigatorKey, home: const SizedBox()));
      await t.runAsync(() async {
        await rig.signIn();
        rig.foreground = false;
        rig.fake.receive(media(7, name: 'A film.mkv', date: DateTime.utc(2026, 10, 24, 12, 4)), bytes: bytes(1000));
        await pumpEventQueue(times: 30);
        await rig.service.play(rig.service.items.single);
        final spec = await rig.played.single.resolve();
        final u = Uri.parse(spec.videoUrl);
        expect(u.host, '127.0.0.1');
        expect(u.pathSegments[1], 'tg');
        expect(u.pathSegments[2], '70');
        expect(Uri.decodeComponent(u.pathSegments[3]), 'A film.mkv');
      });
    });
  });
}

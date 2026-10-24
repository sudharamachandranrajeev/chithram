// End-to-end: Telegram. Run through e2e_all_test.dart (see .github/e2e.sh).
//
// A fake Telegram client stands in for TDLib: a file "sent to Saved Messages"
// is the fixture video, handed over in growing pieces while the real player
// plays it through the real loopback range server.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/core/paths.dart';
import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/secrets.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/telegram/telegram_service.dart';
import 'package:chithram/src/features/telegram/telegram_store.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tdlib/tdlib.dart';

import 'support.dart';

Future<Uint8List> _fixture() async {
  final c = HttpClient();
  try {
    final res = await (await c.getUrl(Uri.parse('$e2eBase/video.mp4'))).close();
    final b = BytesBuilder();
    await for (final chunk in res) {
      b.add(chunk);
    }
    return b.takeBytes();
  } finally {
    c.close(force: true);
  }
}

void telegramE2e() {
  group('telegram', () {
    testWidgets('a file sent to Saved Messages plays while it downloads', (t) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final data = (await t.runAsync(_fixture))!;
      expect(data.length, greaterThan(100 * 1024), reason: 'fixture video');

      final fake = FakeTelegramClient();
      final key = GlobalKey<NavigatorState>();
      final paths = AppPaths.under('${Directory.systemTemp.path}/chithram-e2e-telegram');
      final prefs = Prefs.memory();
      final service = TelegramService(
        navigatorKey: key,
        paths: paths,
        prefs: prefs,
        secrets: MemorySecretStore(),
        apiId: 1,
        apiHash: 'e2e',
        clientFactory: () async => fake,
        store: TelegramStore(null),
      );
      addTearDown(service.dispose);
      final services = AppServices.memory(navigatorKey: key, prefs: prefs, telegram: service);
      await t.pumpWidget(ChithramApp(services: services));
      await t.pumpAndSettle();

      await t.runAsync(() async {
        await service.start();
        fake.emitAuth(const TgAuthWaitPhone());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        fake.emitAuth(const TgAuthReady());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(service.state.value.status, TelegramStatus.ready);

      // The file arrives; the download then proceeds 20% at a time.
      Timer? feeder;
      await t.runAsync(() async {
        fake.receive(
          TgMedia(
            chatId: 1,
            messageId: 1,
            date: DateTime.now().toUtc(),
            kind: TgMediaKind.video,
            name: 'Sent to myself.mp4',
            mime: 'video/mp4',
            file: TgFile(id: 5, size: data.length),
          ),
          bytes: data,
        );
        var step = 0;
        feeder = Timer.periodic(const Duration(milliseconds: 700), (timer) {
          step++;
          fake.advance(5, prefix: step >= 5 ? null : data.length * step ~/ 5);
          if (step >= 5) timer.cancel();
        });
      });

      // It starts playing without a tap.
      for (var i = 0; i < 50 && PlayerActivity.idle; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }
      expect(PlayerActivity.idle, isFalse, reason: 'player should open by itself');
      final position = await waitForPlayback(t);
      // ignore: avoid_print
      print('CHITHRAM_E2E telegram playing at $position');
      feeder?.cancel();

      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(PlayerActivity.idle, isTrue);
      expect(fake.calls, contains('download:5@0'));
    });
  });
}

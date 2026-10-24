import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/telegram/telegram_keys.dart';
import 'package:chithram/src/features/telegram/telegram_page.dart';
import 'package:chithram/src/features/telegram/telegram_received.dart';
import 'package:chithram/src/features/telegram/telegram_settings.dart';
import 'package:chithram/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tdlib/tdlib.dart';

import 'support.dart';

Future<void> show(WidgetTester t, Rig rig, Widget page, {Size size = const Size(1920, 1080)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final services = AppServices.memory(navigatorKey: rig.navigatorKey, telegram: rig.service);
  await t.pumpWidget(
    AppServicesScope(
      services: services,
      child: MaterialApp(navigatorKey: rig.navigatorKey, theme: ThemeData.dark(), home: Scaffold(body: page)),
    ),
  );
}

void main() {
  for (final (label, size) in [('TV', const Size(1920, 1080)), ('phone', const Size(400, 800))]) {
    group(label, () {
      testWidgets('a build without an app id says so', (t) async {
        final rig = Rig(apiId: null, apiHash: null);
        addTearDown(rig.dispose);
        await show(t, rig, const TelegramPage(), size: size);
        await t.runAsync(rig.service.start);
        await t.pump();
        expect(find.byKey(TelegramKeys.unavailable), findsOneWidget);
        expect(find.textContaining('no Telegram app id'), findsOneWidget);
      });

      testWidgets('signed out: Sign in shows the QR code and the phone fallback', (t) async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await show(t, rig, const TelegramPage(), size: size);
        await t.tap(find.byKey(TelegramKeys.signIn));
        await t.runAsync(() async {
          await pumpEventQueue(times: 10);
          rig.fake.emitAuth(const TgAuthWaitPhone());
          await pumpEventQueue(times: 10);
        });
        await t.pump();
        expect(find.byType(QrImageView), findsOneWidget);
        await t.tap(find.byKey(TelegramKeys.usePhone));
        await t.pump();
        expect(find.byKey(TelegramKeys.enterPhone), findsOneWidget);
      });

      testWidgets('signed in: the list shows what arrived and Sign out is there', (t) async {
        final rig = Rig();
        addTearDown(rig.dispose);
        rig.fake.addHistory(media(3, name: 'Old.mkv', size: 2 * 1024 * 1024));
        await show(t, rig, const TelegramPage(), size: size);
        await t.runAsync(rig.signIn);
        await t.runAsync(() => pumpEventQueue(times: 20));
        await t.pump();
        expect(find.textContaining('Old.mkv'), findsOneWidget);
        expect(find.textContaining('2.0 MB'), findsOneWidget);
        expect(find.textContaining('Not downloaded'), findsOneWidget);
        expect(find.byKey(TelegramKeys.signOut), findsOneWidget);
      });
    });
  }

  testWidgets('the Receive section offers set-up when signed out', (t) async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await show(t, rig, const SingleChildScrollView(child: TelegramReceiveSection()));
    expect(find.text('From Telegram'), findsOneWidget);
    expect(find.byKey(TelegramKeys.setup), findsOneWidget);
  });

  testWidgets('selecting a listed file plays it', (t) async {
    final rig = Rig();
    addTearDown(rig.dispose);
    rig.fake.addHistory(media(3, name: 'Old.mkv'));
    await show(t, rig, const SingleChildScrollView(child: TelegramReceiveSection()));
    await t.runAsync(rig.signIn);
    await t.runAsync(() => pumpEventQueue(times: 20));
    await t.pump();
    await t.tap(find.byKey(ValueKey(TelegramKeys.item(3))));
    await t.runAsync(() => pumpEventQueue(times: 20));
    expect(rig.played.single.title, 'Old.mkv');
  });

  testWidgets('settings: label follows the state', (t) async {
    final rig = Rig(apiId: null, apiHash: null);
    addTearDown(rig.dispose);
    await show(t, rig, const TelegramSettings());
    expect(find.text('Telegram: sign in'), findsOneWidget);
    await t.runAsync(rig.service.start);
    await t.pump();
    expect(find.text('Telegram: not in this build'), findsOneWidget);
    expect(ChithramTheme.chithram.accent, isNotNull);
  });
}

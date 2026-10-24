import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/telegram/telegram_keys.dart';
import 'package:chithram/src/features/telegram/telegram_page.dart';
import 'package:chithram/src/features/telegram/telegram_received.dart';
import 'package:chithram/src/features/telegram/telegram_settings.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tdlib/tdlib.dart';

import 'support.dart';

Future<void> show(WidgetTester t, Rig rig, Widget page, {Size size = const Size(1920, 1080), double dpr = 1}) async {
  t.view.physicalSize = size * dpr;
  t.view.devicePixelRatio = dpr;
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

  group('960x540 TV (density 2)', () {
    const screen = Rect.fromLTWH(0, 0, 960, 540);

    Future<Rig> qr(WidgetTester t) async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await show(t, rig, const TelegramPage(), size: const Size(960, 540), dpr: 2);
      await t.tap(find.byKey(TelegramKeys.signIn));
      await t.runAsync(() async {
        await pumpEventQueue(times: 10);
        rig.fake.emitAuth(const TgAuthWaitPhone());
        await pumpEventQueue(times: 10);
      });
      await t.pumpAndSettle();
      return rig;
    }

    /// Every focusable tile is wholly on screen, without scrolling.
    void allOnScreen(WidgetTester t) {
      final cards = find.byType(FocusCard);
      expect(cards, findsWidgets);
      for (final e in cards.evaluate()) {
        final r = t.getRect(find.byWidget(e.widget));
        expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(0.01, 0.01)), isTrue,
            reason: '$r is off the 960x540 screen');
      }
    }

    testWidgets('the QR view fits: code, steps and the phone fallback', (t) async {
      await qr(t);
      final code = t.getRect(find.byKey(TelegramKeys.qr));
      expect(code.height, inInclusiveRange(540 * 0.3, 540 * 0.45));
      expect(find.textContaining('Link Desktop Device'), findsOneWidget);
      allOnScreen(t);
      // Focus starts on the fallback.
      expect(FocusManager.instance.primaryFocus!.rect.overlaps(t.getRect(find.byKey(TelegramKeys.usePhone))), isTrue);
    });

    testWidgets('the phone view fits and D-pad goes back to the QR code', (t) async {
      final rig = await qr(t);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byKey(TelegramKeys.enterPhone), findsOneWidget);
      allOnScreen(t);
      // TDLib renews the QR link meanwhile: the phone view stays.
      await t.runAsync(() async {
        rig.fake.emitAuth(const TgAuthWaitQr('tg://login?token=renewed'));
        await pumpEventQueue(times: 10);
      });
      await t.pumpAndSettle();
      expect(find.byKey(TelegramKeys.enterPhone), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus!.rect.overlaps(t.getRect(find.byKey(TelegramKeys.useQr))), isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byKey(TelegramKeys.qr), findsOneWidget);
      expect(rig.service.state.value.qrLink, 'tg://login?token=renewed');
      allOnScreen(t);
    });
  });

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

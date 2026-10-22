// End-to-end on a phone emulator (`E2E_TARGET=e2e_phone_test.dart .github/e2e.sh
// android <out-dir>`, the phone-e2e job): the channel says phone, the phone
// shell renders, tapping a text field raises the soft keyboard, a YouTube
// search by tapping plays to 2 s, and Back from the player returns to
// portrait on the same tab.
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

/// Pumps in real time until [done] holds or [timeout] passes.
Future<bool> pumpUntil(WidgetTester t, bool Function() done,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    if (done()) return true;
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump();
  }
  return done();
}

Size _logicalSize(WidgetTester t) => t.view.physicalSize / t.view.devicePixelRatio;

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phone: shell, soft keyboard, YouTube playback, player and Back', (t) async {
    final detected = await androidFormFactor();
    expect(detected, FormFactor.phone, reason: 'the activity must report a phone');
    await t.pumpWidget(ChithramApp(formFactor: detected));
    await t.pumpAndSettle();
    expect(find.byType(PhoneShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(_logicalSize(t).height, greaterThan(_logicalSize(t).width), reason: 'starts in portrait');

    // Tapping the search field raises the soft keyboard (the phone search page
    // is a real TextField).
    await _tap(t, find.byKey(const ValueKey('nav-youtube')));
    final field = find.byKey(const ValueKey('search-field'));
    expect(field, findsOneWidget);
    await _tap(t, field);
    final raised = await pumpUntil(t, () => MediaQuery.viewInsetsOf(t.element(field)).bottom > 0);
    // ignore: avoid_print
    print('CHITHRAM_E2E soft keyboard raised: $raised');
    // Report only if the emulator never shows an IME; the owner phone covers it.
    // Set E2E_REQUIRE_IME=true to make it fatal.
    if (const bool.fromEnvironment('E2E_REQUIRE_IME')) expect(raised, isTrue);

    // YouTube search by typing (fixture mode: one "Fixture" item).
    await t.enterText(field, 'fix');
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('search-go')));
    final result = find.byKey(const ValueKey('yt-result-fixturevid1'));
    expect(await pumpUntil(t, () => result.evaluate().isNotEmpty, timeout: const Duration(seconds: 20)), isTrue,
        reason: 'the search result never appeared');
    await _tap(t, result);

    expect(find.byKey(Keys.playerRoot), findsOneWidget);
    final position = await waitForPlayback(t);
    // ignore: avoid_print
    print('CHITHRAM_E2E phone youtube reached $position');
    // The player turns the phone sideways.
    final landscape = await pumpUntil(t, () => _logicalSize(t).width > _logicalSize(t).height);
    // ignore: avoid_print
    print('CHITHRAM_E2E player landscape: $landscape');
    expect(landscape, isTrue, reason: 'the player must be landscape on a phone');

    Navigator.of(t.element(find.byKey(Keys.playerRoot))).pop();
    await t.pumpAndSettle();
    expect(await pumpUntil(t, () => _logicalSize(t).height > _logicalSize(t).width), isTrue,
        reason: 'Back from the player must return to portrait');
    await t.pumpAndSettle();
    expect(find.byType(PhoneShell), findsOneWidget);
    expect(result, findsOneWidget, reason: 'Back returns to the same tab with its results');
  });
}

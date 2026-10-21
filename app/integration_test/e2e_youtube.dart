// End-to-end: YouTube search and playback in fixture mode (E2E_BASE is set, so
// search finds one "Fixture" item and resolve returns video.mp4 + audio.m4a).
// Run through e2e_all_test.dart. The real-network check is
// e2e_youtube_live_test.dart (non-blocking).
import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Enter, not Select: the Linux test key map has no Select.
/// Types [text] on the on-screen keyboard with the D-pad, searches, and opens
/// the [result] tile. Starts on the rail.
Future<void> searchAndOpen(WidgetTester t, String text, Finder result) async {
  await press(t, LogicalKeyboardKey.arrowDown); // Search
  await press(t, LogicalKeyboardKey.arrowRight); // into the keyboard
  for (final c in text.split('')) {
    await dpadTo(t, find.byKey(ValueKey('key-${c == ' ' ? 'space' : c}')));
    await press(t, LogicalKeyboardKey.enter);
  }
  expect(t.widget<Text>(find.byKey(const ValueKey('search-query'))).data, text);
  await dpadTo(t, find.byKey(const ValueKey('search-go')));
  await press(t, LogicalKeyboardKey.enter);

  for (var i = 0; i < 80 && result.evaluate().isEmpty; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await t.pump();
  }
  expect(result, findsWidgets, reason: 'the search result never appeared');
  await dpadTo(t, result);
  await press(t, LogicalKeyboardKey.enter);
}

void youtubeE2e() {
  group('youtube', () {
    testWidgets(
      'search "fix", open the result, it plays to 2 s, Back returns to the result',
      (t) async {
        await t.pumpWidget(const ChithramApp());
        await t.pumpAndSettle();
        await searchAndOpen(
          t,
          'fix',
          find.byKey(const ValueKey('yt-result-fixturevid1')),
        );

        expect(find.byKey(Keys.playerRoot), findsOneWidget);
        final position = await waitForPlayback(t);
        // ignore: avoid_print
        print('CHITHRAM_E2E youtube reached $position');

        Navigator.of(t.element(find.byKey(Keys.playerRoot))).pop();
        await t.pumpAndSettle();
        expectFocusInApp('after closing the player');
        expect(
          find.byKey(const ValueKey('yt-result-fixturevid1')),
          findsOneWidget,
        );
      },
    );
  });
}

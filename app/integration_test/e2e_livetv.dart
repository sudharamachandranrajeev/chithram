// End-to-end: Live TV. Run through e2e_all_test.dart (see .github/e2e.sh).
// Adds the fixture playlist ($E2E_BASE/playlist.m3u: an HLS channel, movie.mkv
// and a dead URL) through the UI, plays the first channel and zaps to the next.
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/livetv/add_playlist.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/iptv.dart';

import 'support.dart';

void livetvE2e() {
  group('livetv', () {
    testWidgets('add the fixture playlist, play, zap, Back keeps focus', (t) async {
      final iptv = IptvService(store: InMemoryIptvStore());
      await t.pumpWidget(ChithramApp(services: AppServices.memory(iptv: iptv)));
      await t.pumpAndSettle();

      // Rail: Home -> Search -> Live TV (a tap on the rail does not switch section).
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      // The page loads its sources on real I/O ticks.
      for (var i = 0; i < 40 && find.byKey(LiveTvKeys.addPlaylist).evaluate().isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 100));
      }
      // Nothing was downloaded just by opening the section.
      expect(await iptv.sources(), isEmpty);

      await t.tap(find.byKey(LiveTvKeys.addPlaylist));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(Keys.textEntryField), '$e2eBase/playlist.m3u');
      await t.tap(find.byKey(Keys.textEntryOk));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Keys.textEntryOk)); // keep the suggested name
      // The download runs on real I/O.
      for (var i = 0; i < 40 && (await t.runAsync(iptv.snapshot))!.channels.values.expand((e) => e).isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      }
      await t.pumpAndSettle();
      expect(find.text('E2E HLS'), findsOneWidget);

      await t.tap(find.text('E2E HLS'));
      await t.pump();
      await waitForPlayback(t);

      // Down zaps to the next channel.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      await waitForPlayback(t);

      Navigator.of(t.element(find.byKey(Keys.playerRoot))).pop();
      await t.pumpAndSettle();
      expectFocusInApp('after closing the player');
    });
  });
}

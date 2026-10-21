// End-to-end: torrents. Run through e2e_all_test.dart (see .github/e2e.sh).
// Needs E2E_MAGNET (movie.mkv, seeded on E2E_PEER) and the torrent library.
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/torrents/network_dialog.dart';
import 'package:chithram/src/features/torrents/torrent_files_page.dart';
import 'package:chithram/src/features/torrents/torrent_logic.dart';
import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:chithram/src/ui/sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Pumps in real time until [finder] matches.
Future<void> _pumpUntil(WidgetTester t, Finder finder, {Duration timeout = const Duration(seconds: 60)}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('$finder did not appear within $timeout');
}

void torrentE2e() {
  group('torrent', () {
    testWidgets('magnet, direct, file list, plays, Back removes the torrent', (t) async {
      final services = AppServices.memory();
      await t.pumpWidget(ChithramApp(services: services));
      await t.pumpAndSettle();
      expect(services.torrents.guard.needsChoice, isTrue, reason: 'the choice starts unset');

      // D-pad: down the rail to Torrents, then into the section. (A tap on a
      // rail item focuses the section it replaces, not the one tapped.)
      for (var i = 0; i < Section.torrents.index; i++) {
        await press(t, LogicalKeyboardKey.arrowDown);
      }
      await press(t, LogicalKeyboardKey.arrowRight);
      expect(find.byKey(TorrentKeys.pasteMagnet), findsOneWidget);
      await t.tap(find.byKey(TorrentKeys.pasteMagnet));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(Keys.textEntryField), e2eMagnet);
      await t.tap(find.byKey(Keys.textEntryOk));
      await t.pumpAndSettle();

      // The first torrent action asks how to connect.
      expect(find.byKey(NetworkDialogKeys.direct), findsOneWidget);
      expect(find.textContaining('see your IP address'), findsOneWidget);
      await t.tap(find.byKey(NetworkDialogKeys.direct));
      await t.pumpAndSettle();
      expect(services.torrents.guard.choice.mode, NetworkMode.direct);

      await _pumpUntil(t, find.byType(TorrentFilesPage));
      await t.pumpAndSettle();
      final id = services.torrents.active!.id;
      expect(find.text('movie.mkv'), findsOneWidget);

      await t.tap(find.text('movie.mkv'));
      await t.pump();
      final position = await waitForPlayback(t, timeout: const Duration(seconds: 20));
      // ignore: avoid_print
      print('CHITHRAM_E2E torrent reached $position');
      expect(await services.torrents.statsFor(id), isNotNull);

      Navigator.of(t.element(find.byKey(Keys.playerRoot))).pop();
      await t.pumpAndSettle();
      // Closing the player removed the torrent and the file list with it.
      expect(services.torrents.active, isNull);
      expect(find.byType(TorrentFilesPage), findsNothing);
      await t.runAsync(() async {
        await expectLater(services.torrents.statsFor(id), throwsA(anything));
      });
      expectFocusInApp('after closing the torrent player');
    }, skip: e2eMagnet.isEmpty);
  });
}

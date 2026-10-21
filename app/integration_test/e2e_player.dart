// End-to-end: the player route. Run through e2e_all_test.dart (see .github/e2e.sh).
import 'dart:async';

import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:chithram/src/ui/shell.dart';
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void playerE2e() {
  group('player', () {
    testWidgets('plays the merged fixture to 2 s and closes', (t) async {
      await t.pumpWidget(const ChithramApp());
      await t.pumpAndSettle();
      final context = t.element(find.byType(Shell));
      final closed = Completer<void>();
      unawaited(openPlayer(
        context,
        PlayRequest(
          itemId: 'url:e2e',
          title: 'Merged fixture',
          resolve: () async => const MediaSpec(videoUrl: '$e2eBase/video.mp4', audioUrl: '$e2eBase/audio.m4a'),
          onClose: () async => closed.complete(),
        ),
      ));
      await t.pump();
      final position = await waitForPlayback(t);
      // ignore: avoid_print
      print('CHITHRAM_E2E player reached $position');

      Navigator.of(t.element(find.byKey(Keys.playerRoot))).pop();
      await t.pumpAndSettle();
      await t.runAsync(() => closed.future.timeout(const Duration(seconds: 10)));
      expectFocusInApp('after closing the player');
    });
  });
}

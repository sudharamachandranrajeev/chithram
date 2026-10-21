// End-to-end: the player route. Run through e2e_all_test.dart (see .github/e2e.sh).
import 'dart:async';

import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/player/player_keys.dart';
import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:chithram/src/ui/shell.dart';
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

PlayRequest _fixture(String id, {Future<void> Function()? onClose, String query = ''}) => PlayRequest(
      itemId: id,
      title: 'Merged fixture',
      // The query is never logged: the Android job checks CHITHRAM_OPEN lines for it.
      resolve: () async =>
          MediaSpec(videoUrl: '$e2eBase/video.mp4$query', audioUrl: '$e2eBase/audio.m4a$query'),
      onClose: onClose,
    );

Future<void> _key(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pump();
}

Future<void> _back(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

void playerE2e() {
  group('player', () {
    testWidgets('plays the merged fixture, pauses, seeks and closes', (t) async {
      await t.pumpWidget(const ChithramApp());
      await t.pumpAndSettle();
      final context = t.element(find.byType(Shell));
      final closed = Completer<void>();
      final watch = Stopwatch()..start();
      unawaited(openPlayer(context, _fixture('url:e2e', query: '?token=secret', onClose: () async => closed.complete())));
      await t.pump();
      final position = await waitForPlayback(t);
      // ignore: avoid_print
      print('CHITHRAM_E2E player reached $position after ${watch.elapsed}');
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)), reason: 'open to 2 s');

      // Center pauses and resumes.
      await _key(t, LogicalKeyboardKey.select);
      await settle(t, const Duration(seconds: 1));
      final paused = playerPosition(t);
      await settle(t, const Duration(seconds: 2));
      expect(playerPosition(t), paused, reason: 'position moved while paused');
      await _key(t, LogicalKeyboardKey.select);
      await waitForPlayback(t, atLeast: paused + const Duration(seconds: 1));

      // Right seeks ahead by 10 s.
      await _key(t, LogicalKeyboardKey.arrowRight);
      await waitForPlayback(t, atLeast: const Duration(seconds: 10));

      await _back(t);
      await t.runAsync(() => closed.future.timeout(const Duration(seconds: 10)));
      expectFocusInApp('after closing the player');
    });

    testWidgets('a missing file shows the error panel', (t) async {
      await t.pumpWidget(const ChithramApp());
      await t.pumpAndSettle();
      final context = t.element(find.byType(Shell));
      unawaited(openPlayer(
        context,
        PlayRequest(
          itemId: 'url:e2e-404',
          title: 'Missing',
          resolve: () async => const MediaSpec(videoUrl: '$e2eBase/no-such-file.mp4'),
        ),
      ));
      final watch = Stopwatch()..start();
      while (find.byKey(Keys.playerError).evaluate().isEmpty) {
        if (watch.elapsed > const Duration(seconds: 30)) fail('no error panel for a 404');
        await settle(t, const Duration(milliseconds: 250));
      }
      expect(find.byKey(PlayerKeys.retry), findsOneWidget);
      await _back(t);
      expectFocusInApp('after closing the error panel');
    });

    testWidgets('reopening after about 40 s offers to resume', (t) async {
      await t.pumpWidget(const ChithramApp());
      await t.pumpAndSettle();
      final context = t.element(find.byType(Shell));
      unawaited(openPlayer(context, _fixture('url:e2e-resume')));
      await t.pump();
      await waitForPlayback(t);
      for (var i = 0; i < 4; i++) {
        await _key(t, LogicalKeyboardKey.arrowRight);
        await settle(t, const Duration(milliseconds: 500));
      }
      final at = await waitForPlayback(t, atLeast: const Duration(seconds: 40));
      await _back(t);
      await settle(t, const Duration(milliseconds: 500));

      unawaited(openPlayer(t.element(find.byType(Shell)), _fixture('url:e2e-resume')));
      await t.pump();
      final watch = Stopwatch()..start();
      while (find.byKey(PlayerKeys.resume).evaluate().isEmpty) {
        if (watch.elapsed > const Duration(seconds: 10)) fail('no resume offer after closing at $at');
        await settle(t, const Duration(milliseconds: 250));
      }
      expect(find.textContaining('Resume from 0:4'), findsOneWidget, reason: 'closed at $at');
      await _back(t);
    });
  });
}

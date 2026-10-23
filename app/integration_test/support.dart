import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram/src/ui/common/sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sends one key and lets the animations finish.
Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pumpAndSettle(const Duration(milliseconds: 50));
}

/// In-memory services with YouTube answered by fixtures: Home has rails of
/// "Fixture" videos and nothing touches the network.
AppServices fixtureServices() =>
    AppServices.memory(youtube: YouTubeService(browse: FixtureBrowse(''), resolver: FixtureResolver('')));

String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

/// Focus is on a real node that is part of the app (never lost, never only a scope).
void expectFocusInApp([String? when]) {
  final f = FocusManager.instance.primaryFocus;
  expect(f, isNotNull, reason: 'primaryFocus is null ${when ?? ''}');
  expect(f, isNot(isA<FocusScopeNode>()), reason: 'only a scope has focus ${when ?? ''}');
  expect(f!.context, isNotNull, reason: 'focused node is detached ${when ?? ''}');
  expect(f.context!.mounted, isTrue, reason: 'focused node is unmounted ${when ?? ''}');
  expect(f.context!.findAncestorWidgetOfExactType<MaterialApp>(), isNotNull,
      reason: 'focus is outside the app ${when ?? ''}');
}

String railLabel(Section s) => 'rail ${s.label}';

/// Moves focus to [target] using only D-pad presses (geometry based).
Future<void> dpadTo(WidgetTester t, Finder target) async {
  for (var i = 0; i < 80; i++) {
    // Re-read every time: focusing scrolls the page.
    final goal = t.getRect(target).center;
    final cur = FocusManager.instance.primaryFocus!.rect;
    final delta = goal - cur.center;
    if (delta.distance < 4) return;
    final LogicalKeyboardKey key;
    if (delta.dy.abs() > cur.height / 2) {
      key = delta.dy > 0 ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp;
    } else {
      key = delta.dx > 0 ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;
    }
    await press(t, key);
  }
  fail('D-pad never reached $target (focus: ${focusLabel()})');
}

/// Fixture server for the end-to-end suite (`.github/e2e.sh host-services`).
const e2eBase = String.fromEnvironment('E2E_BASE', defaultValue: 'http://127.0.0.1:8000');

/// Magnet of `movie.mkv`, seeded on [e2ePeer].
const e2eMagnet = String.fromEnvironment('E2E_MAGNET');
const e2ePeer = String.fromEnvironment('E2E_PEER', defaultValue: '127.0.0.1:16881');

/// Parses the player's `m:ss` / `h:mm:ss` position text.
Duration parsePosition(String text) {
  final parts = text.split(':').map(int.parse).toList();
  return switch (parts.length) {
    2 => Duration(minutes: parts[0], seconds: parts[1]),
    3 => Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]),
    _ => throw FormatException('not a position: $text'),
  };
}

/// Pumps in real time until the open player route shows a position of at
/// least [atLeast]. Fails after [timeout], and at once if the player shows an
/// error.
Future<Duration> waitForPlayback(
  WidgetTester t, {
  Duration atLeast = const Duration(seconds: 2),
  Duration timeout = const Duration(seconds: 30),
}) async {
  final watch = Stopwatch()..start();
  var last = Duration.zero;
  while (watch.elapsed < timeout) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump();
    final errorText = find.byKey(Keys.playerError);
    if (errorText.evaluate().isNotEmpty) {
      fail('player error after ${watch.elapsed}: ${t.widget<Text>(errorText).data}');
    }
    final position = find.byKey(Keys.playerPosition);
    if (position.evaluate().isNotEmpty) {
      last = parsePosition(t.widget<Text>(position).data!);
      if (last >= atLeast) return last;
    }
  }
  fail('playback did not reach $atLeast in $timeout (last position $last)');
}

/// Real-time wait that keeps the frames coming.
Future<void> settle(WidgetTester t, Duration d) async {
  await t.runAsync(() => Future<void>.delayed(d));
  await t.pump();
}

/// The player's current position text.
Duration playerPosition(WidgetTester t) =>
    parsePosition(t.widget<Text>(find.byKey(Keys.playerPosition)).data!);

// Fixture endpoints of the e2e and perf runs (.github/e2e.sh writes the
// defines; empty when the suite runs without the fixture server).
const e2eTmdbBase = String.fromEnvironment('E2E_TMDB_BASE');
const e2eTorznab = String.fromEnvironment('E2E_TORZNAB');
const e2ePluginRepo = String.fromEnvironment('E2E_PLUGIN_REPO');

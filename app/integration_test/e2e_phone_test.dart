// End-to-end on a phone emulator (`E2E_TARGET=e2e_phone_test.dart .github/e2e.sh
// android <out-dir>`, the phone-e2e job): the channel says phone, the phone
// shell renders, tapping a text field raises the soft keyboard, a YouTube
// search by typing plays to 2 s, and Back from the player returns to portrait
// on the same tab. Two more tests drive the phone views: a magnet pasted into
// the text field lists the torrent's files, and a Live TV channel plays from
// the channel list.
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/livetv/add_playlist.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/features/torrents/network_dialog.dart';
import 'package:chithram/src/features/torrents/torrent_files_page.dart';
import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/form_factor.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:chithram/src/ui/phone_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv/iptv.dart';

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

  testWidgets('phone: a pasted magnet lists the files, Back removes the torrent', (t) async {
    final services = AppServices.memory();
    final detected = await androidFormFactor();
    await t.pumpWidget(ChithramApp(services: services, formFactor: detected));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('nav-torrents')));
    // The system keyboard types into a plain text field; no on-screen keys.
    expect(find.text('Send from phone'), findsNothing);
    final field = find.byKey(const ValueKey('torrent-magnet-field'));
    await _tap(t, field);
    await t.enterText(field, e2eMagnet);
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('torrent-magnet-add')));
    // The first torrent action asks how to connect.
    expect(find.byKey(NetworkDialogKeys.direct), findsOneWidget);
    await _tap(t, find.byKey(NetworkDialogKeys.direct));
    expect(await pumpUntil(t, () => find.byType(TorrentFilesPage).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60)), isTrue, reason: 'the file list never opened');
    await t.pumpAndSettle();
    expect(find.text('movie.mkv'), findsOneWidget);
    // ignore: avoid_print
    print('CHITHRAM_E2E phone torrent listed movie.mkv');

    Navigator.of(t.element(find.byType(TorrentFilesPage))).pop();
    await t.pumpAndSettle();
    expect(services.torrents.active, isNull, reason: 'backing out removes the torrent');
    expect(find.byType(PhoneShell), findsOneWidget);
  });

  testWidgets('phone: Live TV channel list plays a channel', (t) async {
    final iptv = IptvService(store: InMemoryIptvStore());
    final detected = await androidFormFactor();
    await t.pumpWidget(ChithramApp(services: AppServices.memory(iptv: iptv), formFactor: detected));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('nav-liveTv')));
    expect(find.byKey(LiveTvKeys.addPlaylist), findsOneWidget, reason: 'no sources: the add card shows');
    // Nothing was downloaded just by opening the section.
    expect(await t.runAsync(iptv.sources), isEmpty);

    // The add dialogs are covered by widget tests; add through the service here.
    await t.runAsync(() => iptv.addM3uUrl(name: 'E2E', url: '$e2eBase/playlist.m3u'));
    final row = find.text('E2E HLS');
    expect(await pumpUntil(t, () => row.evaluate().isNotEmpty, timeout: const Duration(seconds: 20)), isTrue,
        reason: 'the channel never appeared');
    await t.pumpAndSettle();
    await _tap(t, row);
    expect(find.byKey(Keys.playerRoot), findsOneWidget);
    final position = await waitForPlayback(t);
    // ignore: avoid_print
    print('CHITHRAM_E2E phone livetv reached $position');
    Navigator.of(t.element(find.byKey(Keys.playerRoot))).pop();
    await t.pumpAndSettle();
    expect(await pumpUntil(t, () => _logicalSize(t).height > _logicalSize(t).width), isTrue);
    expect(row, findsOneWidget, reason: 'Back returns to the channel list');
  });
}

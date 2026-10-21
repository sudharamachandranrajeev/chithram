// End-to-end: receive. Run through e2e_all_test.dart (see .github/e2e.sh).
//
// An in-process LocalSend sender talks to the app's receiver over loopback
// (real TLS, real HTTP, the real prompt and intake path).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/receive/receive_keys.dart';
import 'package:chithram/src/features/receive/receive_page.dart';
import 'package:chithram/src/features/receive/receive_service.dart';
import 'package:chithram/src/features/torrents/torrent_service.dart';
import 'package:chithram/src/intake/summary.dart';
import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:chithram/src/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_rx/localsend_rx.dart';
import 'package:localsend_rx/testing.dart';
import 'package:torrent/torrent.dart';

import 'support.dart';

const _port = 53330;
const _btih = '0123456789abcdef0123456789abcdef01234567';

/// Records what the intake path asks of the torrent engine; no engine runs.
class _RecordingTorrents extends TorrentService {
  _RecordingTorrents(AppServices base) : super(paths: base.paths, prefs: base.prefs);

  final added = <String>[];
  final opened = <TorrentInfo>[];

  @override
  Future<bool> ensureNetworkChoice(BuildContext c) async => true;

  @override
  Future<TorrentInfo> addMagnet(String magnet) async {
    added.add(magnet);
    return TorrentInfo(id: 7, name: 'Fixture', files: const []);
  }

  @override
  Future<void> openFiles(BuildContext c, TorrentInfo t) async => opened.add(t);
}

void receiveE2e() {
  group('receive', () {
    late _RecordingTorrents torrents;
    late AppServices services;

    Future<void> openScreenAndWait(WidgetTester t) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey<NavigatorState>();
      final base = AppServices.memory(navigatorKey: key);
      torrents = _RecordingTorrents(base);
      final receive = ReceiveService(
        navigatorKey: key,
        paths: base.paths,
        prefs: base.prefs,
        testConfig: (c) => LsReceiverConfig(
          alias: c.alias,
          port: _port,
          allowLoopback: true,
          multicast: false,
          bindAddresses: [InternetAddress.loopbackIPv4],
        ),
      );
      services = AppServices.memory(navigatorKey: key, torrents: torrents, receive: receive);
      await t.pumpWidget(ChithramApp(services: services));
      await t.pumpAndSettle();
      unawaited(openReceive(t.element(find.byType(Shell))));
      await t.pumpAndSettle();
      for (var i = 0; i < 240 && services.receive.state.value.status != ReceiveStatus.listening; i++) {
        // The first run makes a certificate: seconds on a slow device.
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await t.pump();
        expect(services.receive.state.value.status, isNot(ReceiveStatus.error), reason: services.receive.state.value.error);
      }
      expect(services.receive.state.value.status, ReceiveStatus.listening);
    }

    Future<void> waitFor(WidgetTester t, Finder f) async {
      for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }
      expect(f, findsOneWidget);
    }

    /// Waits for a real network future while the test clock stands still.
    Future<T> realAwait<T>(WidgetTester t, Future<T> f) async {
      var done = false;
      unawaited(f.then((_) => done = true, onError: (_) => done = true));
      for (var i = 0; i < 200 && !done; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      return f;
    }

    LsTestSender sender() => LsTestSender(host: '127.0.0.1', port: _port, alias: 'Test phone', model: 'Fixture phone');

    testWidgets('a magnet from a phone: prompt, then the torrent file list, never the player', (t) async {
      await openScreenAndWait(t);
      final magnet = 'magnet:?xt=urn:btih:$_btih&dn=Fixture';
      final sent = sender().sendText(magnet);

      await waitFor(t, find.byKey(ReceiveKeys.prompt));
      final prompt = find.byKey(ReceiveKeys.prompt);
      expect(find.descendant(of: prompt, matching: find.textContaining('Test phone')), findsOneWidget);
      expect(find.descendant(of: prompt, matching: find.textContaining('127.0.0.1')), findsOneWidget);
      expect(find.descendant(of: prompt, matching: find.textContaining('magnet:?xt=urn:btih:$_btih', findRichText: true)), findsOneWidget);
      expect(find.text('Open torrent'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(torrents.added, isEmpty, reason: 'nothing happens before the user chooses');

      await t.tap(find.byKey(ReceiveKeys.accept));
      expect(await realAwait(t, sent), 204);
      await t.pumpAndSettle();

      expect(torrents.added, [magnet]);
      expect(torrents.opened.single.id, 7);
      expect(find.byKey(Keys.playerRoot), findsNothing);
      expect(find.byType(AlertDialog), findsNothing, reason: 'the prompt was the only confirmation');

      services.navigatorKey.currentState!.pop();
      await t.pumpAndSettle();
      expectFocusInApp('after the receive screen closes');
    });

    testWidgets('credentials are masked, the host is shown, Reject sends nothing on', (t) async {
      await openScreenAndWait(t);
      final sent = sender().sendText('https://user:hunter2@tv.example.org/list.m3u');
      await waitFor(t, find.byKey(ReceiveKeys.prompt));
      expect(find.textContaining('hunter2', findRichText: true), findsNothing);
      expect(find.textContaining('tv.example.org', findRichText: true), findsOneWidget);
      expect(find.byType(IntakeSummary), findsOneWidget);
      await t.tap(find.byKey(ReceiveKeys.reject));
      expect(await realAwait(t, sent), 403);
      await t.pumpAndSettle();
      expect(find.byKey(ReceiveKeys.prompt), findsNothing);
      expect(torrents.added, isEmpty);
    });

    testWidgets('a picture is refused without asking', (t) async {
      await openScreenAndWait(t);
      final s = sender();
      final png = LsTestSender.binaryFile('p1', 'photo.png', Uint8List(32), type: 'image/png');
      final status = (await realAwait(t, s.prepare([png]))).status;
      expect(status, 403);
      await t.pump();
      expect(find.byKey(ReceiveKeys.prompt), findsNothing);
    });
  });
}

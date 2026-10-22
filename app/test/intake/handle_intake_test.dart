import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/features/torrents/torrent_service.dart';
import 'package:chithram/src/intake/fetch.dart';
import 'package:chithram/src/intake/intake.dart';
import 'package:chithram/src/intake/summary.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/iptv.dart';
import 'package:torrent/torrent.dart';

class _Torrents extends TorrentService {
  _Torrents(AppServices base) : super(paths: base.paths, prefs: base.prefs);

  final added = <String>[];
  final addedBytes = <Uint8List>[];
  final opened = <TorrentInfo>[];

  @override
  Future<bool> ensureNetworkChoice(BuildContext c) async => true;

  @override
  Future<TorrentInfo> addMagnet(String magnet) async {
    added.add(magnet);
    return const TorrentInfo(id: 1, name: 'x', files: []);
  }

  @override
  Future<TorrentInfo> addTorrentBytes(Uint8List b) async {
    addedBytes.add(b);
    return const TorrentInfo(id: 2, name: 'y', files: []);
  }

  @override
  Future<void> openFiles(BuildContext c, TorrentInfo t) async => opened.add(t);
}

class _Iptv extends IptvService {
  _Iptv() : super(store: InMemoryIptvStore());

  final playlists = <String?>[];

  @override
  Future<void> openAddPlaylist(BuildContext c, {String? url}) async => playlists.add(url);
}

const _magnet = 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Film';

void main() {
  late _Torrents torrents;
  late _Iptv iptv;
  late BuildContext context;
  IntakeFetch? savedFetch;

  setUp(() => savedFetch = intakeFetch);
  tearDown(() {
    intakeFetch = savedFetch!;
    IntakeHooks.search = null;
  });

  Future<void> pump(WidgetTester t) async {
    final base = AppServices.memory();
    torrents = _Torrents(base);
    iptv = _Iptv();
    final services = AppServices.memory(torrents: torrents, iptv: iptv, navigatorKey: base.navigatorKey);
    await t.pumpWidget(AppServicesScope(
      services: services,
      child: MaterialApp(
        navigatorKey: services.navigatorKey,
        home: Builder(builder: (c) {
          context = c;
          return const Scaffold(body: SizedBox());
        }),
      ),
    ));
  }

  testWidgets('a magnet asks first, then opens the torrent file list and never the player', (t) async {
    await pump(t);
    unawaited(handleIntake(context, TextPayload(_magnet, from: 'Phone')));
    await t.pumpAndSettle();
    expect(find.text('From Phone'), findsOneWidget);
    expect(find.text('Open torrent'), findsOneWidget);
    expect(torrents.added, isEmpty, reason: 'nothing happens before the user chooses');
    await t.tap(find.text('Open torrent'));
    await t.pumpAndSettle();
    expect(torrents.added, [_magnet]);
    expect(torrents.opened.single.id, 1);
    expect(find.byKey(Keys.playerRoot), findsNothing);
  });

  testWidgets('Cancel routes nowhere', (t) async {
    await pump(t);
    unawaited(handleIntake(context, TextPayload(_magnet)));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(torrents.added, isEmpty);
  });

  testWidgets('confirmed skips the dialog', (t) async {
    await pump(t);
    await handleIntake(context, TextPayload(_magnet), confirmed: true);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(torrents.added, [_magnet]);
  });

  testWidgets('dangerous schemes are plain text: shown, no action, nothing routed', (t) async {
    await pump(t);
    for (final text in ['javascript:alert(1)', 'file:///etc/passwd', 'content://x/y.mp4', 'intent://x#Intent;end']) {
      unawaited(handleIntake(context, TextPayload(text)));
      await t.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing, reason: text);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
    }
    // Even when the caller claims it was confirmed.
    await handleIntake(context, TextPayload('file:///etc/passwd'), confirmed: true);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(Keys.playerRoot), findsNothing);
  });

  testWidgets('plain text gets "Search for this text" once search is hooked up', (t) async {
    await pump(t);
    String? searched;
    IntakeHooks.search = (c, text) async => searched = text;
    unawaited(handleIntake(context, TextPayload('big buck bunny')));
    await t.pumpAndSettle();
    await t.tap(find.text('Search for this text'));
    await t.pumpAndSettle();
    expect(searched, 'big buck bunny');
  });

  testWidgets('credentials in a link are masked and the host is bold', (t) async {
    await pump(t);
    unawaited(handleIntake(context, TextPayload('https://user:secret@tv.example.org/list.m3u')));
    await t.pumpAndSettle();
    expect(find.textContaining('secret', findRichText: true), findsNothing);
    final text = t.widget<Text>(find.descendant(of: find.byType(IntakeSummary), matching: find.byType(Text)));
    final host = (text.textSpan! as TextSpan).children!.cast<TextSpan>().firstWhere((s) => s.text == 'tv.example.org');
    expect(host.style?.fontWeight, FontWeight.w800);
    expect(find.text('Add playlist'), findsOneWidget);
  });

  testWidgets('long content is cut to 200 characters', (t) async {
    await pump(t);
    unawaited(handleIntake(context, TextPayload('x' * 500)));
    await t.pumpAndSettle();
    expect(find.text('${'x' * 200}...', findRichText: true), findsOneWidget);
  });

  testWidgets('a .torrent link is fetched with a 2 MiB cap and opened from its bytes', (t) async {
    await pump(t);
    int? cap;
    intakeFetch = (uri, {required maxBytes, required timeout, truncate = false}) async {
      cap = maxBytes;
      return Uint8List.fromList(ascii.encode('d4:infod4:name1:aee'));
    };
    await handleIntake(context, TextPayload('https://example.org/film.torrent'), confirmed: true);
    await t.pumpAndSettle();
    expect(cap, 2 * 1024 * 1024);
    expect(torrents.addedBytes, hasLength(1));
    expect(torrents.opened.single.id, 2);
  });

  testWidgets('a .torrent link that is not a torrent is refused', (t) async {
    await pump(t);
    intakeFetch = (uri, {required maxBytes, required timeout, truncate = false}) async => Uint8List.fromList(ascii.encode('<html>'));
    await handleIntake(context, TextPayload('https://example.org/film.torrent'), confirmed: true);
    await t.pumpAndSettle();
    expect(find.text('That link is not a torrent file'), findsOneWidget);
    expect(torrents.addedBytes, isEmpty);
  });

  testWidgets('an .m3u8 list of channels becomes a playlist, not a stream', (t) async {
    await pump(t);
    intakeFetch = (uri, {required maxBytes, required timeout, truncate = false}) async => Uint8List.fromList(ascii.encode(
        '#EXTM3U\n#EXTINF:-1,One\nhttp://a/1.ts\n#EXTINF:-1,Two\nhttp://a/2.ts\n'));
    await handleIntake(context, TextPayload('https://example.org/list.m3u8'), confirmed: true);
    await t.pumpAndSettle();
    expect(iptv.playlists, ['https://example.org/list.m3u8']);
  });

  testWidgets('a .torrent file payload goes to addTorrentBytes', (t) async {
    await pump(t);
    final bytes = Uint8List.fromList(ascii.encode('d4:infod4:name1:aee'));
    unawaited(handleIntake(context, TorrentFilePayload(bytes, 'film.torrent', from: 'Phone')));
    await t.pumpAndSettle();
    await t.tap(find.text('Open torrent'));
    await t.pumpAndSettle();
    expect(torrents.addedBytes.single, bytes);
  });
}

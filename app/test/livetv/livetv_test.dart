import 'dart:async';
import 'dart:convert';

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/livetv/add_playlist.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/features/livetv/livetv_page.dart';
import 'package:chithram/src/features/livetv/suggestions.dart';
import 'package:chithram/src/ui/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/iptv.dart';

/// Records every request; answers from [routes] (matched on URL prefix).
class RecordingHttp implements IptvHttp {
  RecordingHttp([this.routes = const {}]);
  final Map<String, String> routes;
  final requests = <Uri>[];

  @override
  Future<IptvResponse> open(Uri uri,
      {Map<String, String> headers = const {}, Duration timeout = const Duration(seconds: 15)}) async {
    requests.add(uri);
    for (final e in routes.entries) {
      if (uri.toString().startsWith(e.key)) {
        return IptvResponse(
            status: 200,
            headers: const {},
            body: Stream.value(utf8.encode(e.value)),
            ttfb: Duration.zero);
      }
    }
    return IptvResponse(status: 404, headers: const {}, body: const Stream.empty(), ttfb: Duration.zero);
  }
}

const _playlist = '''#EXTM3U
#EXTINF:-1 tvg-id="a" group-title="News",Alpha News
http://a.example.test/a.m3u8
#EXTINF:-1 tvg-id="b" group-title="News",Beta News
http://a.example.test/b.m3u8
#EXTINF:-1 tvg-id="c" group-title="Sport",Gamma Sport
http://a.example.test/c.m3u8
''';

Future<SectionFocus> pumpPage(WidgetTester t, IptvService iptv, {Size size = const Size(1920, 1080)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final focus = SectionFocus();
  addTearDown(focus.dispose);
  await t.pumpWidget(AppServicesScope(
    services: AppServices.memory(iptv: iptv),
    child: MaterialApp(home: Scaffold(body: LiveTvPage(focus: focus))),
  ));
  await t.pumpAndSettle();
  return focus;
}

void main() {
  group('opt-in suggestions', () {
    testWidgets('nothing is fetched until the user confirms', (t) async {
      final http = RecordingHttp({
        CatalogueEndpoints.freeTvPlaylist: _playlist,
      });
      final iptv = IptvService(store: InMemoryIptvStore(), http: http);
      await pumpPage(t, iptv);

      // Empty state offers both suggestions and a playlist link.
      expect(find.byKey(LiveTvKeys.addPlaylist), findsOneWidget);
      expect(find.byKey(LiveTvKeys.suggestion(CatalogueSuggestion.iptvOrg)), findsOneWidget);
      expect(find.byKey(LiveTvKeys.suggestion(CatalogueSuggestion.freeTv)), findsOneWidget);
      expect(http.requests, isEmpty);

      // Selecting a card only explains; Cancel still fetches nothing.
      await t.tap(find.byKey(LiveTvKeys.suggestion(CatalogueSuggestion.freeTv)));
      await t.pumpAndSettle();
      expect(find.text('Add Free-TV?'), findsOneWidget);
      expect(find.textContaining('raw.githubusercontent.com'), findsOneWidget);
      expect(http.requests, isEmpty);
      await t.tap(find.byKey(LiveTvKeys.cancelAdd));
      await t.pumpAndSettle();
      expect(http.requests, isEmpty);
      expect(await iptv.sources(), isEmpty);

      // Confirming downloads from that one host and lists the channels.
      await t.tap(find.byKey(LiveTvKeys.suggestion(CatalogueSuggestion.freeTv)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(LiveTvKeys.confirmAdd));
      await t.pumpAndSettle();
      expect(http.requests.map((u) => u.host).toSet(), {'raw.githubusercontent.com'});
      expect(find.text('Alpha News'), findsOneWidget);
      expect(find.text('3 channels, updated just now'), findsOneWidget);
    });

    test('the service and registry make no request on their own', () async {
      final http = RecordingHttp();
      final iptv = IptvService(store: InMemoryIptvStore(), http: http);
      await iptv.sources();
      await iptv.snapshot();
      await iptv.searchChannels('news');
      expect(http.requests, isEmpty);
    });

    test('iptv-org suggestion keeps filters and the shared catalogue endpoint', () {
      final s = CatalogueSuggestion.iptvOrg.toSource(country: ' IN ', language: '');
      expect(s.kind, SourceKind.catalogue);
      expect(s.location, CatalogueEndpoints.iptvOrgApi);
      expect(s.filterCountry, 'IN');
      expect(s.filterLanguage, isNull);
    });
  });

  group('add playlist', () {
    test('warns only for logins over plain http', () {
      expect(sendsCredentialsInTheClear('http://u:p@h.example.test/l.m3u'), isTrue);
      expect(sendsCredentialsInTheClear('http://h.example.test/l.m3u?token=abc'), isTrue);
      expect(sendsCredentialsInTheClear('https://h.example.test/l.m3u?token=abc'), isFalse);
      expect(sendsCredentialsInTheClear('http://h.example.test/l.m3u'), isFalse);
      expect(urlWarning('ftp://h.example.test/x'), isNotNull);
      expect(urlWarning('not a url'), isNotNull);
      expect(urlWarning('https://h.example.test/x.m3u'), isNull);
    });

    test('adds an M3U URL through a fake http and groups its channels', () async {
      final http = RecordingHttp({'https://p.example.test/': _playlist});
      final iptv = IptvService(store: InMemoryIptvStore(), http: http);
      final r = await iptv.addM3uUrl(name: 'Mine', url: 'https://p.example.test/list.m3u');
      expect(r.status, RefreshStatus.updated);
      final snap = await iptv.snapshot();
      final all = snap.channels.values.expand((e) => e).toList();
      expect(all, hasLength(3));
      expect({for (final c in all) c.group}, {'News', 'Sport'});
      expect((await iptv.searchChannels('gamma')).single.name, 'Gamma Sport');
    });
  });

  group('channel list', () {
    Future<IptvService> seeded(int n, {RecordingHttp? http}) async {
      final store = InMemoryIptvStore();
      await store.saveSource(Source(id: 's', kind: SourceKind.m3uUrl, name: 'Big', location: 'https://p.example.test/x'));
      await store.replaceChannels('s', [
        for (var i = 0; i < n; i++)
          StoredChannel(
            key: 's:$i',
            sourceId: 's',
            name: 'Channel $i',
            url: 'http://c.example.test/$i.m3u8',
            group: 'G${i % 5}',
            dead: i % 7 == 3,
          ),
      ]);
      return IptvService(store: store, http: http ?? RecordingHttp());
    }

    testWidgets('10000 channels open in under a second and filter by group', (t) async {
      final iptv = await seeded(10000);
      final sw = Stopwatch()..start();
      await pumpPage(t, iptv);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(find.text('Channel 0'), findsOneWidget);
      await t.tap(find.text('G2 (2000)'));
      await t.pumpAndSettle();
      expect(find.text('Channel 2'), findsOneWidget);
      expect(find.text('Channel 0'), findsNothing);
    });

    testWidgets('holding Down for 100 presses never loses focus', (t) async {
      final iptv = await seeded(300);
      await pumpPage(t, iptv);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      for (var i = 0; i < 100; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump(const Duration(milliseconds: 30));
        final f = FocusManager.instance.primaryFocus;
        expect(f, isNotNull, reason: 'press $i');
        expect(f, isNot(isA<FocusScopeNode>()), reason: 'press $i');
        expect(f!.context, isNotNull, reason: 'press $i');
      }
    });

    testWidgets('dead channels are dimmed and labelled', (t) async {
      final iptv = await seeded(10);
      await pumpPage(t, iptv);
      expect(find.text('Not working'), findsOneWidget); // channel 3
    });

    testWidgets('remove asks first and deletes the source', (t) async {
      final iptv = await seeded(3);
      await pumpPage(t, iptv);
      await t.tap(find.byKey(const ValueKey('livetv-remove-s')));
      await t.pumpAndSettle();
      expect(await iptv.sources(), hasLength(1));
      await t.tap(find.text('Remove').last);
      await t.pumpAndSettle();
      expect(await iptv.sources(), isEmpty);
      expect(find.byKey(LiveTvKeys.suggestion(CatalogueSuggestion.freeTv)), findsOneWidget);
    });
  });

  test('playRequest passes headers through and zaps over the given list', () async {
    final iptv = IptvService(store: InMemoryIptvStore());
    final list = [
      StoredChannel(key: 'a', sourceId: 's', name: 'A', url: 'http://c.example.test/a', referrer: 'https://r.example.test/', userAgent: 'UA'),
      StoredChannel(key: 'b', sourceId: 's', name: 'B', url: 'http://c.example.test/b'),
    ];
    final r = iptv.playRequest(list, 0);
    expect(r.isLive, isTrue);
    expect(r.zap!.length, 2);
    final spec = await r.resolve();
    expect(spec.videoUrl, 'http://c.example.test/a');
    expect(spec.headers, {'Referer': 'https://r.example.test/', 'User-Agent': 'UA'});
    expect(r.zap!.titleAt(1), 'B');
  });
}

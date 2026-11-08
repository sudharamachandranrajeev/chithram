import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/find/fake_find.dart';
import 'package:chithram/src/find/find_api.dart';
import 'package:chithram/src/find/find_page.dart';
import 'package:chithram/src/ui/common/search_page.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _result = FindResult(
  providerId: 'fixture',
  title: 'Fixture Film 1 2020 1080p',
  kind: ResultKind.torrent,
  seeders: 12,
);

Future<FakeFindProvider> _pump(WidgetTester t, Widget Function(Widget home) wrap, {List<FindProvider>? providers}) async {
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final provider = FakeFindProvider(id: 'fixture', results: const [_result]);
  await t.pumpWidget(AppServicesScope(
    services: AppServices.memory(findSources: [FakeFindProviderSource(providers ?? [provider])]),
    child: MaterialApp(home: wrap(const SizedBox())),
  ));
  return provider;
}

void main() {
  testWidgets('FindPage lists results and passes the query on', (t) async {
    final p = await _pump(t, (_) => const FindPage(query: TextQuery('Fixture Film 1')));
    await t.pumpAndSettle();
    expect(find.text("Find 'Fixture Film 1'"), findsOneWidget);
    expect(find.text('Fixture Film 1 2020 1080p'), findsOneWidget);
    expect(find.textContaining('12 seeders'), findsOneWidget);
    expect(find.byKey(const ValueKey('find-sort-size')), findsOneWidget);
    expect(p.queries.single, isA<TextQuery>());
  });

  testWidgets('selecting a torrent result offers stream, download and copy', (t) async {
    await _pump(t, (_) => const FindPage(query: TextQuery('Fixture Film 1')), providers: [
      FakeFindProvider(id: 'fixture', results: [
        FindResult(
          providerId: 'fixture',
          title: 'Fixture Film 1 2020 1080p',
          kind: ResultKind.torrent,
          seeders: 12,
          infoHash: 'a' * 40,
        ),
      ]),
    ]);
    await t.pumpAndSettle();
    await t.tap(find.text('Fixture Film 1 2020 1080p'));
    await t.pumpAndSettle();
    for (final k in ['find-stream', 'find-files', 'find-download', 'find-copy']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
  });

  testWidgets('FindPage with no providers says so, and skips unavailable ones', (t) async {
    await _pump(t, (_) => const FindPage(query: TextQuery('x')), providers: []);
    await t.pumpAndSettle();
    expect(find.textContaining('No search providers yet.'), findsOneWidget);
    final off = FakeFindProvider(id: 'off', available: false, results: const [_result]);
    await _pump(t, (_) => const FindPage(query: TextQuery('x')), providers: [off]);
    await t.pumpAndSettle();
    expect(off.queries, isEmpty);
  });

  testWidgets('the Search page offers "Find sources for ..." once text is typed', (t) async {
    final focus = SectionFocus();
    addTearDown(focus.dispose);
    final p = await _pump(t, (_) => Scaffold(body: SearchPage(focus: focus, initialQuery: 'Fixture Film 1')));
    await t.pumpAndSettle();
    final card = find.byKey(const ValueKey('search-find-sources'));
    expect(card, findsOneWidget);
    await t.tap(card);
    await t.pumpAndSettle();
    expect(find.byType(FindPage), findsOneWidget);
    expect(find.text('Fixture Film 1 2020 1080p'), findsOneWidget);
    expect(p.queries.single, isA<TextQuery>());
  });

  testWidgets('no card on the YouTube-only search or with an empty query', (t) async {
    final focus = SectionFocus();
    addTearDown(focus.dispose);
    await _pump(t, (_) => Scaffold(body: SearchPage(focus: focus)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-find-sources')), findsNothing);
    await _pump(t, (_) => Scaffold(body: SearchPage(focus: focus, youtubeOnly: true, initialQuery: 'x')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-find-sources')), findsNothing);
  });
}

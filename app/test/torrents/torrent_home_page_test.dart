import 'dart:io';

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/torrents/home/popular_item.dart';
import 'package:chithram/src/features/torrents/home/popular_source.dart';
import 'package:chithram/src/features/torrents/home/open_popular.dart';
import 'package:chithram/src/features/torrents/home/torrent_home_feed.dart';
import 'package:chithram/src/features/torrents/home/torrent_tile.dart';
import 'package:chithram/src/features/torrents/torrents_page.dart';
import 'package:chithram/src/features/torrents/network_dialog.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent/torrent.dart';

import 'torrent_home_feed_test.dart' show item, hex, now;

TorrentFile file(int i, int len, {String ext = 'mkv'}) =>
    TorrentFile(index: i, path: 'f$i.$ext', length: len, streamable: ext == 'mkv');

void main() {
  group('open_popular helpers', () {
    test('magnet from the item, else from the hash, else none', () {
      expect(magnetFor(item('A', magnet: 'magnet:?xt=urn:btih:${hex(1)}&dn=a')), startsWith('magnet:?xt=urn:btih:'));
      expect(magnetFor(item('A B', hash: hex(2))), 'magnet:?xt=urn:btih:${hex(2)}&dn=A%20B');
      expect(magnetFor(item('A')), isNull);
      expect(magnetFor(item('A', magnet: 'magnet:?dn=nothing')), isNull);
    });

    test('auto pick: one video, or one far larger than the rest; packs ask', () {
      TorrentInfo info(List<TorrentFile> f) => TorrentInfo(id: 1, name: 'n', files: f);
      expect(autoPick(info([file(0, 100, ext: 'nfo'), file(1, 5000)]))!.index, 1);
      expect(autoPick(info([file(0, 5000), file(1, 100)]))!.index, 0, reason: 'film beside a sample');
      expect(autoPick(info([file(0, 5000), file(1, 4800), file(2, 4900)])), isNull, reason: 'season pack');
      expect(autoPick(info([file(0, 5000, ext: 'rar')])), isNull);
    });

    test('age text', () {
      expect(ageText(null, now), '');
      expect(ageText(now.subtract(const Duration(minutes: 5)), now), 'now');
      expect(ageText(now.subtract(const Duration(hours: 5)), now), '5 h');
      expect(ageText(now.subtract(const Duration(days: 3)), now), '3 d');
      expect(ageText(now.subtract(const Duration(days: 21)), now), '3 w');
    });
  });

  for (final form in [FormFactor.tv, FormFactor.phone]) {
    group('Torrents tab on ${form.name}', () {
      late Directory tmp;
      setUp(() => tmp = Directory.systemTemp.createTempSync('th-page'));
      tearDown(() => tmp.deleteSync(recursive: true));

      Future<(AppServices, TorrentHomeFeed)> pump(WidgetTester t, FixturePopularSources sources) async {
        t.view.physicalSize = form == FormFactor.tv ? const Size(1920, 1080) : const Size(412, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final feed = TorrentHomeFeed(sources: sources, clock: () => now);
        final services = AppServices.memory(torrentHome: feed);
        await t.pumpWidget(
          AppServicesScope(
            services: services,
            child: FormScope(
              form: form,
              child: MaterialApp(
                theme: buildChithramTheme(form: form),
                home: Scaffold(body: TorrentsPage(focus: SectionFocus())),
              ),
            ),
          ),
        );
        return (services, feed);
      }

      testWidgets('no sources: one Add a source card', (t) async {
        await pump(t, FixturePopularSources([]));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('torrent-add-source')), findsOneWidget);
        expect(find.textContaining('ships no sources'), findsOneWidget);
        expect(find.byKey(const ValueKey('torrent-home-retry')), findsNothing);
      });

      testWidgets('rails with tiles: name, seeders, size, source, age', (t) async {
        final source = FixturePopularSource(
          films: [
            item('Fixture Film 1 2026', seeders: 321, hash: hex(1), size: 2147483648, age: const Duration(hours: 2)),
          ],
          tv: [item('Fixture Show S01', seeders: 55, hash: hex(2), kind: PopularKind.tv, age: const Duration(days: 4))],
        );
        await pump(t, FixturePopularSources([source]));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text('Fixture Film 1 2026').first,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Fixture Film 1 2026'), findsWidgets);
        expect(find.text('321'), findsWidgets);
        expect(find.textContaining('2.0 GiB'), findsWidgets);
        expect(find.text('A'), findsWidgets);
      });

      testWidgets('all sources failing: message and Retry that refetches', (t) async {
        final source = FixturePopularSource(
          films: [item('Back again', seeders: 5, hash: hex(1))],
          error: StateError('down'),
        );
        final (_, feed) = await pump(t, FixturePopularSources([source]));
        await t.pumpAndSettle();
        expect(find.text('Could not reach any source.'), findsOneWidget);
        final retry = find.byKey(const ValueKey('torrent-home-retry'));
        await t.scrollUntilVisible(retry, 200, scrollable: find.byType(Scrollable).first);
        expect(retry, findsOneWidget);
        expect(feed.state.value.sourceErrors, isNotEmpty);
      });

      testWidgets('selecting a tile starts the add flow: the network question first', (t) async {
        final source = FixturePopularSource(films: [item('Pick me', seeders: 5, hash: hex(1))]);
        await pump(t, FixturePopularSources([source]));
        await t.pumpAndSettle();
        final tile = find.text('Pick me').first;
        await t.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
        await t.tap(tile);
        await t.pumpAndSettle();
        expect(find.byKey(NetworkDialogKeys.direct), findsOneWidget);
      });
    });
  }
}

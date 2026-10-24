// End-to-end: Torrent Home. Run through e2e_all_test.dart (see .github/e2e.sh).
// The Torznab fixture (.github/fixtures/torznab) is served at E2E_TORZNAB;
// the feed's clock is fixed at the fixtures' "now" so the age windows are stable.
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/torrents/home/popular_source.dart';
import 'package:chithram/src/features/torrents/home/torrent_home_feed.dart';
import 'package:chithram/src/features/torrents/network_dialog.dart';
import 'package:chithram/src/find/torznab/torznab_service.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/sections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void torrentHomeE2e() {
  group('torrent home', () {
    testWidgets('a Torznab endpoint feeds ranked rails; select asks the network question first', (t) async {
      final base = AppServices.memory();
      final torznab = TorznabService(
        db: base.db,
        secrets: base.secrets,
        network: () => base.torrents.guard.choice,
        minGap: Duration.zero,
      );
      final feed = TorrentHomeFeed(
        sources: TorznabPopularSources(torznab),
        clock: () => DateTime.utc(2026, 10, 24, 12),
      );
      final services = AppServices.memory(
        db: base.db,
        secrets: base.secrets,
        torznab: torznab,
        torrentHome: feed,
        torrents: base.torrents,
      );
      await t.runAsync(() => torznab.add(name: 'Fixture indexer', url: e2eTorznab, apiKey: ''));

      await t.pumpWidget(ChithramApp(services: services));
      await t.pumpAndSettle();
      for (var i = 0; i < Section.torrents.index; i++) {
        await press(t, LogicalKeyboardKey.arrowDown);
      }
      await press(t, LogicalKeyboardKey.arrowRight);

      // The tab opened: the feed fetches, then the rails appear.
      final top = find.text('Fixture Film 1 2026 1080p WEB-DL');
      final watch = Stopwatch()..start();
      while (top.evaluate().isEmpty && watch.elapsed < const Duration(seconds: 30)) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await t.pump();
      }
      expect(top, findsWidgets, reason: 'the fixture indexer\'s top film shows');
      expect(find.text('Fixture Adult 1 2026'), findsNothing);
      expect(feed.state.value.rails.first.title, 'Popular today · Films');
      expect(feed.state.value.rails.first.items.first.seeders, 900, reason: 'merged with the TV-list duplicate');

      await t.ensureVisible(top.first);
      await t.tap(top.first);
      await t.pumpAndSettle();
      expect(find.byKey(NetworkDialogKeys.direct), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(base.torrents.active, isNull);
    });
  });
}

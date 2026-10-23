// End-to-end: Find sources. Run through e2e_all_test.dart. Stub: the page lists
// what the registered providers return (WP-E replaces it with the real page).
import 'dart:async';

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/find/fake_find.dart';
import 'package:chithram/src/find/find_api.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void findE2e() {
  group('find sources', () {
    testWidgets('lists raw results from a provider', (t) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey<NavigatorState>();
      final provider = FakeFindProvider(
        id: 'fixture',
        results: const [
          FindResult(providerId: 'fixture', title: 'Fixture Film 1 2020 1080p', kind: ResultKind.torrent, seeders: 12),
        ],
      );
      await t.pumpWidget(ChithramApp(
        services: AppServices.memory(navigatorKey: key, findSources: [FakeFindProviderSource([provider])]),
      ));
      await t.pumpAndSettle();
      unawaited(openFindSources(key.currentContext!, const TextQuery('Fixture Film 1')));
      await t.pumpAndSettle();
      expect(find.text('Fixture Film 1 2020 1080p'), findsOneWidget);
      expect(provider.queries.single, isA<TextQuery>());
    });
  });
}

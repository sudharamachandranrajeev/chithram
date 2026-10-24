import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/torrents/home/sources_page.dart';
import 'package:chithram/src/find/torznab/torznab_service.dart';
import 'package:chithram/src/find/torznab/torznab_settings.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torznab/torznab.dart';

Future<TorznabResponse> _caps(Uri u) async => TorznabResponse(
  200,
  Uint8List.fromList(utf8.encode(File('../.github/fixtures/torznab/caps.xml').readAsStringSync())),
);

void main() {
  for (final form in [FormFactor.tv, FormFactor.phone]) {
    group('Torznab settings on ${form.name}', () {
      Future<TorznabService> pump(WidgetTester t, Widget body) async {
        t.view.physicalSize = form == FormFactor.tv ? const Size(1920, 1080) : const Size(412, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final base = AppServices.memory();
        final service = TorznabService(
          db: base.db,
          secrets: base.secrets,
          network: () => throw StateError('unused'),
          fetch: _caps,
        );
        final services = AppServices.memory(db: base.db, secrets: base.secrets, torznab: service);
        await service.add(name: 'Home indexer', url: 'http://192.168.1.5:9117/api', apiKey: 'k');
        await t.pumpWidget(
          AppServicesScope(
            services: services,
            child: FormScope(
              form: form,
              child: MaterialApp(
                theme: buildChithramTheme(form: form),
                home: Scaffold(body: SingleChildScrollView(child: body)),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        return service;
      }

      testWidgets('lists the endpoint; the menu tests, disables and removes', (t) async {
        final service = await pump(
          t,
          form == FormFactor.tv ? TorznabSettings(entry: SectionFocus()) : const PhoneTorznabSettings(),
        );
        expect(find.textContaining('Home indexer'), findsOneWidget);
        expect(find.byKey(const ValueKey('torznab-add')), findsOneWidget);

        Future<void> choose(String label) async {
          await t.tap(find.textContaining('Home indexer'));
          await t.pumpAndSettle();
          await t.tap(find.text(label));
          await t.pumpAndSettle();
        }

        await choose('Test');
        expect(find.textContaining('Works:'), findsOneWidget);
        expect(service.health(service.endpoints.single.id).lastOk, isNotNull);
        await choose('Disable');
        expect(service.enabled, isEmpty);
        expect(find.textContaining('(off)').evaluate().length + find.textContaining('Off ·').evaluate().length, 1);
        await choose('Enable');
        expect(service.enabled, hasLength(1));
        await choose('Remove');
        expect(service.endpoints, isEmpty);
        expect(find.textContaining('Home indexer'), findsNothing);
      });

      testWidgets('the sources page offers plugins and Torznab', (t) async {
        await pump(t, const SizedBox());
        final context = t.element(find.byType(SizedBox).first);
        openSources(context);
        await t.pumpAndSettle();
        expect(find.text('Search plugins'), findsOneWidget);
        expect(find.text('Torznab'), findsOneWidget);
        expect(find.byKey(const ValueKey('torznab-add')), findsOneWidget);
      });
    });
  }
}

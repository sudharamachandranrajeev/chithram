import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/media/gateway_client.dart';
import 'package:chithram/src/media/media_config.dart';
import 'package:chithram/src/media/models.dart';
import 'package:chithram/src/media/ui/media_page.dart';
import 'package:chithram/src/media/ui/media_widgets.dart';
import 'package:chithram/src/media/ui/search_view.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'media_support.dart';

SearchItem _hit(int id, String title, {MediaStatus status = MediaStatus.none, String type = 'movie'}) =>
    SearchItem(tmdbId: id, type: type, title: title, year: 2021, overview: 'An overview.', status: status);

AppServices _appServices(Harness h) => AppServices.memory(
  prefs: h.prefs,
  media: h.service,
  youtube: YouTubeService(browse: FixtureBrowse('')),
);

Future<void> _pumpApp(WidgetTester t, Harness h, FormFactor form, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChithramApp(services: _appServices(h), formFactor: form));
  await t.pumpAndSettle();
}

const _sizes = {
  FormFactor.phone: Size(412, 915),
  FormFactor.tv: Size(960, 540),
  FormFactor.desktop: Size(1440, 900),
};

void main() {
  group('feature flag', () {
    for (final form in FormFactor.values) {
      testWidgets('off: ${form.name} shows no Media item, builds no page, makes no call', (t) async {
        final h = Harness(enabled: false);
        await _pumpApp(t, h, form, _sizes[form]!);
        expect(find.byKey(const ValueKey('nav-media')), findsNothing);
        expect(find.byType(MediaPage), findsNothing);
        expect(find.text('Media'), findsNothing);
        expect(h.made, 0);
        expect(h.gateway.calls, isEmpty);
      });

      testWidgets('on: ${form.name} shows the Media item', (t) async {
        final h = Harness();
        await _pumpApp(t, h, form, _sizes[form]!);
        expect(find.byKey(const ValueKey('nav-media')), findsOneWidget);
      });

      testWidgets('${form.name} follows the flag live', (t) async {
        final h = Harness(enabled: false);
        await _pumpApp(t, h, form, _sizes[form]!);
        expect(find.byKey(const ValueKey('nav-media')), findsNothing);
        await h.prefs.set(mediaEnabledPref, true);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('nav-media')), findsOneWidget);
        await h.prefs.set(mediaEnabledPref, false);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('nav-media')), findsNothing);
      });
    }

    testWidgets('desktop: the Media group sits between Sources and Settings', (t) async {
      final h = Harness();
      await _pumpApp(t, h, FormFactor.desktop, _sizes[FormFactor.desktop]!);
      expect(find.text('MEDIA'), findsOneWidget);
      final torrents = t.getTopLeft(find.byKey(const ValueKey('nav-torrents'))).dy;
      final media = t.getTopLeft(find.byKey(const ValueKey('nav-media'))).dy;
      final settings = t.getTopLeft(find.byKey(const ValueKey('nav-settings'))).dy;
      expect(torrents, lessThan(media));
      expect(media, lessThan(settings));
    });

    testWidgets('tv: the rail item sits between YouTube and Settings', (t) async {
      final h = Harness();
      await _pumpApp(t, h, FormFactor.tv, _sizes[FormFactor.tv]!);
      final yt = t.getTopLeft(find.byKey(const ValueKey('nav-youtube'))).dy;
      final media = t.getTopLeft(find.byKey(const ValueKey('nav-media'))).dy;
      final settings = t.getTopLeft(find.byKey(const ValueKey('nav-settings'))).dy;
      expect(yt, lessThan(media));
      expect(media, lessThan(settings));
    });

    testWidgets('phone: the top-bar button opens Media and sits before the gear', (t) async {
      final h = Harness(paired: false);
      await _pumpApp(t, h, FormFactor.phone, _sizes[FormFactor.phone]!);
      final media = t.getTopLeft(find.byKey(const ValueKey('nav-media'))).dx;
      final gear = t.getTopLeft(find.byKey(const ValueKey('nav-settings'))).dx;
      expect(media, lessThan(gear));
      await t.tap(find.byKey(const ValueKey('nav-media')));
      await t.pumpAndSettle();
      expect(find.byType(MediaPage), findsOneWidget);
      expect(find.text('Pair with your media server'), findsOneWidget);
    });

    testWidgets('desktop: selecting Media shows the page', (t) async {
      final h = Harness();
      await _pumpApp(t, h, FormFactor.desktop, _sizes[FormFactor.desktop]!);
      await t.tap(find.byKey(const ValueKey('nav-media')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('media-tab-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('media-tab-downloads')), findsOneWidget, reason: 'admin');
    });
  });

  group('roles', () {
    test('tabs follow the role', () {
      expect(tabsFor(MediaRole.admin), contains(MediaTab.downloads));
      expect(tabsFor(MediaRole.requester), isNot(contains(MediaTab.downloads)));
      expect(tabsFor(MediaRole.viewer), isNot(contains(MediaTab.downloads)));
      expect(tabsFor(null), isNot(contains(MediaTab.downloads)));
    });

    for (final role in MediaRole.values) {
      testWidgets('search: ${role.name} ${role.canRequest ? "sees" : "does not see"} Request', (t) async {
        final h = Harness(role: role);
        h.gateway.searchHits = [_hit(1, 'Dune'), _hit(2, 'Arrival', status: MediaStatus.available)];
        await h.service.load();
        await h.service.refreshMe();
        await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('media-search-field')), 'dune');
        await t.pump(searchDebounce + const Duration(milliseconds: 50));
        await t.pumpAndSettle();
        expect(find.text('Dune'), findsOneWidget);
        expect(find.text('Available'), findsOneWidget);
        expect(find.byKey(const ValueKey('media-request-movie-1')), role.canRequest ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('media-request-movie-2')), findsNothing, reason: 'already available');
      });
    }

    testWidgets('requesting updates the chip and calls the gateway once', (t) async {
      final h = Harness(role: MediaRole.requester);
      h.gateway.searchHits = [_hit(1, 'Dune')];
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('media-search-field')), 'dune');
      await t.pump(searchDebounce + const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('media-request-movie-1')));
      await t.pumpAndSettle();
      expect(h.gateway.calls.where((c) => c.startsWith('request:')), ['request:movie:1']);
      expect(find.text('Awaiting approval'), findsOneWidget);
      expect(find.byKey(const ValueKey('media-request-movie-1')), findsNothing);
    });

    for (final role in MediaRole.values) {
      testWidgets('requests: ${role.name} ${role.isAdmin ? "can" : "cannot"} approve and decline', (t) async {
        final h = Harness(role: role);
        h.gateway.requestItems = [
          const RequestItem(id: 10, title: 'Dune', type: 'movie', status: MediaStatus.awaitingApproval),
          const RequestItem(id: 11, title: 'Arrival', type: 'movie', status: MediaStatus.available),
        ];
        await h.service.load();
        await h.service.refreshMe();
        await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('media-tab-requests')));
        await t.pumpAndSettle();
        expect(find.text('Dune'), findsOneWidget);
        expect(find.byKey(const ValueKey('media-approve-10')), role.isAdmin ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('media-decline-10')), role.isAdmin ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('media-approve-11')), findsNothing, reason: 'not awaiting approval');
      });
    }

    testWidgets('an admin approving changes the chip', (t) async {
      final h = Harness();
      h.gateway.requestItems = [const RequestItem(id: 10, title: 'Dune', type: 'movie', status: MediaStatus.awaitingApproval)];
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('media-tab-requests')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('media-approve-10')));
      await t.pumpAndSettle();
      expect(h.gateway.calls, contains('approve:10'));
      expect(find.text('Approved'), findsOneWidget);
      expect(find.byKey(const ValueKey('media-approve-10')), findsNothing);
    });

    testWidgets('downloads: only admins get the tab; progress shows as text and bar', (t) async {
      final viewer = Harness(role: MediaRole.viewer);
      await viewer.service.load();
      await viewer.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(viewer));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('media-tab-downloads')), findsNothing);

      final h = Harness();
      h.gateway.downloadItems = [
        const DownloadItem(type: 'movie', title: 'Dune', status: MediaStatus.downloading, progress: 0.42, timeLeft: '00:12:00'),
        const DownloadItem(type: 'tv', title: 'Severance', status: MediaStatus.importing),
      ];
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('media-tab-downloads')));
      await t.pumpAndSettle();
      expect(find.text('Downloading 42%'), findsOneWidget);
      expect(find.text('Importing'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // Leave the page so its refresh timer is cancelled.
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a failed "who am I" is asked once, then waits for Try again', (t) async {
      final h = Harness();
      h.gateway.meError = const GatewayException(GatewayErrorKind.unavailable, 'The media service is unavailable. Try again later.');
      await h.service.load();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      expect(h.gateway.calls.where((c) => c == 'me'), hasLength(1), reason: 'no retry loop');
      expect(find.text('Try again'), findsOneWidget);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(h.gateway.calls.where((c) => c == 'me'), hasLength(2), reason: 'only the button asks again');

      h.gateway.meError = null;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(h.gateway.calls.where((c) => c == 'me'), hasLength(3));
      expect(find.text('Try again'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the server tab shows the role and Unpair forgets the device', (t) async {
      final h = Harness(role: MediaRole.requester);
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('media-tab-server')));
      await t.pumpAndSettle();
      expect(find.text('Requester'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('media-unpair')));
      await t.pumpAndSettle();
      expect(await h.tokens.read(), isNull);
      expect(find.text('Pair with your media server'), findsOneWidget);
    });
  });

  group('status chips', () {
    testWidgets('every status has its own label and shape, none is colour only', (t) async {
      final h = Harness();
      await pumpMedia(
        t,
        Wrap(children: [for (final s in MediaStatus.values) MediaStatusChip(s, progress: s == MediaStatus.downloading ? 0.5 : null)]),
        services: _appServices(h),
      );
      for (final s in MediaStatus.values) {
        if (s == MediaStatus.none) continue;
        final label = s == MediaStatus.downloading ? 'Downloading 50%' : s.label;
        expect(find.text(label), findsOneWidget, reason: '$s');
      }
      final icons = t.widgetList<Icon>(find.byType(Icon)).map((i) => i.icon).toSet();
      expect(icons.length, MediaStatus.values.length - 1, reason: 'one distinct icon per status');
    });
  });

  group('search behaviour', () {
    testWidgets('typing is debounced: one search for several keystrokes', (t) async {
      final h = Harness();
      h.gateway.searchHits = [_hit(1, 'Dune')];
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      final f = find.byKey(const ValueKey('media-search-field'));
      for (final s in ['du', 'dun', 'dune']) {
        await t.enterText(f, s);
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(h.gateway.calls.where((c) => c.startsWith('search:')), isEmpty);
      await t.pump(searchDebounce + const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      expect(h.gateway.calls.where((c) => c.startsWith('search:')), ['search:dune']);
    });

    testWidgets('a 429 shows a friendly message and does not search again until the time is up', (t) async {
      final h = Harness();
      h.gateway.searchError = const GatewayException(
        GatewayErrorKind.rateLimited,
        'Too many attempts. Try again in 60 s.',
        retryAfter: Duration(seconds: 60),
      );
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      final f = find.byKey(const ValueKey('media-search-field'));
      await t.enterText(f, 'dune');
      await t.pump(searchDebounce + const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      await t.enterText(f, 'dunes');
      await t.pump(searchDebounce + const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      expect(find.textContaining('Too many searches'), findsOneWidget);
      expect(h.gateway.calls.where((c) => c.startsWith('search:')), ['search:dune'], reason: 'second one never left the app');
    });

    testWidgets('503 reads as service unavailable and offers no crash', (t) async {
      final h = Harness();
      h.gateway.searchError = const GatewayException(GatewayErrorKind.unavailable, 'The media service is unavailable. Try again later.');
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('media-search-field')), 'dune');
      await t.pump(searchDebounce + const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      expect(find.textContaining('unavailable'), findsOneWidget);
      expect(h.service.paired, isTrue, reason: '503 keeps the pairing');
    });

    testWidgets('empty result and the initial hint', (t) async {
      final h = Harness();
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('media-search-hint')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('media-search-field')), 'zzzz');
      await t.pump(searchDebounce + const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      expect(find.text('No matches.'), findsOneWidget);
    });
  });

  group('library', () {
    final id = 'e' * 32;
    testWidgets('a movie plays, a series explains', (t) async {
      final h = Harness();
      h.gateway.libraryItems = [
        LibraryItem(id: id, title: 'Dune', type: 'Movie', year: 2021, poster: '/v1/images/$id?w=342'),
        LibraryItem(id: 'f' * 32, title: 'Severance', type: 'Series'),
      ];
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('media-tab-library')));
      await t.pumpAndSettle();
      expect(find.text('Dune'), findsOneWidget);
      expect(h.gateway.calls, contains('library:movies'));
      // Series: the note, no player.
      await t.tap(find.text('Severance'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('media-library-note')), findsOneWidget);
    });

    testWidgets('images are fetched through the client (token header), never by URL', (t) async {
      final h = Harness();
      h.gateway.libraryItems = [LibraryItem(id: id, title: 'Dune', type: 'Movie', poster: '/v1/images/$id?w=342')];
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('media-tab-library')));
      await t.pumpAndSettle();
      expect(h.gateway.calls, contains('image'));
      expect(find.byType(Image), findsNothing, reason: 'the fake refused, so the placeholder shows');
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });

  group('pairing screen', () {
    testWidgets('rejects an http:// address with a clear message and no network', (t) async {
      final h = Harness(paired: false);
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('media-address')), 'http://media.test');
      await t.enterText(find.byKey(const ValueKey('media-fingerprint')), testFingerprint);
      await t.enterText(find.byKey(const ValueKey('media-code')), '123456');
      await t.tap(find.byKey(const ValueKey('media-pair')));
      await t.pumpAndSettle();
      expect(find.textContaining('No http://'), findsOneWidget);
      expect(h.made, 0);
    });

    testWidgets('a good pairing lands on the paired view with the role', (t) async {
      final h = Harness(paired: false, role: MediaRole.viewer);
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('media-address')), 'media.test');
      await t.enterText(find.byKey(const ValueKey('media-fingerprint')), testFingerprint);
      await t.enterText(find.byKey(const ValueKey('media-code')), '123456');
      await t.tap(find.byKey(const ValueKey('media-pair')));
      await t.pumpAndSettle();
      expect(h.service.paired, isTrue);
      expect(find.byKey(const ValueKey('media-tab-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('media-tab-downloads')), findsNothing, reason: 'viewer');
    });

    testWidgets('a rate-limited pairing disables the button for the Retry-After time', (t) async {
      final gw = _LimitedGateway();
      final h = Harness(paired: false, gateway: gw);
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('media-address')), 'media.test');
      await t.enterText(find.byKey(const ValueKey('media-fingerprint')), testFingerprint);
      await t.enterText(find.byKey(const ValueKey('media-code')), '123456');
      await t.tap(find.byKey(const ValueKey('media-pair')));
      await t.pumpAndSettle();
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('media-code')), '654321');
      await t.tap(find.byKey(const ValueKey('media-pair')));
      await t.pumpAndSettle();
      expect(gw.pairCalls, 1);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('tv d-pad', () {
    testWidgets('tabs are reachable and activatable with arrows and Select', (t) async {
      final h = Harness();
      await h.service.load();
      await h.service.refreshMe();
      final focus = SectionFocus();
      await pumpMedia(t, MediaPage(focus: focus), services: _appServices(h), form: FormFactor.tv);
      await t.pumpAndSettle();
      focus.focus();
      await t.pump();
      expect(FocusManager.instance.primaryFocus, focus.entry, reason: 'the first tab takes focus');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(h.gateway.calls, contains('requests'), reason: 'second tab is Requests');
    });

    testWidgets('pairing: a field opens the on-screen number pad and fills the code', (t) async {
      final h = Harness(paired: false);
      final focus = SectionFocus();
      await pumpMedia(t, MediaPage(focus: focus), services: _appServices(h), form: FormFactor.tv);
      await t.pumpAndSettle();
      // No pointer-only control: every field is a FocusCard.
      expect(find.byType(TextField), findsNothing);
      focus.focus();
      await t.pump();
      // address, fingerprint, code, then Pair.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('Pairing code'), findsWidgets);
      await t.enterText(find.byKey(const ValueKey('text-entry-field')), '123456');
      await t.tap(find.byKey(const ValueKey('text-entry-ok')));
      await t.pumpAndSettle();
      // The code is hidden on screen.
      expect(find.textContaining('123456'), findsNothing);
      expect(find.textContaining('••••••'), findsOneWidget);
    });
  });

  group('phone text scale', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('every tab lays out without overflow at ${scale}x', (t) async {
        final h = Harness();
        h.gateway
          ..searchHits = [
            _hit(1, 'A very long title that surely wraps onto several lines at large text sizes', status: MediaStatus.awaitingApproval),
            _hit(2, 'Arrival'),
          ]
          ..requestItems = [
            const RequestItem(id: 10, title: 'Dune: Part Two, the extended collectors edition', type: 'movie', status: MediaStatus.awaitingApproval, requestedBy: 'someone-with-a-long-name'),
          ]
          ..downloadItems = [
            const DownloadItem(type: 'movie', title: 'Dune: Part Two, the extended collectors edition', status: MediaStatus.downloading, progress: 0.3, timeLeft: '01:12:00'),
          ]
          ..libraryItems = [
            LibraryItem(id: 'a' * 32, title: 'Dune: Part Two, the extended collectors edition', type: 'Movie', year: 2024),
            LibraryItem(id: 'b' * 32, title: 'Severance', type: 'Series', year: 2022),
          ];
        await h.service.load();
        await h.service.refreshMe();
        await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h), form: FormFactor.phone, textScale: scale);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        for (final tab in MediaTab.values) {
          await t.tap(find.byKey(ValueKey('media-tab-${tab.name}')));
          await t.pumpAndSettle();
          if (tab == MediaTab.search) {
            await t.enterText(find.byKey(const ValueKey('media-search-field')), 'dune');
            await t.pump(searchDebounce + const Duration(milliseconds: 50));
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull, reason: '${tab.name} at ${scale}x');
        }
        await t.pumpWidget(const SizedBox());
      });

      testWidgets('the pairing screen fits at ${scale}x', (t) async {
        final h = Harness(paired: false);
        await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h), form: FormFactor.phone, textScale: scale);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.enterText(find.byKey(const ValueKey('media-address')), 'http://x');
        await t.ensureVisible(find.byKey(const ValueKey('media-pair')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('media-pair')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('the main controls are in the bottom half (one hand)', (t) async {
      final h = Harness();
      await h.service.load();
      await h.service.refreshMe();
      await pumpMedia(t, MediaPage(focus: SectionFocus()), services: _appServices(h), form: FormFactor.phone);
      await t.pumpAndSettle();
      final h2 = t.view.physicalSize.height / 2;
      expect(t.getCenter(find.byKey(const ValueKey('media-tab-requests'))).dy, greaterThan(h2));
    });
  });
}

class _LimitedGateway extends FakeGateway {
  int pairCalls = 0;

  @override
  Future<PairResult> pair(String code, String deviceName) async {
    pairCalls++;
    throw const GatewayException(
      GatewayErrorKind.rateLimited,
      'Too many attempts. Try again in 60 s.',
      retryAfter: Duration(seconds: 60),
    );
  }
}

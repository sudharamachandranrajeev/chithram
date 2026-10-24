import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/websites/websites_page.dart';
import 'package:chithram/src/features/websites/websites_service.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_media/web_media.dart';

final _site = Uri.parse('https://videos.example/');

const _pages = {
  'https://videos.example/': '<title>Videos</title><a href="/watch/1"><img src="/t1.jpg">First film</a>'
      '<a href="https://ads.example.net/go">Win a prize</a>',
  'https://videos.example/watch/1': '<title>First film</title><iframe src="https://player.example/e/1"></iframe>',
  'https://player.example/e/1': '<script>player({file:"https://cdn.example/hls/1.m3u8",label:"720p"})</script>',
};

WebsitesService _service() => WebsitesService(
      resolver: WebMediaResolver(
        fetch: (url, {headers = const {}}) async {
          final body = _pages[url.toString()];
          return body == null ? null : FetchedPage(url: url, contentType: 'text/html', body: body);
        },
      ),
    );

Future<void> _pump(WidgetTester t, WebsitesService service) async {
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final focus = SectionFocus();
  addTearDown(focus.dispose);
  await t.pumpWidget(AppServicesScope(
    services: AppServices.memory(websites: service),
    child: MaterialApp(home: Scaffold(body: WebsitesPage(focus: focus))),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('websiteUrlProblem', () {
    expect(websiteUrlProblem('https://videos.example/'), isNull);
    expect(websiteUrlProblem('videos.example'), isNotNull);
    expect(websiteUrlProblem('file:///etc/passwd'), isNotNull);
    expect(websiteUrlProblem('javascript:alert(1)'), isNotNull);
  });

  testWidgets('a saved site opens to its links, a link to its video; ads are not listed', (t) async {
    final service = _service();
    await service.add(_site, 'My videos');
    await _pump(t, service);
    expect(find.byKey(WebsitesKeys.add), findsOneWidget);
    expect(find.text('My videos'), findsOneWidget);

    await t.tap(find.byKey(WebsitesKeys.site(_site)));
    await t.pumpAndSettle();
    expect(find.text('No video on this page. Pick one of its links.'), findsOneWidget);
    expect(find.text('First film'), findsOneWidget);
    expect(find.text('Win a prize'), findsNothing);

    await t.tap(find.byKey(WebsitesKeys.link(0)));
    await t.pumpAndSettle();
    expect(find.byKey(WebsitesKeys.media(0)), findsOneWidget);
    expect(find.textContaining('720p'), findsOneWidget);
    expect(find.textContaining('cdn.example'), findsOneWidget);
  });

  testWidgets('remove asks first', (t) async {
    final service = _service();
    await service.add(_site, 'My videos');
    await _pump(t, service);
    await t.tap(find.byKey(WebsitesKeys.remove(_site)));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Remove'));
    await t.pumpAndSettle();
    expect(await service.sites(), isEmpty);
    expect(find.text('My videos'), findsNothing);
  });

  test('an HLS stream plays through the ad filter with the page as Referer', () async {
    final service = _service();
    final scan = await service.resolver.scan(Uri.parse('https://videos.example/watch/1'));
    final spec = await service.playRequest(scan!.media.single, title: 'First film').resolve();
    expect(spec.videoUrl, startsWith('http://127.0.0.1:'));
    expect(spec.videoUrl, endsWith('.m3u8'));
    expect(spec.headers['Referer'], 'https://player.example/e/1');
  });
}

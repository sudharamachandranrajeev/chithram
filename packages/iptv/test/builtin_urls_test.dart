import 'dart:io';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

void main() {
  test('the only URLs in lib/ are the CatalogueEndpoints constants', () {
    final allowed = {CatalogueEndpoints.iptvOrgApi, CatalogueEndpoints.freeTvPlaylist};
    final url = RegExp(r'''https?://[^\s'"]+''');
    final found = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      for (final line in f.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue; // comments may cite specs
        for (final m in url.allMatches(line)) {
          found.add(m.group(0)!);
          expect(f.path.endsWith('catalogue.dart'), isTrue, reason: '${f.path}: $line');
        }
      }
    }
    expect(found, allowed);
  });

  test('nothing is requested before a source is added and refreshed', () async {
    final http = FakeHttp({});
    final store = InMemoryIptvStore();
    final reg = SourceRegistry(store, http);
    expect(await reg.sources(), isEmpty);
    expect(await reg.due(), isEmpty);
    expect(await reg.refreshDue(), isEmpty);
    // Adding a suggestion alone stores it; only refresh touches the network.
    await reg.add(Source.freeTv('f'));
    expect(http.requests, isEmpty);
    await reg.refresh('f');
    expect(http.requests.single.host, 'raw.githubusercontent.com');
  });
}

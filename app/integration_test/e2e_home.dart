// End-to-end: the 0.3.0 foundations on a real device. Run through
// e2e_all_test.dart. Stubs for now: the work packages add their Home steps.
import 'dart:convert';
import 'dart:io';

import 'package:chithram/src/core/paths.dart';
import 'package:chithram/src/core/secrets.dart';
import 'package:chithram/src/data/database.dart';
import 'package:chithram/src/data/db_pin_store.dart';
import 'package:chithram/src/home/fake_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';
import 'package:path_provider/path_provider.dart';

import 'support.dart';

void homeE2e() {
  group('home foundations', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('e2e-home'));
    tearDown(() => dir.delete(recursive: true));

    testWidgets('SecretStore round-trips (Keystore, credential store or 0600 file)', (t) async {
      final store = openSecretStore(AppPaths.under(dir.path));
      await store.write('e2e.key', 'v1');
      expect(await store.read('e2e.key'), 'v1');
      await store.delete('e2e.key');
      expect(await store.read('e2e.key'), isNull);
      // ignore: avoid_print
      print('CHITHRAM_E2E secrets fallback=${store.isFallback}');
    });

    testWidgets('the database opens on this device and keeps a pin', (t) async {
      final support = await getApplicationSupportDirectory();
      final paths = AppPaths(support: Directory('${dir.path}/support'), cache: support);
      final db = AppDatabase.file(File('${dir.path}/e2e.sqlite'));
      addTearDown(db.close);
      final pins = DbPinStore(db);
      await pins.set('e2e-repo', PinnedKey('AABB', 'pub'));
      expect((await pins.get('e2e-repo'))!.keyIdHex, 'AABB');
      expect(paths.support.path, isNotEmpty);
    });

    testWidgets('the fixture server answers /__hits', (t) async {
      if (e2eBase.isEmpty) return;
      final c = HttpClient();
      addTearDown(c.close);
      final r = await (await c.getUrl(Uri.parse('$e2eBase/__hits'))).close();
      final body = jsonDecode(await utf8.decodeStream(r)) as Map;
      expect(r.statusCode, 200);
      expect(body['total'], isA<int>());
    });

    testWidgets('synthetic fixtures stay synthetic', (t) async {
      expect(fixtureSnapshot().hero.first.title, 'Fixture Film 1');
    });
  });
}

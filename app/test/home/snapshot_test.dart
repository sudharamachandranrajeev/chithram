import 'dart:convert';
import 'dart:io';

import 'package:chithram/src/home/fake_home.dart';
import 'package:chithram/src/home/snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips through JSON bytes', () {
    final s = fixtureSnapshot();
    final back = HomeSnapshot.tryParse(utf8.encode(jsonEncode(s.toJson())))!;
    expect(back.generatedAt, s.generatedAt);
    expect(back.language, 'en-US');
    expect(back.hero.map((t) => t.title), s.hero.map((t) => t.title));
    expect(back.rails, hasLength(3));
    expect(back.rails[1].tiles.first.id, s.rails[1].tiles.first.id);
    expect(back.rails[0].tiles.first.kind, MediaKind.movie);
    expect(back.rails[0].tiles.first.rating, s.rails[0].tiles.first.rating);
    expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
  });

  test('a v:2 snapshot, corrupt bytes and wrong shapes give null', () {
    final v2 = fixtureSnapshot().toJson()..['v'] = 2;
    expect(HomeSnapshot.tryParse(utf8.encode(jsonEncode(v2))), isNull);
    expect(HomeSnapshot.tryParse(utf8.encode('{"v":1,"rails":')), isNull);
    expect(HomeSnapshot.tryParse([0xff, 0xfe, 0x00]), isNull);
    expect(HomeSnapshot.tryParse(utf8.encode('[]')), isNull);
    expect(HomeSnapshot.tryParse(utf8.encode('{"v":1}')), isNull);
    expect(HomeSnapshot.tryParse(const []), isNull);
  });

  group('SnapshotStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('snap'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('missing file loads null; save then load; delete', () async {
      final store = SnapshotStore(File('${dir.path}/sub/home_snapshot.json'));
      expect(await store.load(), isNull);
      await store.save(fixtureSnapshot(rails: 2));
      expect((await store.load())!.rails, hasLength(2));
      expect(File('${dir.path}/sub/home_snapshot.json.tmp').existsSync(), isFalse);
      await store.delete();
      expect(await store.load(), isNull);
      await store.delete(); // already gone
    });

    test('a corrupt file and a v:2 file load null', () async {
      final f = File('${dir.path}/home_snapshot.json')..writeAsStringSync('not json');
      expect(await SnapshotStore(f).load(), isNull);
      f.writeAsStringSync(jsonEncode(fixtureSnapshot().toJson()..['v'] = 2));
      expect(await SnapshotStore(f).load(), isNull);
    });
  });
}

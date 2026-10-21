import 'dart:io';

import 'package:chithram/src/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('values persist through a reload and null removes a key', () async {
    final dir = await Directory.systemTemp.createTemp('prefs');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/sub/prefs.json');
    final a = await Prefs.load(file);
    expect(a.getString('k'), isNull);
    await a.set('k', 'v');
    await a.set('n', 3);
    await a.set('b', true);
    final b = await Prefs.load(file);
    expect(b.getString('k'), 'v');
    expect(b.getInt('n'), 3);
    expect(b.getBool('b'), isTrue);
    await b.set('k', null);
    expect((await Prefs.load(file)).getString('k'), isNull);
  });

  test('a corrupt file starts empty', () async {
    final dir = await Directory.systemTemp.createTemp('prefs');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/prefs.json')..writeAsStringSync('{oops');
    expect((await Prefs.load(file)).getString('k'), isNull);
  });
}

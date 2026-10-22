import 'package:test/test.dart';
import 'package:torznab/torznab.dart';

void main() {
  test('stub client finds nothing', () async {
    const c = NullTorznabClient();
    final base = Uri.parse('http://localhost:9117/api');
    expect((await c.caps(base)).search, isFalse);
    expect(await c.search(base, query: 'Fixture Film 1'), isEmpty);
  });
}

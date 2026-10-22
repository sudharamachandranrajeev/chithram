import 'package:media_names/media_names.dart';
import 'package:test/test.dart';

void main() {
  test('stub keeps the trimmed name as the title', () {
    final p = parse('  Fixture Film 1 2020 1080p  ');
    expect(p.title, 'Fixture Film 1 2020 1080p');
    expect(p.year, isNull);
    expect(p.isPack, isFalse);
  });
}

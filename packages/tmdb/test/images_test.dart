import 'package:test/test.dart';
import 'package:tmdb/tmdb.dart';

void main() {
  test('poster picks the smallest bucket at least as wide', () {
    expect(tmdbPoster('/a.jpg', 100), 'https://image.tmdb.org/t/p/w154/a.jpg');
    expect(tmdbPoster('/a.jpg', 154), 'https://image.tmdb.org/t/p/w154/a.jpg');
    expect(tmdbPoster('/a.jpg', 336), 'https://image.tmdb.org/t/p/w342/a.jpg');
    expect(tmdbPoster('/a.jpg', 1), 'https://image.tmdb.org/t/p/w92/a.jpg');
  });

  test('beyond the largest bucket falls back to original', () {
    expect(tmdbPoster('/a.jpg', 781), 'https://image.tmdb.org/t/p/original/a.jpg');
    expect(tmdbBackdrop('/b.jpg', 1264), 'https://image.tmdb.org/t/p/w1280/b.jpg');
    expect(tmdbBackdrop('/b.jpg', 1281), 'https://image.tmdb.org/t/p/original/b.jpg');
  });

  test('backdrop, profile and still buckets', () {
    expect(tmdbBackdrop('/b.jpg', 960), 'https://image.tmdb.org/t/p/w1280/b.jpg');
    expect(tmdbBackdrop('/b.jpg', 200), 'https://image.tmdb.org/t/p/w300/b.jpg');
    expect(tmdbProfile('/p.png', 100), 'https://image.tmdb.org/t/p/w185/p.png');
    expect(tmdbStill('/s.webp', 250), 'https://image.tmdb.org/t/p/w300/s.webp');
  });

  test('paths that could leave the image host are refused', () {
    for (final bad in ['a.jpg', '//evil.test/a.jpg', '/../a.jpg', '/a/b.jpg', '/a.jpg?x=1', '', 'https://x/a.jpg']) {
      expect(() => tmdbPoster(bad, 100), throwsArgumentError, reason: bad);
      expect(isTmdbImagePath(bad), isFalse);
    }
  });
}

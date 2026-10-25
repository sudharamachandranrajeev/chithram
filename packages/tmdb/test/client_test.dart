import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tmdb/tmdb.dart';

const key = '0123456789abcdef0123456789abcdef';
Map<String, dynamic> fixture(String name) => jsonDecode(
  File('../../.github/fixtures/tmdb/$name.json').readAsStringSync(),
) as Map<String, dynamic>;

void main() {
  test('key shapes and cache identities never expose credentials', () {
    expect(authMode(key), AuthMode.v3);
    expect(authMode('eyJfixture.token'), AuthMode.bearer);
    expect(
      () => authMode('secret-invalid'),
      throwsA(
        isA<TmdbException>().having(
          (e) => e.toString(),
          'redacted',
          isNot(contains('secret-invalid')),
        ),
      ),
    );
    expect(
      TmdbClient.cacheKey('movie/1', {'api_key': key, 'language': 'en'}),
      isNot(contains(key)),
    );
  });
  test('both auth modes, conditional headers and adult exclusion', () async {
    for (final token in [key, 'eyJfixture.token']) {
      final client = TmdbClient(
        key: token,
        client: MockClient((request) async {
          expect(request.url.queryParameters['include_adult'], 'false');
          expect(request.headers['If-None-Match'], 'fixture-etag');
          expect(request.headers['If-Modified-Since'], 'fixture-date');
          if (token == key) {
            expect(request.url.queryParameters['api_key'], key);
          } else {
            expect(request.headers['Authorization'], 'Bearer $token');
          }
          return http.Response('', 304);
        }),
      );
      expect(
        (await client.get(
          'movie/popular',
          list: true,
          etag: 'fixture-etag',
          lastModified: 'fixture-date',
        )).status,
        304,
      );
      client.close();
    }
  });
  test(
    'all synthetic endpoint shapes parse, adult and person results excluded',
    () {
      expect(
        parseTiles(fixture('movie-list'), MediaKind.movie).single.title,
        'Fixture Film 1',
      );
      expect(
        parseTiles(fixture('tv-list'), MediaKind.tv).single.id,
        'tmdb:tv:2',
      );
      expect(parseTiles(fixture('mixed-list')).length, 2);
      expect(parseGenres(fixture('genres')).single.id, 12);
      final movie = parseDetails(fixture('movie-details'), MediaKind.movie);
      expect(movie.cast.single.character, 'Fixture Role');
      expect(movie.trailers.single.youtubeKey, 'fixture1234');
      expect(movie.similar.single.tmdbId, 5);
      final tv = parseDetails(fixture('tv-details'), MediaKind.tv);
      expect(tv.cast.single.character, 'Fixture Role');
      expect(tv.seasons.single.number, 1);
      expect(tv.tvdbId, 22);
      expect(parseSeason(fixture('season')).episodes.single.runtimeMin, 45);
    },
  );
  test(
    '401 redacts URLs and key, malformed and oversized bodies fail safely',
    () async {
      for (final response in [
        http.Response(key, 401),
        http.Response(key, 200),
        http.Response('x' * (2 * 1024 * 1024 + 1), 200),
      ]) {
        final client = TmdbClient(
          key: key,
          client: MockClient((_) async => response),
        );
        await expectLater(
          client.get('configuration'),
          throwsA(
            isA<TmdbException>().having(
              (e) => e.toString(),
              'safe',
              isNot(contains(key)),
            ),
          ),
        );
        client.close();
      }
    },
  );
  test(
    '429 supports seconds and HTTP date, blocks queued and repeated fetches',
    () async {
      final now = DateTime.utc(2026, 1, 1);
      for (final retry in [
        '120',
        HttpDate.format(now.add(const Duration(minutes: 2))),
      ]) {
        var count = 0;
        final client = TmdbClient(
          key: key,
          now: () => now,
          random: () => 0.5,
          client: MockClient((_) async {
            count++;
            return http.Response('', 429, headers: {'retry-after': retry});
          }),
        );
        await expectLater(
          client.get('configuration'),
          throwsA(
            isA<TmdbException>().having(
              (e) => e.retryAfter,
              'retry',
              const Duration(minutes: 2),
            ),
          ),
        );
        await expectLater(
          client.get('configuration'),
          throwsA(isA<TmdbException>()),
        );
        expect(count, 1);
        client.close();
      }
    },
  );
  test('adult details are rejected before caching and transport failures back off', () async {
    expect(() => parseDetails({...fixture('movie-details'),'adult':true},MediaKind.movie),throwsA(isA<TmdbException>()));
    var attempts=0;
    final client=TmdbClient(key:key,random:()=>0.5,client:MockClient((_) async {attempts++;throw const SocketException('secret fixture');}));
    await expectLater(client.get('configuration'),throwsA(isA<TmdbException>().having((e)=>e.retryAfter,'backoff',const Duration(minutes:1))));
    await expectLater(client.get('configuration'),throwsA(isA<TmdbException>()));
    expect(attempts,1);client.close();
  });

  test(
    'fake clock enforces eight starts per second and four in flight',
    () async {
      var now = DateTime.utc(2026);
      final starts = <DateTime>[];
      var active = 0, peak = 0;
      final limiter = RequestLimiter(
        now: () => now,
        sleep: (duration) async {
          now = now.add(duration);
        },
      );
      final gates = <Completer<void>>[];
      final futures = List.generate(
        12,
        (_) => limiter.run(() async {
          starts.add(now);
          active++;
          if (active > peak) peak = active;
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          active--;
        }),
      );
      for (var i = 0; i < 12; i++) {
        while (gates.length <= i) {
          await Future<void>.delayed(Duration.zero);
        }
        gates[i].complete();
      }
      await Future.wait(futures);
      expect(peak, lessThanOrEqualTo(4));
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i].difference(starts[i - 1]),
          greaterThanOrEqualTo(const Duration(milliseconds: 125)),
        );
      }
      for (final start in starts) {
        expect(
          starts
              .where(
                (s) =>
                    !s.isBefore(start) &&
                    s.isBefore(start.add(const Duration(seconds: 1))),
              )
              .length,
          lessThanOrEqualTo(8),
        );
      }
    },
  );
}

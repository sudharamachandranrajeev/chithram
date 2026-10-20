import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:innertube/innertube.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('parseSponsorSegments filters by video id and sorts by start', () {
    final segs = parseSponsorSegments(fixtureAny('sponsorblock_prefix.json'), 'FIXTUREVOD1');
    expect(segs.map((s) => s.category), ['sponsor', 'outro']);
    expect(segs.first.start, const Duration(milliseconds: 10250));
    expect(segs.first.end, const Duration(seconds: 40));
    expect(segs.first.uuid, 'u1');
  });

  test('client sends only the 4-char hash prefix', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(fixtureText('sponsorblock_prefix.json'), 200);
    });
    final segs = await SponsorBlockClient(client: client).segments('FIXTUREVOD1');
    final prefix = sha256.convert(utf8.encode('FIXTUREVOD1')).toString().substring(0, 4);
    expect(seen.host, 'sponsor.ajay.app');
    expect(seen.path, '/api/skipSegments/$prefix');
    expect(seen.toString(), isNot(contains('FIXTUREVOD1')));
    expect(segs, hasLength(2));
  });

  test('404 means no segments; 500 throws', () async {
    final none = SponsorBlockClient(client: MockClient((_) async => http.Response('Not Found', 404)));
    expect(await none.segments('FIXTUREVOD1'), isEmpty);
    final bad = SponsorBlockClient(client: MockClient((_) async => http.Response('', 500)));
    expect(() => bad.segments('FIXTUREVOD1'), throwsA(isA<HttpStatusException>()));
  });
}

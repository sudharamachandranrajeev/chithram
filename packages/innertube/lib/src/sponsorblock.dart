import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'errors.dart';
import 'util.dart';

class SponsorSegment {
  const SponsorSegment({
    required this.category,
    required this.actionType,
    required this.start,
    required this.end,
    this.uuid = '',
  });
  final String category;
  final String actionType;
  final Duration start;
  final Duration end;
  final String uuid;
}

const defaultSponsorCategories = ['sponsor', 'selfpromo', 'interaction', 'intro', 'outro', 'music_offtopic'];

/// SponsorBlock (sponsor.ajay.app) segments. Opt-in: nothing calls this unless
/// the user turned it on. Uses the privacy-preserving prefix lookup: only the
/// first 4 hex chars of the SHA-256 of the video id are sent.
class SponsorBlockClient {
  SponsorBlockClient({http.Client? client, this.host = 'sponsor.ajay.app'}) : _client = client ?? http.Client();
  final http.Client _client;
  final String host;

  Future<List<SponsorSegment>> segments(String videoId,
      {List<String> categories = defaultSponsorCategories}) async {
    final prefix = sha256.convert(utf8.encode(videoId)).toString().substring(0, 4);
    final uri = Uri.https(host, '/api/skipSegments/$prefix', {
      'categories': jsonEncode(categories),
      'actionTypes': jsonEncode(['skip']),
    });
    final response = await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) return const [];
    if (response.statusCode >= 400) throw HttpStatusException(response.statusCode, host);
    return parseSponsorSegments(jsonDecode(utf8.decode(response.bodyBytes)), videoId);
  }
}

/// Segments for [videoId] from a prefix-lookup response (a list of
/// `{videoID, segments: [...]}`), sorted by start.
List<SponsorSegment> parseSponsorSegments(Object? data, String videoId) {
  final out = <SponsorSegment>[];
  for (final entry in asList(data).map(asJson)) {
    if (asString(entry['videoID']) != videoId) continue;
    for (final s in asList(entry['segments']).map(asJson)) {
      final times = asList(s['segment']);
      if (times.length < 2 || times[0] is! num || times[1] is! num) continue;
      out.add(SponsorSegment(
        category: asString(s['category']),
        actionType: asString(s['actionType']),
        start: Duration(milliseconds: ((times[0] as num) * 1000).round()),
        end: Duration(milliseconds: ((times[1] as num) * 1000).round()),
        uuid: asString(s['UUID']),
      ));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

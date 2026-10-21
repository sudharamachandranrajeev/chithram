import 'sources.dart';
import 'xmltv.dart';

/// One card in the "Live now" sports rail.
class LiveSportsItem {
  LiveSportsItem(this.channel, this.programme, this.score, this.isCricket);
  final StoredChannel channel;

  /// The airing programme, or null when the channel only matched by group.
  final EpgProgramme? programme;
  final int score;
  final bool isCricket;
}

RegExp _kw(List<String> words) => RegExp(
    '(?<![a-z0-9])(?:${words.map(RegExp.escape).join('|')})(?![a-z0-9])',
    caseSensitive: false);

final _cricket = _kw([
  'cricket', 'ipl', 't20', 't20i', 'odi', 'test match', 'test series',
  'icc', 'bbl', 'psl', 'cpl', 'ranji', 'asia cup',
]);

final _sports = _kw([
  'sport', 'sports', 'football', 'soccer', 'tennis', 'basketball', 'nba',
  'nfl', 'hockey', 'kabaddi', 'formula 1', 'f1', 'motogp', 'wwe', 'ufc',
  'boxing', 'golf', 'rugby', 'premier league', 'la liga', 'isl',
  'badminton', 'athletics', 'olympics',
]);

bool isCricketText(String? s) => s != null && _cricket.hasMatch(s);
bool isSportsText(String? s) =>
    s != null && (_sports.hasMatch(s) || _cricket.hasMatch(s));

/// Builds the "Live now" sports rail.
///
/// - [airingNow]: programmes whose window covers [now] (any channel).
/// - [epgIdByChannelKey]: StoredChannel.key -> EPG channel id (from
///   `mapChannelsToEpg`, or just the tvg-id).
/// Cricket items always rank above others, then by score. Scores: cricket programme 100, other sports programme 60, channel in a
/// sports group 20 (+30 if its group/name says cricket). Ties by name.
List<LiveSportsItem> liveSportsNow({
  required List<StoredChannel> channels,
  required Iterable<EpgProgramme> airingNow,
  required Map<String, String> epgIdByChannelKey,
  DateTime? now,
  int limit = 50,
}) {
  final t = (now ?? DateTime.now()).toUtc();
  final byEpg = <String, List<EpgProgramme>>{};
  for (final p in airingNow) {
    if (p.airingAt(t)) (byEpg[p.channel] ??= []).add(p);
  }
  final out = <LiveSportsItem>[];
  for (final c in channels) {
    if (!c.playable) continue;
    final epgId = epgIdByChannelKey[c.key];
    EpgProgramme? bestProg;
    var best = 0;
    var cricket = false;
    for (final p in epgId == null ? const <EpgProgramme>[] : byEpg[epgId] ?? const []) {
      final hay = <String?>[p.title, ...p.categories];
      final isC = hay.any(isCricketText) || isCricketText(p.description);
      final isS = isC || hay.any(isSportsText);
      final s = isC ? 100 : (isS ? 60 : 0);
      if (s > best) {
        best = s;
        bestProg = p;
        cricket = isC;
      }
    }
    var score = best;
    final groupText = [c.group, ...c.categories];
    if (groupText.any(isSportsText)) {
      score += 20;
      if (groupText.any(isCricketText) || isCricketText(c.name)) {
        score += 30;
        cricket = true;
      }
    }
    if (score == 0) continue;
    out.add(LiveSportsItem(c, bestProg, score, cricket));
  }
  out.sort((a, b) {
    if (a.isCricket != b.isCricket) return a.isCricket ? -1 : 1;
    final s = b.score.compareTo(a.score);
    return s != 0 ? s : a.channel.name.toLowerCase().compareTo(b.channel.name.toLowerCase());
  });
  return out.length > limit ? out.sublist(0, limit) : out;
}

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

StoredChannel ch(String key, String name, {String? group, bool dead = false}) =>
    StoredChannel(key: key, sourceId: 's', name: name, group: group, url: 'https://h.example.test/$key', dead: dead);

void main() {
  final now = DateTime.utc(2026, 6, 1, 12);
  EpgProgramme p(String c, String title,
          {List<String> cats = const [], int startMin = -10, int len = 120, String? desc}) =>
      EpgProgramme(
          channel: c,
          start: now.add(Duration(minutes: startMin)),
          stop: now.add(Duration(minutes: startMin + len)),
          title: title,
          categories: cats,
          description: desc);

  test('cricket first, then sports, then group-only; dead and past excluded', () {
    final channels = [
      ch('foot', 'Foot TV'),
      ch('cric', 'Cric TV'),
      ch('grp', 'Group Sports', group: 'Sports'),
      ch('news', 'News'),
      ch('dead', 'Dead Cricket', dead: true),
      ch('old', 'Old Cricket'),
      ch('grpcric', 'Willow', group: 'Cricket'),
    ];
    final map = {for (final c in channels) c.key: '${c.key}.test'};
    final items = liveSportsNow(
      channels: channels,
      epgIdByChannelKey: map,
      now: now,
      airingNow: [
        p('foot.test', 'Premier League Live', cats: ['Football']),
        p('cric.test', 'Mumbai vs Chennai', cats: ['Sports', 'IPL']),
        p('news.test', 'Evening News', cats: ['News']),
        p('dead.test', 'Test Match Special'),
        p('old.test', 'T20 Blast', startMin: -300, len: 120),
      ],
    );
    expect(items.map((i) => i.channel.key), ['cric', 'grpcric', 'foot', 'grp']);
    expect(items.first.isCricket, isTrue);
    expect(items[1].programme, isNull);
    expect(items[1].isCricket, isTrue);
    expect(items[2].isCricket, isFalse);
  });

  test('keyword matching is case-insensitive and word-bounded', () {
    expect(isCricketText('IPL 2026: Final'), isTrue);
    expect(isCricketText('india v pak odi'), isTrue);
    expect(isCricketText('1st TEST MATCH day 2'), isTrue);
    expect(isCricketText('T20 World Cup'), isTrue);
    expect(isCricketText('Melodic diplomacy'), isFalse); // odi inside word
    expect(isCricketText('Triple Time'), isFalse);
    expect(isSportsText('Live Sports'), isTrue);
    expect(isSportsText('Cooking show'), isFalse);
  });

  test('cricket in description counts', () {
    final c = [ch('a', 'A')];
    final r = liveSportsNow(
        channels: c,
        epgIdByChannelKey: {'a': 'a.test'},
        now: now,
        airingNow: [p('a.test', 'Special', desc: 'Live cricket coverage')]);
    expect(r.single.isCricket, isTrue);
  });

  test('limit', () {
    final c = [for (var i = 0; i < 10; i++) ch('k$i', 'n$i', group: 'Sports')];
    expect(liveSportsNow(channels: c, airingNow: const [], epgIdByChannelKey: const {}, limit: 3), hasLength(3));
  });
}

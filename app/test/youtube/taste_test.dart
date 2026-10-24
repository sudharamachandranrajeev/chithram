import 'dart:convert';
import 'dart:io';

import 'package:chithram/src/features/youtube/feed/taste.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart';

VideoItem _video(String id, String title, {String channel = 'UCa', String author = 'A'}) =>
    VideoItem(videoId: id.padRight(11, '0'), title: title, channelId: channel, author: author);

const _min = Duration(minutes: 1);
const _ten = Duration(minutes: 10);

void main() {
  final t0 = DateTime.utc(2026, 10, 1);

  test('reward: finished, half, abandoned, live', () {
    expect(TasteProfile.rewardFor(_ten * 0.8, _ten), 1);
    expect(TasteProfile.rewardFor(_ten * 0.4, _ten), 0.5);
    expect(TasteProfile.rewardFor(const Duration(seconds: 10), _ten), lessThan(0));
    expect(TasteProfile.rewardFor(const Duration(minutes: 2), _ten), 0.15);
    expect(TasteProfile.rewardFor(const Duration(minutes: 15), Duration.zero), 1);
    expect(TasteProfile.rewardFor(const Duration(seconds: 5), Duration.zero), lessThan(0));
  });

  test('a finished video raises its channel and words; an abandoned one lowers them', () {
    final p = TasteProfile()
      ..watched(_video('a', 'Malayalam melody hits', channel: 'UCm'), position: _ten, duration: _ten, now: t0)
      ..watched(_video('b', 'Unboxing gadgets', channel: 'UCg'), position: const Duration(seconds: 5), duration: _ten, now: t0);
    expect(p.channels['UCm'], greaterThan(0));
    expect(p.channels['UCg'], lessThan(0));
    expect(p.terms['malayalam'], greaterThan(0));
    expect(p.terms['unboxing'], lessThan(0));
    expect(p.affinity(_video('c', 'New Malayalam melody', channel: 'UCx')),
        greaterThan(p.affinity(_video('d', 'Gadgets unboxing', channel: 'UCx'))));
    expect(p.seen, containsAll([_video('a', '').videoId, _video('b', '').videoId]));
  });

  test('scores fade with a 30-day half-life', () {
    final p = TasteProfile()..watched(_video('a', 'song', channel: 'UCm'), position: _ten, duration: _ten, now: t0);
    final before = p.channels['UCm']!;
    p.searched('other', now: t0.add(TasteProfile.halfLife));
    expect(p.channels['UCm'], closeTo(before / 2, 1e-9));
  });

  test('titles in any script make terms; common words do not', () {
    expect(TasteProfile.titleTerms('Official Video | കണ്ണേ കലൈമാനേ 4K'), ['കണ്ണേ', 'കലൈമാനേ']);
    expect(TasteProfile.titleTerms('The 2026 cricket'), ['cricket']);
  });

  test('unfinished: started, not near the end, not live', () {
    final p = TasteProfile()
      ..watched(_video('a', 'half'), position: _ten * 0.5, duration: _ten, now: t0)
      ..watched(_video('b', 'done'), position: _ten, duration: _ten, now: t0)
      ..watched(_video('c', 'peek'), position: const Duration(seconds: 10), duration: _ten, now: t0);
    expect(p.unfinished.map((w) => w.item.title), ['half']);
  });

  test('seeds prefer liked and recent plays', () {
    final p = TasteProfile()
      ..watched(_video('old', 'old'), position: _ten, duration: _ten, now: t0)
      ..watched(_video('new', 'new'), position: _ten, duration: _ten, now: t0.add(const Duration(days: 20)))
      ..watched(_video('bad', 'bad'), position: const Duration(seconds: 3), duration: _ten, now: t0.add(const Duration(days: 21)));
    final seeds = p.seeds(4, now: t0.add(const Duration(days: 21)));
    expect(seeds.map((s) => s.$1.title), ['new', 'old']);
  });

  test('recommend: related to several seeds wins; seen and disliked drop; two per channel', () {
    final p = TasteProfile()
      ..watched(_video('seen', 'seen', channel: 'UCs'), position: _ten, duration: _ten, now: t0)
      ..watched(_video('meh', 'meh', channel: 'UCbad'), position: const Duration(seconds: 2), duration: _min, now: t0)
      ..watched(_video('meh2', 'meh', channel: 'UCbad'), position: const Duration(seconds: 2), duration: _min, now: t0);
    final shared = _video('shared', 'x', channel: 'UC1');
    final list = p.recommend(
      related: [
        ([_video('only', 'y', channel: 'UC2'), shared, _video('seen', 'seen', channel: 'UCs')], 1.0),
        ([shared, _video('dis', 'z', channel: 'UCbad')], 1.0),
      ],
      popular: [for (var i = 0; i < 4; i++) _video('pop$i', 'p', channel: 'UCpop')],
    );
    final ids = list.map((v) => v.videoId.replaceAll('0', '')).toList();
    expect(ids.first, 'shared');
    expect(ids, contains('only'));
    expect(ids, isNot(contains('seen')));
    expect(ids, isNot(contains('dis')));
    expect(ids.where((id) => id.startsWith('pop')), hasLength(2));
  });

  test('a store keeps the profile in its file and clears it', () async {
    final dir = await Directory.systemTemp.createTemp('taste');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/youtube_taste.json');
    final store = TasteStore(file);
    await store.watched(_video('a', 'kerala travel'), position: _ten, duration: _ten, source: 'popular-news');
    expect(jsonDecode(await file.readAsString())['v'], 1);

    final again = TasteStore(file);
    await again.load();
    expect(again.profile.history.single.item.title, 'kerala travel');
    expect(again.profile.history.single.source, 'popular-news');
    expect(again.profile.sources['popular-news'], greaterThan(0));

    await again.clear();
    final cleared = TasteStore(file);
    await cleared.load();
    expect(cleared.profile.isEmpty, isTrue);
  });
}

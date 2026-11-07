import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

void main() {
  group('country', () {
    test('from tvg-country: codes, lists, UK and names', () {
      expect(normalizeCountry('AL'), 'AL');
      expect(normalizeCountry('al;xk'), 'AL');
      expect(normalizeCountry(' UK '), 'GB');
      expect(normalizeCountry('Albania'), 'AL');
      expect(normalizeCountry('INT'), isNull);
      expect(normalizeCountry(''), isNull);
      expect(normalizeCountry(null), isNull);
    });

    test('from the tvg-id suffix, before any @feed', () {
      expect(countryFromTvgId('Kanali7.al'), 'AL');
      expect(countryFromTvgId('StingrayClassicRock.us@SD'), 'US');
      expect(countryFromTvgId('BBCOne.uk'), 'GB');
      expect(countryFromTvgId('a.test'), isNull);
      expect(countryFromTvgId('noDot'), isNull);
      expect(countryFromTvgId('trailing.'), isNull);
      expect(countryFromTvgId(null), isNull);
    });

    test('names round-trip to codes', () {
      expect(countryNames['IN'], 'India');
      expect(countryCodeForName('india'), 'IN');
      expect(countryCodeForName('United States'), 'US');
      expect(countryCodeForName('USA'), 'US');
      expect(countryCodeForName('Movies'), isNull);
    });
  });

  group('categories', () {
    test('split on ;, tidy case, drop country names and duplicates', () {
      expect(categoriesFromGroup('Animation;Kids'), ['Animation', 'Kids']);
      expect(categoriesFromGroup('NEWS'), ['News']);
      expect(categoriesFromGroup('Albania'), isEmpty);
      expect(categoriesFromGroup('Movies; ;movies'), ['Movies']);
      expect(categoriesFromGroup('Undefined'), isEmpty);
      expect(categoriesFromGroup(null), isEmpty);
    });
  });

  group('quality', () {
    test('buckets from names', () {
      expect(qualityOf('Stingray Classic Rock (1080p)'), ChannelQuality.fhd);
      expect(qualityOf('Nature 4K'), ChannelQuality.uhd);
      expect(qualityOf('Film UHD'), ChannelQuality.uhd);
      expect(qualityOf('Sky News HD'), ChannelQuality.hd);
      expect(qualityOf('Local (720p)'), ChannelQuality.hd);
      expect(qualityOf('Retro (480p)'), ChannelQuality.sd);
      expect(qualityOf('Plain'), ChannelQuality.unknown);
      // "HD" inside a word is not a tag.
      expect(qualityOf('Shdw TV'), ChannelQuality.unknown);
    });

    test('a catalogue quality wins over the name', () {
      expect(qualityOf('Channel HD', '1080p'), ChannelQuality.fhd);
      expect(qualityOf('Channel HD', ''), ChannelQuality.hd);
      expect(ChannelQuality.unknown.nameOrNull, isNull);
      expect(ChannelQuality.byName('hd'), ChannelQuality.hd);
    });
  });

  group('names and flags', () {
    test('markers and quality tags are removed', () {
      expect(
        cleanChannelName('Stingray Classic Rock (1080p)'),
        'Stingray Classic Rock',
      );
      expect(
        cleanChannelName('Channel One (720p) [Geo-blocked]'),
        'Channel One',
      );
      expect(cleanChannelName('News 24 [Not 24/7]'), 'News 24');
      expect(cleanChannelName('Kanali 7 Ⓢ'), 'Kanali 7');
      expect(cleanChannelName('Ⓖ RTSH 1 Ⓨ'), 'RTSH 1');
      expect(cleanChannelName('[x]'), '[x]');
    });

    test('geo-blocked and not 24/7', () {
      expect(isGeoBlocked('A [Geo-blocked]'), isTrue);
      expect(isGeoBlocked('A Ⓖ'), isTrue);
      expect(isGeoBlocked('A'), isFalse);
      expect(isNot247('A [Not 24/7]'), isTrue);
      expect(isNot247('A'), isFalse);
    });
  });

  group('languages', () {
    test('tvg-language names and codes become names', () {
      expect(languagesFromAttribute('English;Hindi'), ['English', 'Hindi']);
      expect(languagesFromAttribute('eng, mal'), ['English', 'Malayalam']);
      expect(languagesFromAttribute('TAMIL'), ['Tamil']);
      expect(languagesFromAttribute(null), isEmpty);
      expect(normalizeLanguages(['mal', 'mal', 'tam']), ['Malayalam', 'Tamil']);
    });
  });

  group('ChannelMeta.of', () {
    test('derives everything for a record stored before the new fields', () {
      final old = StoredChannel.fromJson({
        'key': 'k',
        'src': 's',
        'name': 'Stingray Classic Rock (1080p) [Geo-blocked]',
        'tvgId': 'StingrayClassicRock.us@SD',
        'group': 'Music;Entertainment',
      });
      final m = ChannelMeta.of(old);
      expect(m.displayName, 'Stingray Classic Rock');
      expect(m.country, 'US');
      expect(m.countryName, 'United States');
      expect(m.categories, ['Music', 'Entertainment']);
      expect(m.languages, ['English']);
      expect(m.languagesInferred, isTrue);
      expect(m.quality, ChannelQuality.fhd);
      expect(m.geoBlocked, isTrue);
      expect(m.not247, isFalse);
    });

    test('the feed suffix gives a quality when the name does not', () {
      final c = StoredChannel(
        key: 'k',
        sourceId: 's',
        name: 'Plain',
        tvgId: 'Plain.us@SD',
      );
      expect(ChannelMeta.of(c).quality, ChannelQuality.sd);
    });

    test('a country-name group gives the country, not a category', () {
      final c = StoredChannel(
        key: 'k',
        sourceId: 's',
        name: 'Kanali 7',
        group: 'Albania',
      );
      final m = ChannelMeta.of(c);
      expect(m.country, 'AL');
      expect(m.categories, isEmpty);
      expect(m.languages, ['Albanian']);
    });

    test('stored languages are not marked inferred; unknown countries guess nothing', () {
      final c = StoredChannel(
        key: 'k',
        sourceId: 's',
        name: 'X',
        country: 'IN',
        languages: const ['Malayalam'],
      );
      expect(ChannelMeta.of(c).languagesInferred, isFalse);
      final india = StoredChannel(
        key: 'k',
        sourceId: 's',
        name: 'X',
        country: 'IN',
      );
      expect(ChannelMeta.of(india).languages, isEmpty);
    });
  });

  group('StoredChannel JSON', () {
    test('new fields round-trip; old records load with them empty', () {
      final c = StoredChannel(
        key: 'k',
        sourceId: 's',
        name: 'N',
        country: 'AL',
        languages: const ['Albanian'],
        quality: 'hd',
        number: 7,
      );
      final back = StoredChannel.fromJson(c.toJson());
      expect(back.country, 'AL');
      expect(back.languages, ['Albanian']);
      expect(back.quality, 'hd');
      expect(back.number, 7);
      expect(back.copyWith(dead: true).number, 7);
      expect(back.mergedOver(null, DateTime.utc(2026)).languages, ['Albanian']);

      final old = StoredChannel.fromJson({'key': 'k', 'src': 's', 'name': 'N'});
      expect(old.country, isNull);
      expect(old.languages, isEmpty);
      expect(old.quality, isNull);
      expect(old.number, isNull);
      expect(
        StoredChannel(
          key: 'k',
          sourceId: 's',
          name: 'N',
        ).toJson().containsKey('cc'),
        isFalse,
      );
    });
  });

  test('an M3U refresh stores country, languages, quality and number', () async {
    const body =
        '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="Kanali7.al" tvg-country="AL" tvg-chno="7" group-title="Albania",Kanali 7 Ⓖ\n'
        'https://s.example.test/1.m3u8\n'
        '#EXTINF:-1 tvg-id="Rock.us@SD" group-title="Music;Kids",Rock (1080p)\n'
        'https://s.example.test/2.m3u8\n'
        '#EXTINF:-1 tvg-language="English;Hindi" group-title="News",Desh\n'
        'https://s.example.test/3.m3u8\n';
    final store = InMemoryIptvStore();
    final reg = SourceRegistry(
      store,
      FakeHttp({'https://l.example.test/': (u, h) => reply(200, body)}),
    );
    await reg.add(
      Source(
        id: 's',
        kind: SourceKind.m3uUrl,
        name: 'L',
        location: 'https://l.example.test/p.m3u',
      ),
    );
    await reg.refresh('s');
    final ch = await store.channels('s');
    expect(ch[0].country, 'AL');
    expect(ch[0].number, 7);
    expect(ch[0].categories, isEmpty);
    expect(ch[1].country, 'US');
    expect(ch[1].quality, 'fhd');
    expect(ch[1].categories, ['Music', 'Kids']);
    expect(ch[2].languages, ['English', 'Hindi']);
    expect(ch[2].country, isNull);
  });
}

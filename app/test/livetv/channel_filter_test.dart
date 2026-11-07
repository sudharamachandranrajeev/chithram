import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/features/livetv/channel_filter.dart';
import 'package:chithram/src/features/livetv/livetv_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/iptv.dart';

final _sources = [
  Source(
    id: 'a',
    kind: SourceKind.m3uUrl,
    name: 'List A',
    location: 'http://a.test/a.m3u',
  ),
  Source(
    id: 'b',
    kind: SourceKind.m3uUrl,
    name: 'List B',
    location: 'http://b.test/b.m3u',
  ),
];

StoredChannel _ch(
  String key,
  String name, {
  String source = 'a',
  String? group,
  String? country,
  List<String> languages = const [],
  String? quality,
  int? number,
  int? ttfbMs,
  bool dead = false,
}) => StoredChannel(
  key: key,
  sourceId: source,
  name: name,
  url: 'http://c.test/$key.m3u8',
  group: group,
  country: country,
  languages: languages,
  quality: quality,
  number: number,
  ttfbMs: ttfbMs,
  dead: dead,
);

ChannelIndex _index() => ChannelIndex.build(_sources, {
  'a': [
    _ch(
      'a:1',
      'BBC News (1080p)',
      group: 'News',
      country: 'GB',
      languages: ['English'],
      number: 3,
      ttfbMs: 300,
    ),
    _ch(
      'a:2',
      'Sky Sports',
      group: 'Sports',
      country: 'GB',
      languages: ['English'],
      number: 1,
      ttfbMs: 100,
    ),
    _ch(
      'a:3',
      'France 24',
      group: 'News',
      country: 'FR',
      languages: ['French'],
      quality: 'hd',
      number: 2,
    ),
    _ch(
      'a:4',
      'Cartoon Club',
      group: 'Animation;Kids',
      country: 'US',
      dead: true,
    ),
  ],
  'b': [
    _ch(
      'b:1',
      'Al Jazeera',
      source: 'b',
      group: 'News',
      country: 'QA',
      languages: ['Arabic', 'English'],
      ttfbMs: 50,
    ),
    _ch('b:2', 'Unknown Thing', source: 'b'),
  ],
});

List<String> _names(FilterResult r) => [for (final c in r.visible) c.name];

int _count(FilterResult r, ChannelFacet f, String key) => r
    .options(f)
    .firstWhere(
      (o) => o.key == key,
      orElse: () => const FacetOption('', '', -1),
    )
    .count;

void main() {
  group('index', () {
    test('derives clean names, categories and facet labels', () {
      final i = _index();
      expect(i.byKey['a:1']!.name, 'BBC News');
      expect(i.byKey['a:4']!.meta.categories, ['Animation', 'Kids']);
      expect(i.label(ChannelFacet.country, 'GB'), 'United Kingdom');
      expect(i.label(ChannelFacet.source, 'b'), 'List B');
      expect(i.label(ChannelFacet.quality, 'fhd'), '1080p');
      expect(i.label(ChannelFacet.category, ''), 'Other');
    });
  });

  group('filter', () {
    test('no filter keeps playlist order and counts every facet', () {
      final r = applyChannelFilter(_index(), const ChannelFilter());
      expect(r.visible, hasLength(6));
      expect(r.total, 6);
      expect(_names(r).first, 'BBC News');
      expect(_count(r, ChannelFacet.category, 'News'), 3);
      expect(_count(r, ChannelFacet.country, 'GB'), 2);
      // A channel with two languages counts once in each; Cartoon Club has
      // none stored, so its language is inferred from its country (US).
      expect(_count(r, ChannelFacet.language, 'English'), 4);
      expect(_count(r, ChannelFacet.language, 'Arabic'), 1);
      expect(_count(r, ChannelFacet.source, 'b'), 2);
      // Unknown values sort last.
      expect(r.options(ChannelFacet.category).last.key, '');
    });

    test('values in one facet are OR, facets are AND', () {
      final i = _index();
      var f = const ChannelFilter().toggle(ChannelFacet.category, 'News');
      expect(_names(applyChannelFilter(i, f)), [
        'BBC News',
        'France 24',
        'Al Jazeera',
      ]);
      f = f.toggle(ChannelFacet.category, 'Sports');
      expect(applyChannelFilter(i, f).visible, hasLength(4));
      f = f.toggle(ChannelFacet.country, 'GB');
      expect(_names(applyChannelFilter(i, f)), ['BBC News', 'Sky Sports']);
    });

    test(
      "a facet's counts ignore its own selection but respect the others",
      () {
        final f = const ChannelFilter()
            .toggle(ChannelFacet.category, 'News')
            .toggle(ChannelFacet.country, 'GB');
        final r = applyChannelFilter(_index(), f);
        // Category counts: everything from GB, whatever its category.
        expect(_count(r, ChannelFacet.category, 'News'), 1);
        expect(_count(r, ChannelFacet.category, 'Sports'), 1);
        expect(r.countWithout(ChannelFacet.category), 2);
        // Country counts: every News channel, whatever its country.
        expect(_count(r, ChannelFacet.country, 'FR'), 1);
        expect(_count(r, ChannelFacet.country, 'QA'), 1);
        expect(r.countWithout(ChannelFacet.country), 3);
      },
    );

    test(
      'a picked value with no matches stays offered so it can be unpicked',
      () {
        final f = const ChannelFilter()
            .toggle(ChannelFacet.country, 'GB')
            .toggle(ChannelFacet.language, 'French');
        final r = applyChannelFilter(_index(), f);
        expect(r.visible, isEmpty);
        final fr = r
            .options(ChannelFacet.language)
            .firstWhere((o) => o.key == 'French');
        expect(fr.selected, isTrue);
        expect(fr.count, 0);
      },
    );

    test('unknown is a selectable value', () {
      final f = const ChannelFilter().toggle(ChannelFacet.country, '');
      expect(_names(applyChannelFilter(_index(), f)), ['Unknown Thing']);
    });

    test('search matches name, category, language and country words', () {
      final i = _index();
      expect(_names(applyChannelFilter(i, const ChannelFilter(query: 'bbc'))), [
        'BBC News',
      ]);
      expect(
        _names(applyChannelFilter(i, const ChannelFilter(query: 'kids'))),
        ['Cartoon Club'],
      );
      expect(
        _names(applyChannelFilter(i, const ChannelFilter(query: 'arabic'))),
        ['Al Jazeera'],
      );
      expect(
        _names(
          applyChannelFilter(i, const ChannelFilter(query: 'france news')),
        ),
        ['France 24'],
      );
      expect(
        applyChannelFilter(
          i,
          const ChannelFilter(query: 'united kingdom'),
        ).visible,
        hasLength(2),
      );
    });

    test('working only and favourites only', () {
      final i = _index();
      expect(
        applyChannelFilter(
          i,
          const ChannelFilter(workingOnly: true),
        ).visible.map((c) => c.key),
        isNot(contains('a:4')),
      );
      final fav = applyChannelFilter(
        i,
        const ChannelFilter(favouritesOnly: true),
        favourites: {'b:1', 'a:3'},
      );
      expect(_names(fav), ['France 24', 'Al Jazeera']);
    });

    test('cleared keeps search and sort; isActive and activeCount follow', () {
      final f = const ChannelFilter(
        query: 'x',
        sort: ChannelSort.nameAz,
        workingOnly: true,
      ).toggle(ChannelFacet.country, 'GB').toggle(ChannelFacet.country, 'FR');
      expect(f.isActive, isTrue);
      expect(f.activeCount, greaterThanOrEqualTo(2));
      final c = f.cleared();
      expect(c.query, 'x');
      expect(c.sort, ChannelSort.nameAz);
      expect(c.hasFacets, isFalse);
      expect(c.workingOnly, isFalse);
      expect(
        f.toggle(ChannelFacet.country, 'GB').selected(ChannelFacet.country),
        {'FR'},
      );
    });
  });

  group('sort', () {
    List<String> sorted(ChannelSort s, {List<String> recent = const []}) =>
        _names(
          applyChannelFilter(_index(), ChannelFilter(sort: s), recent: recent),
        );

    test('name A-Z and Z-A use the clean name', () {
      expect(sorted(ChannelSort.nameAz).take(3), [
        'Al Jazeera',
        'BBC News',
        'Cartoon Club',
      ]);
      expect(sorted(ChannelSort.nameZa).first, 'Unknown Thing');
    });

    test('fastest puts unprobed and dead channels last', () {
      final s = sorted(ChannelSort.fastest);
      expect(s.take(3), ['Al Jazeera', 'Sky Sports', 'BBC News']);
      expect(s.last, 'Cartoon Club');
    });

    test('channel number, then name for unnumbered', () {
      expect(sorted(ChannelSort.number).take(3), [
        'Sky Sports',
        'France 24',
        'BBC News',
      ]);
    });

    test('recently watched first, then playlist order', () {
      expect(sorted(ChannelSort.recent, recent: ['b:2', 'a:3']).take(3), [
        'Unknown Thing',
        'France 24',
        'BBC News',
      ]);
    });

    test('unknown stored names fall back to playlist order', () {
      expect(ChannelSort.byName('nope'), ChannelSort.playlist);
      expect(ChannelSort.byName('nameZa'), ChannelSort.nameZa);
    });
  });

  test('zap list keeps only playable channels, plus the picked one', () {
    final r = applyChannelFilter(_index(), const ChannelFilter());
    final dead = r.visible.firstWhere((c) => c.key == 'a:4');
    expect(
      zapList(r.visible, r.visible.first).map((c) => c.key),
      isNot(contains('a:4')),
    );
    final withDead = zapList(r.visible, dead);
    expect(withDead.map((c) => c.key), contains('a:4'));
    expect(withDead, hasLength(6));
  });

  test('11k channels: index and filter stay fast', () {
    const n = 11000;
    const countries = ['US', 'GB', 'IN', 'FR', 'DE', 'BR', 'ES', 'IT'];
    const groups = [
      'News',
      'Sports',
      'Movies',
      'Kids;Animation',
      'Music',
      'General',
    ];
    final channels = [
      for (var i = 0; i < n; i++)
        _ch(
          'a:$i',
          'Channel $i ${i % 3 == 0 ? '(720p)' : ''}',
          group: groups[i % groups.length],
          country: countries[i % countries.length],
          languages: [if (i.isEven) 'English' else 'Spanish'],
          ttfbMs: i % 500,
          dead: i % 11 == 0,
        ),
    ];
    final sw = Stopwatch()..start();
    final index = ChannelIndex.build(_sources, {'a': channels});
    final built = sw.elapsedMilliseconds;
    sw.reset();
    final f =
        const ChannelFilter(
              query: 'channel 1',
              sort: ChannelSort.nameAz,
              workingOnly: true,
            )
            .toggle(ChannelFacet.country, 'GB')
            .toggle(ChannelFacet.country, 'US')
            .toggle(ChannelFacet.category, 'News');
    final r = applyChannelFilter(index, f);
    final filtered = sw.elapsedMilliseconds;
    expect(index.length, n);
    expect(r.visible, isNotEmpty);
    // Generous bounds for slow CI machines; locally both are a few ms.
    expect(built, lessThan(1500), reason: 'build $built ms');
    expect(filtered, lessThan(250), reason: 'filter $filtered ms');
  });

  group('library', () {
    test('favourites toggle, newest first, and survive a reload', () async {
      final prefs = Prefs.memory();
      final lib = LiveTvLibrary(prefs);
      await lib.toggleFavourite('a');
      await lib.toggleFavourite('b');
      expect(lib.favourites, ['b', 'a']);
      expect(lib.isFavourite('a'), isTrue);
      await lib.toggleFavourite('a');
      expect(lib.favourites, ['b']);
      expect(LiveTvLibrary(prefs).favourites, ['b']);
    });

    test('recent moves a channel to the front and keeps 50', () async {
      final lib = LiveTvLibrary(Prefs.memory());
      for (var i = 0; i < 60; i++) {
        await lib.markWatched('c$i');
      }
      expect(lib.recent, hasLength(LiveTvLibrary.maxRecent));
      expect(lib.recent.first, 'c59');
      await lib.markWatched('c30');
      expect(lib.recent.first, 'c30');
      expect(lib.recent.where((k) => k == 'c30'), hasLength(1));
    });

    test(
      'bad stored JSON reads as empty; sort and grid have defaults',
      () async {
        final lib = LiveTvLibrary(
          Prefs.memory({
            LiveTvLibrary.favouritesKey: '{oops',
            LiveTvLibrary.recentKey: '{"a":1}',
          }),
        );
        expect(lib.favourites, isEmpty);
        expect(lib.recent, isEmpty);
        expect(lib.sort, ChannelSort.playlist);
        expect(lib.grid, isTrue);
        await lib.setSort(ChannelSort.fastest);
        await lib.setGrid(false);
        expect(lib.sort, ChannelSort.fastest);
        expect(lib.grid, isFalse);
      },
    );
  });
}

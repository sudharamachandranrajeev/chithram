import 'package:iptv/iptv.dart';

/// The facets Live TV filters on. Each channel has zero or more values per
/// facet; a channel with none counts under [unknownLabel].
enum ChannelFacet {
  category('Category', 'Other'),
  language('Language', 'Unknown'),
  country('Country', 'Unknown'),
  quality('Quality', 'Unknown'),
  source('Source', 'Unknown');

  const ChannelFacet(this.label, this.unknownLabel);
  final String label;
  final String unknownLabel;
}

enum ChannelSort {
  nameAz('Name A-Z'),
  nameZa('Name Z-A'),
  recent('Recently watched'),
  fastest('Fastest response'),
  playlist('Playlist order'),
  number('Channel number');

  const ChannelSort(this.label);
  final String label;

  static ChannelSort byName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return ChannelSort.playlist;
  }
}

/// One channel with everything filtering and sorting need, computed once per
/// snapshot so a filter change never re-parses names.
class IndexedChannel {
  IndexedChannel._(
    this.channel,
    this.meta,
    this.order,
    this.sortName,
    this.haystack,
    this.facetKeys,
  );

  final StoredChannel channel;
  final ChannelMeta meta;

  /// Position in the sources as listed (playlist order).
  final int order;
  final String sortName;

  /// Lower-case text a search matches against.
  final String haystack;

  /// Facet value keys, indexed by [ChannelFacet.index]. `''` is "unknown".
  final List<List<String>> facetKeys;

  String get key => channel.key;
  String get name => meta.displayName;
}

/// A facet value with how many channels would show if it were picked.
class FacetOption {
  const FacetOption(this.key, this.label, this.count, {this.selected = false});

  final String key;
  final String label;
  final int count;
  final bool selected;
}

/// Every channel of a snapshot, indexed. Build once per snapshot (11k
/// channels take a few tens of milliseconds); filtering then is one pass.
class ChannelIndex {
  ChannelIndex._(this.channels, this.byKey, this.sourceNames);

  factory ChannelIndex.build(
    List<Source> sources,
    Map<String, List<StoredChannel>> bySource,
  ) {
    final out = <IndexedChannel>[];
    final names = {for (final s in sources) s.id: s.name};
    for (final s in sources) {
      for (final c in bySource[s.id] ?? const <StoredChannel>[]) {
        final m = ChannelMeta.of(c);
        final cats = m.categories.isEmpty ? const [''] : m.categories;
        final langs = m.languages.isEmpty ? const [''] : m.languages;
        final keys = <List<String>>[
          cats,
          langs,
          [m.country ?? ''],
          [m.quality == ChannelQuality.unknown ? '' : m.quality.name],
          [c.sourceId],
        ];
        final hay = StringBuffer(m.displayName.toLowerCase())
          ..write(' ')
          ..write(m.categories.join(' ').toLowerCase())
          ..write(' ')
          ..write(m.languages.join(' ').toLowerCase());
        if (m.country != null) {
          hay
            ..write(' ')
            ..write(m.country!.toLowerCase())
            ..write(' ')
            ..write((m.countryName ?? '').toLowerCase());
        }
        if (c.group != null) hay.write(' ${c.group!.toLowerCase()}');
        out.add(
          IndexedChannel._(
            c,
            m,
            out.length,
            m.displayName.toLowerCase(),
            hay.toString(),
            keys,
          ),
        );
      }
    }
    return ChannelIndex._(out, {for (final c in out) c.key: c}, names);
  }

  static final empty = ChannelIndex._(const [], const {}, const {});

  final List<IndexedChannel> channels;
  final Map<String, IndexedChannel> byKey;
  final Map<String, String> sourceNames;

  int get length => channels.length;

  /// The text shown for a facet value.
  String label(ChannelFacet f, String key) {
    if (key.isEmpty) return f.unknownLabel;
    return switch (f) {
      ChannelFacet.country => countryNames[key] ?? key,
      ChannelFacet.quality => ChannelQuality.byName(key)?.label ?? key,
      ChannelFacet.source => sourceNames[key] ?? key,
      _ => key,
    };
  }
}

/// What the user asked to see. Immutable; the pages keep one and replace it.
class ChannelFilter {
  const ChannelFilter({
    this.query = '',
    this.facets = const {},
    this.workingOnly = false,
    this.favouritesOnly = false,
    this.sort = ChannelSort.playlist,
  });

  final String query;
  final Map<ChannelFacet, Set<String>> facets;

  /// Hide channels the probe found dead and those gone from the source.
  final bool workingOnly;
  final bool favouritesOnly;
  final ChannelSort sort;

  Set<String> selected(ChannelFacet f) => facets[f] ?? const {};

  bool get hasFacets => facets.values.any((s) => s.isNotEmpty);

  /// Something narrows the list (the sort does not count).
  bool get isActive =>
      query.trim().isNotEmpty || hasFacets || workingOnly || favouritesOnly;

  /// How many separate restrictions are on (for a "Filters (3)" badge).
  int get activeCount =>
      facets.values.fold(0, (n, s) => n + s.length) +
      (workingOnly ? 1 : 0) +
      (favouritesOnly ? 1 : 0) +
      (query.trim().isNotEmpty ? 1 : 0);

  ChannelFilter copyWith({
    String? query,
    Map<ChannelFacet, Set<String>>? facets,
    bool? workingOnly,
    bool? favouritesOnly,
    ChannelSort? sort,
  }) => ChannelFilter(
    query: query ?? this.query,
    facets: facets ?? this.facets,
    workingOnly: workingOnly ?? this.workingOnly,
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
    sort: sort ?? this.sort,
  );

  ChannelFilter withFacet(ChannelFacet f, Set<String> keys) =>
      copyWith(facets: {...facets, f: Set.unmodifiable(keys)});

  /// Adds [key] to facet [f], or removes it when it is there.
  ChannelFilter toggle(ChannelFacet f, String key) {
    final s = {...selected(f)};
    if (!s.remove(key)) s.add(key);
    return withFacet(f, s);
  }

  /// Everything off except the search text and the sort.
  ChannelFilter cleared() => ChannelFilter(query: query, sort: sort);

  /// A key for animations: changes when the facets or sort change, not when
  /// one more letter is typed.
  String get shapeKey => [
    for (final f in ChannelFacet.values)
      '${f.name}=${(selected(f).toList()..sort()).join(',')}',
    'w=$workingOnly',
    'f=$favouritesOnly',
    's=${sort.name}',
  ].join('|');
}

/// The channels to show and the facet counts for the filter bar.
class FilterResult {
  const FilterResult(this.visible, this.facets, this._countWithout, this.total);

  static const empty = FilterResult([], {}, {}, 0);

  final List<IndexedChannel> visible;

  /// Options per facet: counts are what the list would hold if that value
  /// were picked too (the other facets applied, this one ignored), the usual
  /// faceted-search rule so a multi-select within a facet never shows 0s.
  final Map<ChannelFacet, List<FacetOption>> facets;
  final Map<ChannelFacet, int> _countWithout;
  final int total;

  /// How many channels show with facet [f] cleared ("All (n)").
  int countWithout(ChannelFacet f) => _countWithout[f] ?? visible.length;

  List<FacetOption> options(ChannelFacet f) => facets[f] ?? const [];
}

/// Filters and sorts [index]. One pass over the channels: each channel is
/// tested against every facet once, and counts go to the facets it would
/// pass if that facet alone were dropped. No step is worse than O(n log n).
FilterResult applyChannelFilter(
  ChannelIndex index,
  ChannelFilter f, {
  Set<String> favourites = const {},
  List<String> recent = const [],
}) {
  final tokens = f.query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  const facets = ChannelFacet.values;
  final active = [for (final x in facets) f.selected(x).isNotEmpty];
  final counts = [for (final _ in facets) <String, int>{}];
  final without = List<int>.filled(facets.length, 0);
  final visible = <IndexedChannel>[];

  for (final c in index.channels) {
    if (f.workingOnly && !c.channel.playable) continue;
    if (f.favouritesOnly && !favourites.contains(c.key)) continue;
    if (tokens.isNotEmpty && !tokens.every(c.haystack.contains)) continue;
    var fails = 0;
    var failed = -1;
    for (var i = 0; i < facets.length; i++) {
      if (!active[i]) continue;
      final sel = f.facets[facets[i]]!;
      if (!c.facetKeys[i].any(sel.contains)) {
        fails++;
        failed = i;
        if (fails > 1) break;
      }
    }
    if (fails > 1) continue;
    if (fails == 0) {
      visible.add(c);
      for (var i = 0; i < facets.length; i++) {
        without[i]++;
        for (final k in c.facetKeys[i]) {
          counts[i][k] = (counts[i][k] ?? 0) + 1;
        }
      }
    } else {
      without[failed]++;
      for (final k in c.facetKeys[failed]) {
        counts[failed][k] = (counts[failed][k] ?? 0) + 1;
      }
    }
  }

  _sort(visible, f.sort, recent);

  final options = <ChannelFacet, List<FacetOption>>{};
  for (var i = 0; i < facets.length; i++) {
    final facet = facets[i];
    final sel = f.selected(facet);
    final list = [
      for (final e in counts[i].entries)
        FacetOption(
          e.key,
          index.label(facet, e.key),
          e.value,
          selected: sel.contains(e.key),
        ),
      // A picked value stays offered (with 0) so it can be unpicked.
      for (final k in sel)
        if (!counts[i].containsKey(k))
          FacetOption(k, index.label(facet, k), 0, selected: true),
    ];
    if (facet == ChannelFacet.quality) {
      int rank(FacetOption o) =>
          o.key.isEmpty ? 99 : (ChannelQuality.byName(o.key)?.index ?? 98);
      list.sort((a, b) => rank(a).compareTo(rank(b)));
    } else {
      // Most channels first; "unknown" last; ties by name.
      list.sort((a, b) {
        if (a.key.isEmpty != b.key.isEmpty) return a.key.isEmpty ? 1 : -1;
        final c = b.count.compareTo(a.count);
        return c != 0
            ? c
            : a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    }
    options[facet] = list;
  }
  return FilterResult(visible, options, {
    for (var i = 0; i < facets.length; i++) facets[i]: without[i],
  }, index.length);
}

void _sort(List<IndexedChannel> list, ChannelSort sort, List<String> recent) {
  int byOrder(IndexedChannel a, IndexedChannel b) => a.order.compareTo(b.order);
  int byName(IndexedChannel a, IndexedChannel b) {
    final c = a.sortName.compareTo(b.sortName);
    return c != 0 ? c : byOrder(a, b);
  }

  switch (sort) {
    case ChannelSort.playlist:
      break; // already in source order
    case ChannelSort.nameAz:
      list.sort(byName);
    case ChannelSort.nameZa:
      list.sort((a, b) => byName(b, a));
    case ChannelSort.recent:
      final rank = {for (var i = 0; i < recent.length; i++) recent[i]: i};
      list.sort((a, b) {
        final c = (rank[a.key] ?? 1 << 30).compareTo(rank[b.key] ?? 1 << 30);
        return c != 0 ? c : byOrder(a, b);
      });
    case ChannelSort.fastest:
      // Unprobed and unplayable channels go last.
      int ms(IndexedChannel c) =>
          !c.channel.playable ? 1 << 30 : (c.channel.ttfbMs ?? (1 << 29));
      list.sort((a, b) {
        final c = ms(a).compareTo(ms(b));
        return c != 0 ? c : byName(a, b);
      });
    case ChannelSort.number:
      list.sort((a, b) {
        final c = (a.meta.number ?? 1 << 30).compareTo(
          b.meta.number ?? 1 << 30,
        );
        return c != 0 ? c : byName(a, b);
      });
  }
}

/// The channels worth zapping through: playable ones in [list] order, plus
/// [picked] (it plays even if it looked dead).
List<StoredChannel> zapList(List<IndexedChannel> list, IndexedChannel picked) =>
    [
      for (final c in list)
        if (c.channel.playable || identical(c, picked)) c.channel,
    ];

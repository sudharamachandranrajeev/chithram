import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart';

import '../../../theme.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/phone/phone_widgets.dart';
import '../add_playlist.dart';
import '../channel_filter.dart';
import '../iptv_service.dart';
import '../livetv_controller.dart';
import '../livetv_widgets.dart';
import '../suggestions.dart';

/// Live TV on a phone: search, your sources (pull down to refresh them), and
/// two rows of chips that stay at the top while the channel list scrolls:
/// sort and filters (each opens a bottom sheet with counts), then the
/// categories. Favourites and recents sit above the list; a star or a long
/// press marks a favourite, and a tap plays. With no sources it offers to add
/// one; nothing is downloaded until you choose and confirm.
class PhoneLiveTvPage extends StatefulWidget {
  const PhoneLiveTvPage({super.key});

  @override
  State<PhoneLiveTvPage> createState() => _PhoneLiveTvPageState();
}

class _PhoneLiveTvPageState extends State<PhoneLiveTvPage>
    with LiveTvControllerHost {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final snap = c.snapshot;
    if (snap == null) return const Center(child: CircularProgressIndicator());
    if (snap.sources.isEmpty) return _Empty(service: c.service);

    final visible = c.visible;
    final showRows = !c.filter.isActive;
    final favourites = showRows ? c.favourites : const <IndexedChannel>[];
    final recent = showRows ? c.recent : const <IndexedChannel>[];
    final cats = quickCategories(c);
    final selectedSources = c.filter.selected(ChannelFacet.source);
    final categoryChips = cats.length <= 1
        ? const <Widget>[]
        : [
            _GroupChip(
              key: LiveTvFilterKeys.allCategories,
              label: 'All (${c.result.countWithout(ChannelFacet.category)})',
              selected: c.filter.selected(ChannelFacet.category).isEmpty,
              onTap: () => c.clearFacet(ChannelFacet.category),
            ),
            for (final o in cats)
              _GroupChip(
                key: LiveTvFilterKeys.category(o.key),
                label: '${o.label} (${o.count})',
                selected: o.selected,
                onTap: () => c.toggleFacet(ChannelFacet.category, o.key),
              ),
          ];

    return RefreshIndicator(
      onRefresh: c.refreshAll,
      child: CustomScrollView(
        key: const PageStorageKey<String>('phone-livetv-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _SearchField(controller: c, text: _search),
          ),
          const SliverToBoxAdapter(child: PhoneSectionTitle('Sources')),
          SliverList.list(
            children: [
              for (final s in snap.sources)
                _SourceTile(
                  source: s,
                  channels: snap.channels[s.id]?.length ?? 0,
                  busy: c.refreshing.contains(s.id),
                  selected: selectedSources.contains(s.id),
                  onSelect: () => c.toggleFacet(ChannelFacet.source, s.id),
                  service: c.service,
                ),
              ListTile(
                key: LiveTvKeys.addPlaylist,
                minTileHeight: 56,
                leading: const Icon(Icons.add_rounded),
                title: const Text('Add playlist'),
                subtitle: const Text('A link or a community catalogue'),
                onTap: () => showAddPlaylist(context, c.service),
              ),
            ],
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _ChipsHeader(
              // A landscape phone has little height to spare, so the filters
              // and categories scroll side by side in one pinned row there.
              sideBySide: MediaQuery.sizeOf(context).height < 520,
              active: c.filter.isActive,
              rows: [
                _filterChips(context, c),
                if (categoryChips.isNotEmpty) categoryChips,
              ],
            ),
          ),
          if (favourites.isNotEmpty) ..._row('Favourites', favourites),
          if (recent.isNotEmpty) ..._row('Recently watched', recent),
          if (favourites.isNotEmpty || recent.isNotEmpty)
            const SliverToBoxAdapter(child: PhoneSectionTitle('All channels')),
          SliverFixedExtentList(
            itemExtent: 76,
            delegate: SliverChildBuilderDelegate(
              (context, i) => _ChannelTile(
                key: LiveTvFilterKeys.channel(visible[i].key),
                channel: visible[i],
                favourite: c.isFavourite(visible[i].key),
                onPlay: () => c.play(context, visible[i], visible),
                onFavourite: () => c.toggleFavourite(visible[i].key),
              ),
              childCount: visible.length,
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  PhoneNote(
                    c.filter.isActive
                        ? 'No channels match these filters.'
                        : 'No channels here yet.',
                  ),
                  if (c.filter.isActive)
                    OutlinedButton.icon(
                      onPressed: () {
                        _search.clear();
                        c.setFilter(c.filter.cleared().copyWith(query: ''));
                      },
                      icon: const Icon(Icons.filter_alt_off_rounded),
                      label: const Text('Clear filters and search'),
                    ),
                ],
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Widget> _filterChips(BuildContext context, LiveTvController c) {
    final f = c.filter;
    return [
      // First, so the result count and a way out are always in view.
      if (f.isActive)
        ActionChip(
          key: LiveTvFilterKeys.clear,
          avatar: const Icon(Icons.filter_alt_off_rounded, size: 18),
          label: Text('Clear (${c.visible.length} of ${c.result.total})'),
          onPressed: c.clearFilters,
        ),
      _SheetChip(
        key: LiveTvFilterKeys.sort,
        icon: Icons.swap_vert_rounded,
        label: f.sort.label,
        selected: false,
        onTap: () => _showSortSheet(context, c),
      ),
      for (final facet in offeredFacets(c, category: false))
        _SheetChip(
          key: LiveTvFilterKeys.facet(facet),
          icon: facetIcon(facet),
          label: facetChipText(c, facet),
          selected: f.selected(facet).isNotEmpty,
          onTap: () => _showFacetSheet(context, c, facet),
        ),
      FilterChip(
        key: LiveTvFilterKeys.favouritesOnly,
        avatar: Icon(
          f.favouritesOnly ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 18,
        ),
        showCheckmark: false,
        label: const Text('Favourites'),
        selected: f.favouritesOnly,
        onSelected: (v) => c.setFilter(f.copyWith(favouritesOnly: v)),
      ),
      FilterChip(
        key: LiveTvFilterKeys.workingOnly,
        label: const Text('Working only'),
        selected: f.workingOnly,
        onSelected: (v) => c.setFilter(f.copyWith(workingOnly: v)),
      ),
    ];
  }

  List<Widget> _row(String title, List<IndexedChannel> list) => [
    SliverToBoxAdapter(child: PhoneSectionTitle(title)),
    SliverToBoxAdapter(
      child: SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: phoneGutter),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.s12),
          itemBuilder: (context, i) => _MiniCard(
            channel: list[i],
            onPlay: () => controller.play(context, list[i], list),
          ),
        ),
      ),
    ),
  ];
}

Future<void> _showSortSheet(BuildContext context, LiveTvController c) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (ctx, _) => RadioGroup<ChannelSort>(
            groupValue: c.filter.sort,
            onChanged: (s) {
              if (s != null) c.setFilter(c.filter.copyWith(sort: s));
              Navigator.of(ctx).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(phoneGutter, 0, phoneGutter, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sort by',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                for (final s in ChannelSort.values)
                  RadioListTile<ChannelSort>(
                    key: LiveTvFilterKeys.sortOption(s),
                    value: s,
                    title: Text(s.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> _showFacetSheet(
  BuildContext context,
  LiveTvController c,
  ChannelFacet facet,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    minChildSize: 0.3,
    maxChildSize: 0.92,
    builder: (ctx, _) => SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(phoneGutter, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    facet.label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => c.clearFacet(facet),
                  child: const Text('Clear'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FacetOptionsList(controller: c, facet: facet),
          ),
        ],
      ),
    ),
  ),
);

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.text});

  final LiveTvController controller;
  final TextEditingController text;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(phoneGutter, Space.s8, phoneGutter, 0),
      child: ListenableBuilder(
        listenable: text,
        builder: (context, _) => TextField(
          key: LiveTvFilterKeys.search,
          controller: text,
          onChanged: controller.setQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            hintText: 'Search channels',
            filled: true,
            fillColor: colors.surface,
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.pill),
              borderSide: BorderSide.none,
            ),
            suffixIcon: text.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      text.clear();
                      controller.setQuery('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.service});

  final IptvService service;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const PhoneNote(
          'Add an M3U playlist you have, or choose a community catalogue. '
          'Nothing is downloaded until you choose one and confirm.',
        ),
        ListTile(
          key: LiveTvKeys.addPlaylist,
          minTileHeight: 64,
          leading: Icon(
            Icons.link_rounded,
            color: ChithramColors.of(context).accent,
          ),
          title: const Text('Add playlist'),
          subtitle: const Text('An M3U link'),
          onTap: () => addPlaylistFromUrl(context, service),
        ),
        for (final s in CatalogueSuggestion.values)
          ListTile(
            key: LiveTvKeys.suggestion(s),
            minTileHeight: 64,
            leading: Icon(
              Icons.public_rounded,
              color: ChithramColors.of(context).accent,
            ),
            title: Text(s.name),
            subtitle: Text(
              s.blurb,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => addSuggestionFlow(context, service, s),
          ),
      ],
    );
  }
}

enum _SourceAction { refresh, remove }

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.channels,
    required this.busy,
    required this.selected,
    required this.onSelect,
    required this.service,
  });

  final Source source;
  final int channels;
  final bool busy;
  final bool selected;
  final VoidCallback onSelect;
  final IptvService service;

  @override
  Widget build(BuildContext context) {
    final problem = sourceHasProblem(source);
    return ListTile(
      key: ValueKey('livetv-source-${source.id}'),
      minTileHeight: 64,
      selected: selected,
      selectedTileColor: ChithramColors.of(context).accent
          .withValues(alpha: 0.18),
      leading: Icon(
        selected
            ? Icons.check_circle_rounded
            : (problem ? Icons.warning_amber_rounded : Icons.list_alt_rounded),
      ),
      title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        sourceDetail(source, channels, busy),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<_SourceAction>(
        key: ValueKey('livetv-menu-${source.id}'),
        tooltip: 'Source options',
        onSelected: (a) {
          switch (a) {
            case _SourceAction.refresh:
              service.refresh(source.id);
            case _SourceAction.remove:
              confirmRemoveSource(context, service, source);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _SourceAction.refresh,
            key: ValueKey('livetv-refresh-${source.id}'),
            child: const Text('Refresh'),
          ),
          PopupMenuItem(
            value: _SourceAction.remove,
            key: ValueKey('livetv-remove-${source.id}'),
            child: const Text('Remove'),
          ),
        ],
      ),
      onTap: onSelect,
    );
  }
}

/// One or two rows of chips that stay pinned under the app bar; with
/// [sideBySide] the rows share one line, each scrolling on its own.
class _ChipsHeader extends SliverPersistentHeaderDelegate {
  _ChipsHeader({
    required this.rows,
    required this.active,
    this.sideBySide = false,
  });

  final List<List<Widget>> rows;
  final bool sideBySide;

  /// Whether any filter is on. The rows scroll back to the start when it
  /// changes, so the Clear chip (first) is in view.
  final bool active;

  static const _rowHeight = 56.0;

  @override
  double get minExtent => _rowHeight * (sideBySide ? 1 : rows.length);
  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = ChithramColors.of(context);
    return Material(
      color: colors.background,
      elevation: overlapsContent || shrinkOffset > 0 ? 2 : 0,
      shadowColor: Colors.black,
      child: sideBySide
          ? SizedBox(
              height: _rowHeight,
              child: Row(
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 1,
                        indent: 12,
                        endIndent: 12,
                        color: colors.hairline,
                      ),
                    Expanded(child: _chipRow(i, row)),
                  ],
                ],
              ),
            )
          : Column(
              children: [
                for (final (i, row) in rows.indexed)
                  SizedBox(height: _rowHeight, child: _chipRow(i, row)),
              ],
            ),
    );
  }

  Widget _chipRow(int i, List<Widget> row) => ListView.separated(
    key: ValueKey('livetv-chips-$i-$active'),
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 2),
    itemCount: row.length,
    separatorBuilder: (_, _) => const SizedBox(width: 8),
    itemBuilder: (_, i) => Center(child: row[i]),
  );

  @override
  bool shouldRebuild(_ChipsHeader old) => true;
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}

/// A chip that opens a bottom sheet; the arrow says so.
class _SheetChip extends StatelessWidget {
  const _SheetChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
    avatar: Icon(icon, size: 18),
    showCheckmark: false,
    selected: selected,
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 2),
        const Icon(Icons.arrow_drop_down_rounded, size: 20),
      ],
    ),
    onSelected: (_) => onTap(),
  );
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.channel, required this.onPlay});

  final IndexedChannel channel;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    return SizedBox(
      width: 96,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPlay,
        child: Column(
          children: [
            const SizedBox(height: 6),
            ChannelLogo(channel: channel, size: 60, radius: 14),
            const SizedBox(height: 6),
            Text(
              channel.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    super.key,
    required this.channel,
    required this.favourite,
    required this.onPlay,
    required this.onFavourite,
  });

  final IndexedChannel channel;
  final bool favourite;
  final VoidCallback onPlay;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final ch = channel;
    final cats = ch.meta.categories.join(' · ');
    return Opacity(
      opacity: ch.channel.playable ? 1 : 0.55,
      child: ListTile(
        minTileHeight: 76,
        leading: ChannelLogo(channel: ch, size: 48, radius: 10),
        title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cats.isNotEmpty)
              Text(
                cats,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.textDim),
              ),
            const SizedBox(height: 3),
            BadgeRow(badgesFor(ch), max: 3),
          ],
        ),
        trailing: IconButton(
          key: LiveTvFilterKeys.favourite(ch.key),
          tooltip: favourite ? 'Remove from favourites' : 'Add to favourites',
          onPressed: onFavourite,
          icon: Icon(
            favourite ? Icons.star_rounded : Icons.star_outline_rounded,
            color: favourite ? colors.accent : colors.textDim,
          ),
        ),
        onTap: onPlay,
        onLongPress: onFavourite,
      ),
    );
  }
}

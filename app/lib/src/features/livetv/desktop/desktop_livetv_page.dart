import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart' show ChannelQuality;

import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/tv/focus_card.dart';
import '../add_playlist.dart';
import '../channel_filter.dart';
import '../livetv_controller.dart';
import '../livetv_page.dart' show LiveTvEmptyState;
import '../livetv_widgets.dart';

/// Live TV in a desktop window: a header with search, sort, view and
/// sources; a filter bar of facet dropdowns with counts; Favourites and
/// Recently watched rows; then the channels as a grid of cards or a dense
/// list. Mouse first, with hover feedback; the keyboard still reaches every
/// control.
class DesktopLiveTvPage extends StatefulWidget {
  const DesktopLiveTvPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  State<DesktopLiveTvPage> createState() => _DesktopLiveTvPageState();
}

class _DesktopLiveTvPageState extends State<DesktopLiveTvPage>
    with LiveTvControllerHost {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = controller;
    final snap = c.snapshot;
    final pad = EdgeInsets.all(d.gutter);
    if (snap == null) return const Center(child: CircularProgressIndicator());
    if (snap.sources.isEmpty) {
      return LiveTvEmptyState(
        focus: widget.focus,
        service: c.service,
        padding: pad,
      );
    }

    final motion = Motion.of(context);
    final grid = c.library.grid;
    final showRows = !c.filter.isActive;
    final favourites = showRows ? c.favourites : const <IndexedChannel>[];
    final recent = showRows ? c.recent : const <IndexedChannel>[];
    final cats = quickCategories(c);

    return Padding(
      padding: EdgeInsets.fromLTRB(d.gutter, d.gutter, d.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(controller: c, search: _search, focus: widget.focus),
          const SizedBox(height: Space.s16),
          _FilterBar(controller: c),
          if (cats.length > 1) ...[
            const SizedBox(height: Space.s12),
            _CategoryStrip(controller: c, options: cats),
          ],
          const SizedBox(height: Space.s8),
          Expanded(
            child: AnimatedSwitcher(
              duration: motion.expandTime,
              switchInCurve: Motion.curve,
              switchOutCurve: Motion.curve,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.015),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: CustomScrollView(
                key: ValueKey('${c.filter.shapeKey}|grid=$grid'),
                slivers: [
                  if (favourites.isNotEmpty)
                    ..._row(
                      context,
                      'Favourites',
                      favourites,
                      Icons.star_rounded,
                    ),
                  if (recent.isNotEmpty)
                    ..._row(
                      context,
                      'Recently watched',
                      recent,
                      Icons.history_rounded,
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        2,
                        Space.s16,
                        2,
                        Space.s12,
                      ),
                      child: Text(
                        c.filter.isActive ? 'Results' : 'All channels',
                        style: d.type.row,
                      ),
                    ),
                  ),
                  if (c.visible.isEmpty)
                    SliverToBoxAdapter(
                      child: _NoResults(controller: c, search: _search),
                    )
                  else if (grid)
                    _grid(c)
                  else ...[
                    const SliverToBoxAdapter(child: _ListHeader()),
                    _list(c),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: Space.s32)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _row(
    BuildContext context,
    String title,
    List<IndexedChannel> list,
    IconData icon,
  ) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, Space.s16, 2, Space.s8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.accent),
              const SizedBox(width: 8),
              Text(title, style: d.type.row),
              const SizedBox(width: 8),
              Text(
                '${list.length}',
                style: d.type.meta.copyWith(color: colors.textDim),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s12),
            itemBuilder: (context, i) => SizedBox(
              width: 320,
              child: _ChannelCard(
                channel: list[i],
                favourite: controller.isFavourite(list[i].key),
                onPlay: () => controller.play(context, list[i], list),
                onFavourite: () => controller.toggleFavourite(list[i].key),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _grid(LiveTvController c) {
    final visible = c.visible;
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 88,
        crossAxisSpacing: Space.s12,
        mainAxisSpacing: Space.s12,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => _ChannelCard(
          key: LiveTvFilterKeys.channel(visible[i].key),
          channel: visible[i],
          favourite: c.isFavourite(visible[i].key),
          onPlay: () => c.play(context, visible[i], visible),
          onFavourite: () => c.toggleFavourite(visible[i].key),
        ),
        childCount: visible.length,
      ),
    );
  }

  Widget _list(LiveTvController c) {
    final visible = c.visible;
    return SliverFixedExtentList(
      itemExtent: 56,
      delegate: SliverChildBuilderDelegate(
        (context, i) => _ChannelListRow(
          key: LiveTvFilterKeys.channel(visible[i].key),
          channel: visible[i],
          favourite: c.isFavourite(visible[i].key),
          striped: i.isOdd,
          onPlay: () => c.play(context, visible[i], visible),
          onFavourite: () => c.toggleFavourite(visible[i].key),
        ),
        childCount: visible.length,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.search,
    required this.focus,
  });

  final LiveTvController controller;
  final TextEditingController search;
  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final c = controller;
    final sources = c.snapshot!.sources.length;
    final total = c.result.total;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Live TV', style: d.type.h1),
              const SizedBox(height: 2),
              Text(
                '$total channels from $sources ${sources == 1 ? 'source' : 'sources'}',
                style: d.type.meta.copyWith(color: colors.textDim),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 320,
          height: 40,
          child: ListenableBuilder(
            listenable: search,
            builder: (context, _) => TextField(
              key: LiveTvFilterKeys.search,
              controller: search,
              onChanged: c.setQuery,
              style: d.type.body,
              decoration: InputDecoration(
                hintText: 'Search channels, countries, languages',
                isDense: true,
                filled: true,
                fillColor: colors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: colors.textDim,
                ),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        iconSize: 18,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          search.clear();
                          c.setQuery('');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  borderSide: BorderSide(
                    color: colors.accent.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.s12),
        _SortMenu(controller: c, focusNode: focus.entry),
        const SizedBox(width: Space.s8),
        _ViewToggle(controller: c),
        const SizedBox(width: Space.s8),
        _SourcesButton(controller: c),
        const SizedBox(width: Space.s8),
        FilledButton.icon(
          key: LiveTvKeys.addPlaylist,
          onPressed: () => showAddPlaylist(context, c.service),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add playlist'),
        ),
      ],
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.controller, this.focusNode});

  final LiveTvController controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        for (final s in ChannelSort.values)
          MenuItemButton(
            key: LiveTvFilterKeys.sortOption(s),
            leadingIcon: Icon(
              c.filter.sort == s ? Icons.check_rounded : null,
              size: 18,
            ),
            onPressed: () => c.setFilter(c.filter.copyWith(sort: s)),
            child: Text(s.label),
          ),
      ],
      builder: (context, menu, _) => _PillButton(
        key: LiveTvFilterKeys.sort,
        focusNode: focusNode,
        icon: Icons.swap_vert_rounded,
        label: c.filter.sort.label,
        trailing: Icons.expand_more_rounded,
        tooltip: 'Sort channels',
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.controller});

  final LiveTvController controller;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final grid = controller.library.grid;
    Widget seg(bool forGrid, IconData icon, String tip) => Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: () => controller.library.setGrid(forGrid),
        child: AnimatedContainer(
          duration: Motion.of(context).hoverPressTime,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: grid == forGrid
                ? colors.accent.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Icon(
            icon,
            size: 18,
            color: grid == forGrid ? colors.accent : colors.textDim,
          ),
        ),
      ),
    );
    return Container(
      key: LiveTvFilterKeys.viewToggle,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(true, Icons.grid_view_rounded, 'Grid'),
          seg(false, Icons.view_list_rounded, 'List'),
        ],
      ),
    );
  }
}

class _SourcesButton extends StatelessWidget {
  const _SourcesButton({required this.controller});

  final LiveTvController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final sources = c.snapshot!.sources;
    final busy = c.refreshing.isNotEmpty;
    final problem = sources.any(sourceHasProblem);
    return Builder(
      builder: (anchor) => _PillButton(
        key: LiveTvFilterKeys.sources,
        icon: Icons.playlist_play_rounded,
        label: 'Sources (${sources.length})',
        tooltip: 'Playlists: refresh or remove',
        status: busy
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (problem
                  ? const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFFFB74D),
                    )
                  : null),
        onTap: () => _showPopover(
          anchor,
          width: 380,
          builder: (ctx) => _SourcesPanel(controller: c),
        ),
      ),
    );
  }
}

class _SourcesPanel extends StatelessWidget {
  const _SourcesPanel({required this.controller});

  final LiveTvController controller;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final d = Dims.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final snap = c.snapshot!;
        final selected = c.filter.selected(ChannelFacet.source);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Sources', style: d.type.card),
            ),
            for (final s in snap.sources)
              ListTile(
                key: ValueKey('livetv-source-${s.id}'),
                dense: true,
                selected: selected.contains(s.id),
                selectedTileColor: colors.accent.withValues(alpha: 0.14),
                selectedColor: colors.text,
                leading: Icon(
                  sourceHasProblem(s)
                      ? Icons.warning_amber_rounded
                      : Icons.playlist_play_rounded,
                  color: sourceHasProblem(s)
                      ? const Color(0xFFFFB74D)
                      : colors.accent,
                ),
                title: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  sourceDetail(
                    s,
                    snap.channels[s.id]?.length ?? 0,
                    c.refreshing.contains(s.id),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textDim),
                ),
                onTap: () => c.toggleFacet(ChannelFacet.source, s.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: ValueKey('livetv-refresh-${s.id}'),
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: c.refreshing.contains(s.id)
                          ? null
                          : () => c.service.refresh(s.id),
                    ),
                    IconButton(
                      key: ValueKey('livetv-remove-${s.id}'),
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await confirmRemoveSource(context, c.service, s);
                      },
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => c.refreshAll(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh all'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      showAddPlaylist(context, c.service);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add playlist'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Facet dropdowns, Favourites and Working-only toggles, the count and Clear.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final LiveTvController controller;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final c = controller;
    final f = c.filter;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: Space.s8,
            runSpacing: Space.s8,
            children: [
              for (final facet in offeredFacets(c))
                Builder(
                  builder: (anchor) => _PillButton(
                    key: LiveTvFilterKeys.facet(facet),
                    icon: facetIcon(facet),
                    label: facetChipText(c, facet),
                    trailing: Icons.expand_more_rounded,
                    selected: f.selected(facet).isNotEmpty,
                    onTap: () => _showPopover(
                      anchor,
                      width: 300,
                      maxHeight: 440,
                      builder: (ctx) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(facet.label, style: d.type.card),
                                ),
                                TextButton(
                                  onPressed: () => c.clearFacet(facet),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: FacetOptionsList(
                              controller: c,
                              facet: facet,
                              shrinkWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              _PillButton(
                key: LiveTvFilterKeys.favouritesOnly,
                icon: f.favouritesOnly
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                label: 'Favourites',
                selected: f.favouritesOnly,
                onTap: () =>
                    c.setFilter(f.copyWith(favouritesOnly: !f.favouritesOnly)),
              ),
              _PillButton(
                key: LiveTvFilterKeys.workingOnly,
                icon: Icons.check_circle_outline_rounded,
                label: 'Working only',
                selected: f.workingOnly,
                onTap: () =>
                    c.setFilter(f.copyWith(workingOnly: !f.workingOnly)),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.s12),
        Text(
          f.isActive
              ? '${c.visible.length} of ${c.result.total}'
              : '${c.result.total} channels',
          style: d.type.meta.copyWith(color: colors.textDim),
        ),
        AnimatedSize(
          duration: Motion.of(context).expandTime,
          child: f.isActive
              ? Padding(
                  padding: const EdgeInsets.only(left: Space.s8),
                  child: TextButton.icon(
                    key: LiveTvFilterKeys.clear,
                    // As tall as the chips, so the bar does not jump.
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      fixedSize: const Size.fromHeight(36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: c.clearFilters,
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                    label: const Text('Clear'),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.controller, required this.options});

  final LiveTvController controller;
  final List<FacetOption> options;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CategoryPill(
            key: LiveTvFilterKeys.allCategories,
            label: 'All',
            count: c.result.countWithout(ChannelFacet.category),
            selected: c.filter.selected(ChannelFacet.category).isEmpty,
            onTap: () => c.clearFacet(ChannelFacet.category),
          ),
          for (final o in options)
            _CategoryPill(
              key: LiveTvFilterKeys.category(o.key),
              label: o.label,
              count: o.count,
              selected: o.selected,
              onTap: () => c.toggleFacet(ChannelFacet.category, o.key),
            ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final motion = Motion.of(context);
    final fg = selected ? colors.onAccent : colors.text;
    return Padding(
      padding: const EdgeInsets.only(right: Space.s8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: onTap,
          child: AnimatedContainer(
            duration: motion.hoverPressTime,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.accent : colors.surface,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: TextStyle(fontWeight: FontWeight.w600, color: fg),
                  ),
                  TextSpan(
                    text: '  $count',
                    style: TextStyle(color: fg.withValues(alpha: 0.65)),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded button for the header and filter bar; accent-tinted when
/// [selected], highlighted under the mouse.
class _PillButton extends StatefulWidget {
  const _PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.tooltip,
    this.status,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final IconData? trailing;
  final bool selected;
  final String? tooltip;
  final Widget? status;
  final FocusNode? focusNode;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final motion = Motion.of(context);
    final sel = widget.selected;
    final fg = sel ? colors.accent : colors.text;
    Widget body = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: widget.focusNode,
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: motion.hoverPressTime,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: sel
                  ? colors.accent.withValues(alpha: _hover ? 0.26 : 0.18)
                  : (_hover ? colors.surfaceHigh : colors.surface),
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(
                color: sel
                    ? colors.accent.withValues(alpha: 0.6)
                    : colors.glassEdge,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 17, color: fg),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                if (widget.status != null) ...[
                  const SizedBox(width: 6),
                  widget.status!,
                ],
                if (widget.trailing != null) ...[
                  const SizedBox(width: 2),
                  Icon(
                    widget.trailing,
                    size: 18,
                    color: fg.withValues(alpha: 0.8),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      body = Tooltip(message: widget.tooltip!, child: body);
    }
    return body;
  }
}

/// Opens [builder] in a panel just under [anchor] (a filter chip), like a
/// dropdown but able to hold a search field and a long list.
Future<void> _showPopover(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 300,
  double maxHeight = 480,
}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero);
  final rect = topLeft & box.size;
  return showGeneralDialog<void>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.of(anchor).expandTime,
    pageBuilder: (ctx, _, _) {
      final screen = MediaQuery.sizeOf(ctx);
      final left = rect.left.clamp(
        8.0,
        (screen.width - width - 8).clamp(8.0, double.infinity),
      );
      final top = rect.bottom + 6;
      final room = (screen.height - top - 12).clamp(160.0, maxHeight);
      final colors = ChithramColors.of(ctx);
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: room),
              child: Material(
                color: colors.surface,
                elevation: 12,
                shadowColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.button + 2),
                  side: BorderSide(color: colors.glassEdge),
                ),
                clipBehavior: Clip.antiAlias,
                child: builder(ctx),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Motion.curve),
      child: ScaleTransition(
        alignment: Alignment.topLeft,
        scale: Tween(
          begin: 0.97,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Motion.curve)),
        child: child,
      ),
    ),
  );
}

/// A channel card: logo, clean name, categories and badges; lifts and shows
/// its star under the mouse.
class _ChannelCard extends StatefulWidget {
  const _ChannelCard({
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
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final motion = Motion.of(context);
    final ch = widget.channel;
    final radius = BorderRadius.circular(Radii.card(FormFactor.desktop));
    final cats = ch.meta.categories.join(' · ');
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedSlide(
        duration: motion.hoverPressTime,
        offset: _hover && !motion.reduced
            ? const Offset(0, -0.02)
            : Offset.zero,
        child: AnimatedContainer(
          duration: motion.hoverPressTime,
          decoration: BoxDecoration(
            color: _hover ? colors.surfaceHigh : colors.surface,
            borderRadius: radius,
            border: Border.all(
              color: _hover
                  ? colors.accent.withValues(alpha: 0.55)
                  : colors.glassEdge,
            ),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onPlay,
              child: Opacity(
                opacity: ch.channel.playable ? 1 : 0.55,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ChannelLogo(channel: ch, size: 56, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ch.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (cats.isNotEmpty)
                              Text(
                                cats,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textDim,
                                ),
                              ),
                            const SizedBox(height: 5),
                            BadgeRow(badgesFor(ch)),
                          ],
                        ),
                      ),
                      AnimatedOpacity(
                        duration: motion.hoverPressTime,
                        opacity: widget.favourite || _hover ? 1 : 0,
                        child: IconButton(
                          key: LiveTvFilterKeys.favourite(ch.key),
                          tooltip: widget.favourite
                              ? 'Remove from favourites'
                              : 'Add to favourites',
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onFavourite,
                          icon: Icon(
                            widget.favourite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: widget.favourite
                                ? colors.accent
                                : colors.textDim,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _colCategory = 180.0;
const _colCountry = 150.0;
const _colLanguage = 130.0;
const _colQuality = 80.0;
const _colSpeed = 80.0;

class _ListHeader extends StatelessWidget {
  const _ListHeader();

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
      color: colors.textDim,
    );
    Widget col(String t, double w) => SizedBox(
      width: w,
      child: Text(t, style: style),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(child: Text('CHANNEL', style: style)),
          col('CATEGORY', _colCategory),
          col('COUNTRY', _colCountry),
          col('LANGUAGE', _colLanguage),
          col('QUALITY', _colQuality),
          col('RESPONSE', _colSpeed),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ChannelListRow extends StatefulWidget {
  const _ChannelListRow({
    super.key,
    required this.channel,
    required this.favourite,
    required this.striped,
    required this.onPlay,
    required this.onFavourite,
  });

  final IndexedChannel channel;
  final bool favourite;
  final bool striped;
  final VoidCallback onPlay;
  final VoidCallback onFavourite;

  @override
  State<_ChannelListRow> createState() => _ChannelListRowState();
}

class _ChannelListRowState extends State<_ChannelListRow> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final ch = widget.channel;
    final m = ch.meta;
    final c = ch.channel;
    final dim = TextStyle(fontSize: 13, color: colors.textDim);
    Widget col(String t, double w, {TextStyle? style}) => SizedBox(
      width: w,
      child: Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style ?? dim,
      ),
    );
    final status = badgesFor(ch)
        .where((b) => b.tone == BadgeTone.bad || b.tone == BadgeTone.warn)
        .toList();
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.of(context).hoverPressTime,
        decoration: BoxDecoration(
          color: _hover
              ? colors.surfaceHigh
              : (widget.striped
                    ? colors.surface.withValues(alpha: 0.5)
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onPlay,
            child: Opacity(
              opacity: c.playable ? 1 : 0.55,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    ChannelLogo(channel: ch, size: 36, radius: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              ch.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (status.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(child: BadgeRow(status, max: 2)),
                          ],
                        ],
                      ),
                    ),
                    col(
                      m.categories.isEmpty ? '-' : m.categories.join(', '),
                      _colCategory,
                    ),
                    col(m.countryName ?? '-', _colCountry),
                    col(
                      m.languages.isEmpty ? '-' : m.languages.join(', '),
                      _colLanguage,
                      style: m.languagesInferred
                          ? dim.copyWith(fontStyle: FontStyle.italic)
                          : null,
                    ),
                    SizedBox(
                      width: _colQuality,
                      child: m.quality == ChannelQuality.unknown
                          ? Text('-', style: dim)
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: BadgeChip(
                                badgesFor(ch, status: false).first,
                              ),
                            ),
                    ),
                    col(c.ttfbMs == null ? '-' : '${c.ttfbMs} ms', _colSpeed),
                    IconButton(
                      key: LiveTvFilterKeys.favourite(ch.key),
                      tooltip: widget.favourite
                          ? 'Remove from favourites'
                          : 'Add to favourites',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onFavourite,
                      icon: Icon(
                        widget.favourite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color: widget.favourite
                            ? colors.accent
                            : (_hover
                                  ? colors.text
                                  : colors.textDim.withValues(alpha: 0.5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.controller, required this.search});

  final LiveTvController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    final d = Dims.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s48),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: colors.textDim),
          const SizedBox(height: Space.s12),
          Text(
            controller.filter.isActive
                ? 'No channels match these filters.'
                : 'No channels here yet.',
            style: d.type.body,
          ),
          if (controller.filter.isActive) ...[
            const SizedBox(height: Space.s12),
            OutlinedButton.icon(
              onPressed: () {
                search.clear();
                controller.setFilter(
                  controller.filter.cleared().copyWith(query: ''),
                );
              },
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Clear filters and search'),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/sections.dart';
import '../../ui/common/tokens.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import 'add_playlist.dart';
import 'channel_filter.dart';
import 'desktop/desktop_livetv_page.dart';
import 'iptv_service.dart';
import 'livetv_controller.dart';
import 'livetv_widgets.dart';
import 'phone/phone_livetv_page.dart';
import 'suggestions.dart';

/// Live TV: your sources and their channels, with search, facet filters
/// (category, language, country, quality, source), sorting, favourites and
/// recents. With no sources it offers to add a playlist or one of the
/// community catalogues; nothing is downloaded until you choose one and
/// confirm.
///
/// Each form gets its own layout over one [LiveTvController]: a desktop
/// window gets a dense, mouse-first page; a TV gets big focusable rows and
/// pickers for the D-pad; a phone gets chips and bottom sheets.
class LiveTvPage extends StatelessWidget {
  const LiveTvPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) => switch (Dims.of(context).form) {
    FormFactor.phone => const PhoneLiveTvPage(),
    FormFactor.desktop => DesktopLiveTvPage(focus: focus),
    FormFactor.tv => _TvLiveTvPage(focus: focus),
  };
}

class _TvLiveTvPage extends StatefulWidget {
  const _TvLiveTvPage({required this.focus});

  final SectionFocus focus;

  @override
  State<_TvLiveTvPage> createState() => _TvLiveTvPageState();
}

class _TvLiveTvPageState extends State<_TvLiveTvPage>
    with LiveTvControllerHost {
  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = controller;
    final snap = c.snapshot;
    final pad = EdgeInsets.all(d.gutter);
    if (snap == null) {
      return Padding(
        padding: pad,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (snap.sources.isEmpty) {
      return LiveTvEmptyState(
        focus: widget.focus,
        service: c.service,
        padding: pad,
      );
    }

    final colors = ChithramColors.of(context);
    final visible = c.visible;
    final cats = quickCategories(c);
    final rows = !c.filter.isActive;
    final favourites = rows ? c.favourites : const <IndexedChannel>[];
    final recent = rows ? c.recent : const <IndexedChannel>[];

    return Padding(
      padding: pad,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Live TV',
                  style: TextStyle(
                    fontSize: d.t(32),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  c.filter.isActive
                      ? '${visible.length} of ${c.result.total} channels'
                      : '${c.result.total} channels',
                  style: TextStyle(fontSize: d.t(14), color: colors.textDim),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _TvSources(controller: c, focus: widget.focus),
          ),
          SliverToBoxAdapter(
            child: _TvFilterRow(controller: c, section: widget.focus),
          ),
          if (cats.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: d.u(64),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _TvChip(
                      key: LiveTvFilterKeys.allCategories,
                      label:
                          'All (${c.result.countWithout(ChannelFacet.category)})',
                      selected: c.filter
                          .selected(ChannelFacet.category)
                          .isEmpty,
                      onTap: () => c.clearFacet(ChannelFacet.category),
                    ),
                    for (final o in cats)
                      _TvChip(
                        key: LiveTvFilterKeys.category(o.key),
                        label: '${o.label} (${o.count})',
                        selected: o.selected,
                        onTap: () =>
                            c.toggleFacet(ChannelFacet.category, o.key),
                      ),
                  ],
                ),
              ),
            ),
          if (favourites.isNotEmpty)
            SliverToBoxAdapter(
              child: _TvRow(
                title: 'Favourites',
                channels: favourites,
                controller: c,
                section: widget.focus,
              ),
            ),
          if (recent.isNotEmpty)
            SliverToBoxAdapter(
              child: _TvRow(
                title: 'Recently watched',
                channels: recent,
                controller: c,
                section: widget.focus,
              ),
            ),
          SliverFixedExtentList(
            itemExtent: d.u(84),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _TvChannelRow(
                channel: visible[i],
                favourite: c.isFavourite(visible[i].key),
                section: widget.focus,
                onPlay: () => c.play(context, visible[i], visible),
                onFavourite: () => c.toggleFavourite(visible[i].key),
              ),
              childCount: visible.length,
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  c.filter.isActive
                      ? 'No channels match these filters.'
                      : 'No channels here yet.',
                  style: TextStyle(fontSize: d.t(16), color: colors.textDim),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The no-sources screen of the TV and desktop forms.
class LiveTvEmptyState extends StatelessWidget {
  const LiveTvEmptyState({
    super.key,
    required this.focus,
    required this.service,
    required this.padding,
  });

  final SectionFocus focus;
  final IptvService service;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Padding(
      padding: padding,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Section.liveTv.icon,
              size: d.u(48),
              color: ChithramColors.of(context).accent,
            ),
            const SizedBox(height: 16),
            Text(
              'Live TV',
              style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Add an M3U playlist you have, or choose a community catalogue. '
              'Nothing is downloaded until you choose one and confirm.',
              style: TextStyle(
                color: ChithramColors.of(context).textDim,
                fontSize: d.t(14),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _Card(
                  key: LiveTvKeys.addPlaylist,
                  focusNode: focus.entry,
                  section: focus,
                  icon: Icons.link_rounded,
                  title: 'Add playlist',
                  detail: 'An M3U link',
                  onTap: () => addPlaylistFromUrl(context, service),
                ),
                for (final s in CatalogueSuggestion.values)
                  _Card(
                    key: LiveTvKeys.suggestion(s),
                    section: focus,
                    icon: Icons.public_rounded,
                    title: s.name,
                    detail: s.blurb,
                    onTap: () => addSuggestionFlow(context, service, s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    required this.section,
    this.focusNode,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final SectionFocus section;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return SizedBox(
      width: d.u(300),
      child: FocusCard(
        focusNode: focusNode,
        section: section,
        radius: 18,
        onActivate: onTap,
        child: Container(
          color: ChithramColors.of(context).surfaceHigh,
          padding: EdgeInsets.all(d.u(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: ChithramColors.of(context).accent,
                size: d.u(28),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: d.t(18),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: d.t(13),
                  color: ChithramColors.of(context).textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sources as a slim strip: an add tile, then each source with its state and
/// Refresh / Remove pills. Selecting a source filters to it.
class _TvSources extends StatelessWidget {
  const _TvSources({required this.controller, required this.focus});

  final LiveTvController controller;
  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final c = controller;
    final snap = c.snapshot!;
    final busy = c.refreshing;
    final selected = c.filter.selected(ChannelFacet.source);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FocusCard(
            key: LiveTvKeys.addPlaylist,
            focusNode: focus.entry,
            section: focus,
            radius: 14,
            onActivate: () => showAddPlaylist(context, c.service),
            child: Container(
              height: d.u(72),
              color: colors.surfaceHigh,
              padding: EdgeInsets.symmetric(horizontal: d.u(18)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: colors.accent, size: d.u(28)),
                  const SizedBox(width: 8),
                  Text(
                    'Add playlist',
                    style: TextStyle(
                      fontSize: d.t(16),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final s in snap.sources)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: d.u(280),
                  child: FocusCard(
                    key: ValueKey('livetv-source-${s.id}'),
                    section: focus,
                    radius: 14,
                    onActivate: () => c.toggleFacet(ChannelFacet.source, s.id),
                    child: Container(
                      height: d.u(72),
                      color: selected.contains(s.id)
                          ? colors.accent.withValues(alpha: 0.25)
                          : colors.surfaceHigh,
                      padding: EdgeInsets.symmetric(horizontal: d.u(14)),
                      child: Row(
                        children: [
                          Icon(
                            sourceHasProblem(s)
                                ? Icons.warning_amber_rounded
                                : Icons.playlist_play_rounded,
                            color: sourceHasProblem(s)
                                ? const Color(0xFFFFB74D)
                                : colors.accent,
                            size: d.u(26),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: d.t(16),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  sourceDetail(
                                    s,
                                    snap.channels[s.id]?.length ?? 0,
                                    busy.contains(s.id),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: d.t(12),
                                    color: colors.textDim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FocusCard(
                  key: ValueKey('livetv-refresh-${s.id}'),
                  section: focus,
                  radius: 24,
                  onActivate: () => c.service.refresh(s.id),
                  child: const ActionLabel(
                    text: 'Refresh',
                    icon: Icons.refresh_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                FocusCard(
                  key: ValueKey('livetv-remove-${s.id}'),
                  section: focus,
                  radius: 24,
                  onActivate: () => confirmRemoveSource(context, c.service, s),
                  child: const ActionLabel(
                    text: 'Remove',
                    icon: Icons.delete_outline_rounded,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Sort, facet pickers and toggles, each one D-pad stop.
class _TvFilterRow extends StatelessWidget {
  const _TvFilterRow({required this.controller, required this.section});

  final LiveTvController controller;
  final SectionFocus section;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = controller;
    final f = c.filter;
    return SizedBox(
      height: d.u(64),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _TvChip(
            key: LiveTvFilterKeys.sort,
            icon: Icons.sort_rounded,
            label: 'Sort: ${f.sort.label}',
            selected: false,
            onTap: () => _pickSort(context, c),
          ),
          for (final facet in offeredFacets(c, category: true))
            _TvChip(
              key: LiveTvFilterKeys.facet(facet),
              icon: facetIcon(facet),
              label: facetChipText(c, facet),
              selected: f.selected(facet).isNotEmpty,
              onTap: () => _pickFacet(context, c, facet),
            ),
          _TvChip(
            key: LiveTvFilterKeys.favouritesOnly,
            icon: f.favouritesOnly
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            label: 'Favourites',
            selected: f.favouritesOnly,
            onTap: () =>
                c.setFilter(f.copyWith(favouritesOnly: !f.favouritesOnly)),
          ),
          _TvChip(
            key: LiveTvFilterKeys.workingOnly,
            icon: Icons.check_circle_outline_rounded,
            label: 'Working only',
            selected: f.workingOnly,
            onTap: () => c.setFilter(f.copyWith(workingOnly: !f.workingOnly)),
          ),
          if (f.isActive)
            _TvChip(
              key: LiveTvFilterKeys.clear,
              icon: Icons.filter_alt_off_rounded,
              label: 'Clear filters',
              selected: false,
              onTap: c.clearFilters,
            ),
        ],
      ),
    );
  }
}

Future<void> _pickSort(BuildContext context, LiveTvController c) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => _TvPicker(
        title: 'Sort channels',
        controller: c,
        itemCount: ChannelSort.values.length,
        item: (ctx, i) {
          final s = ChannelSort.values[i];
          return _TvPickerRow(
            key: LiveTvFilterKeys.sortOption(s),
            label: s.label,
            selected: c.filter.sort == s,
            autofocus: c.filter.sort == s,
            onTap: () {
              c.setFilter(c.filter.copyWith(sort: s));
              Navigator.of(ctx).pop();
            },
          );
        },
      ),
    );

Future<void> _pickFacet(
  BuildContext context,
  LiveTvController c,
  ChannelFacet facet,
) => showDialog<void>(
  context: context,
  builder: (ctx) => _TvPicker(
    title: facet.label,
    controller: c,
    itemCount: c.result.options(facet).length,
    onClear: () => c.clearFacet(facet),
    item: (ctx, i) {
      final options = c.result.options(facet);
      if (i >= options.length) return const SizedBox.shrink();
      final o = options[i];
      return _TvPickerRow(
        key: LiveTvFilterKeys.option(facet, o.key),
        label: o.label,
        count: o.count,
        selected: o.selected,
        autofocus: i == 0,
        check: true,
        onTap: () => c.toggleFacet(facet, o.key),
      );
    },
  ),
);

/// A focusable list in a dialog: Back closes it, picks apply at once.
class _TvPicker extends StatelessWidget {
  const _TvPicker({
    required this.title,
    required this.controller,
    required this.itemCount,
    required this.item,
    this.onClear,
  });

  final String title;
  final LiveTvController controller;
  final int itemCount;
  final IndexedWidgetBuilder item;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: d.u(520),
          maxHeight: size.height * 0.8,
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(d.u(24), d.u(20), d.u(24), d.u(8)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: d.t(22),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onClear != null)
                      FocusCard(
                        radius: 24,
                        onActivate: onClear,
                        child: const ActionLabel(
                          text: 'Clear',
                          icon: Icons.filter_alt_off_rounded,
                        ),
                      ),
                    const SizedBox(width: 12),
                    FocusCard(
                      radius: 24,
                      onActivate: () => Navigator.of(context).pop(),
                      child: const ActionLabel(
                        text: 'Done',
                        icon: Icons.check_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                    d.u(16),
                    d.u(8),
                    d.u(16),
                    d.u(20),
                  ),
                  itemCount: itemCount,
                  itemBuilder: item,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvPickerRow extends StatelessWidget {
  const _TvPickerRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.autofocus = false,
    this.check = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool autofocus;

  /// A multi-select row (checkbox) rather than a single choice (radio).
  final bool check;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final icon = check
        ? (selected
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded)
        : (selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_off_rounded);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _AutofocusCard(
        autofocus: autofocus,
        onActivate: onTap,
        child: Container(
          height: d.u(56),
          color: selected
              ? colors.accent.withValues(alpha: 0.18)
              : colors.surfaceHigh,
          padding: EdgeInsets.symmetric(horizontal: d.u(16)),
          child: Row(
            children: [
              Icon(icon, color: selected ? colors.accent : colors.textDim),
              SizedBox(width: d.u(14)),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: d.t(16)),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: TextStyle(fontSize: d.t(14), color: colors.textDim),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [FocusCard] that takes focus when it first appears (the picker's first
/// or current row), so the D-pad starts inside the dialog.
class _AutofocusCard extends StatefulWidget {
  const _AutofocusCard({
    required this.autofocus,
    required this.onActivate,
    required this.child,
  });

  final bool autofocus;
  final VoidCallback onActivate;
  final Widget child;

  @override
  State<_AutofocusCard> createState() => _AutofocusCardState();
}

class _AutofocusCardState extends State<_AutofocusCard> {
  final _node = FocusNode(debugLabel: 'picker row');

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusCard(
    focusNode: _node,
    radius: 12,
    onActivate: widget.onActivate,
    child: widget.child,
  );
}

class _TvChip extends StatelessWidget {
  const _TvChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final fg = selected ? colors.onAccent : colors.text;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FocusCard(
        radius: 24,
        onActivate: onTap,
        child: Container(
          color: selected ? colors.accent : colors.surfaceHigh,
          padding: EdgeInsets.symmetric(horizontal: d.u(18), vertical: d.u(8)),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: d.t(16) + 2, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: d.t(14),
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of channel cards (Favourites, Recently watched); zapping stays in it.
class _TvRow extends StatelessWidget {
  const _TvRow({
    required this.title,
    required this.channels,
    required this.controller,
    required this.section,
  });

  final String title;
  final List<IndexedChannel> channels;
  final LiveTvController controller;
  final SectionFocus section;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final width = d.u(220);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Text(
            title,
            style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: d.u(120),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            itemCount: channels.length,
            separatorBuilder: (_, _) => SizedBox(width: tvRailGap(width)),
            itemBuilder: (context, i) {
              final ch = channels[i];
              return SizedBox(
                width: width,
                child: FocusCard(
                  section: section,
                  radius: Radii.card(FormFactor.tv),
                  onActivate: () => controller.play(context, ch, channels),
                  child: Container(
                    color: colors.surfaceHigh,
                    padding: EdgeInsets.all(d.u(12)),
                    child: Row(
                      children: [
                        ChannelLogo(channel: ch, size: d.u(56)),
                        SizedBox(width: d.u(12)),
                        Expanded(
                          child: Text(
                            ch.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: d.t(15),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TvChannelRow extends StatelessWidget {
  const _TvChannelRow({
    required this.channel,
    required this.favourite,
    required this.section,
    required this.onPlay,
    required this.onFavourite,
  });

  final IndexedChannel channel;
  final bool favourite;
  final SectionFocus section;
  final VoidCallback onPlay;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final c = channel.channel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: FocusCard(
              key: LiveTvFilterKeys.channel(channel.key),
              section: section,
              radius: 12,
              onActivate: onPlay,
              child: Opacity(
                opacity: c.playable ? 1 : 0.55,
                child: Container(
                  color: colors.surface,
                  padding: EdgeInsets.symmetric(horizontal: d.u(12)),
                  child: Row(
                    children: [
                      ChannelLogo(channel: channel, size: d.u(56)),
                      SizedBox(width: d.u(16)),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: d.t(17),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            BadgeRow(badgesFor(channel), max: 5),
                          ],
                        ),
                      ),
                      if (channel.meta.categories.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(left: d.u(12)),
                          child: Text(
                            channel.meta.categories.join(' · '),
                            style: TextStyle(
                              fontSize: d.t(13),
                              color: colors.textDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: d.u(12)),
          FocusCard(
            key: LiveTvFilterKeys.favourite(channel.key),
            section: section,
            radius: 30,
            onActivate: onFavourite,
            child: Container(
              width: d.u(56),
              height: d.u(56),
              color: colors.surface,
              alignment: Alignment.center,
              child: Icon(
                favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: favourite ? colors.accent : colors.textDim,
                semanticLabel: favourite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

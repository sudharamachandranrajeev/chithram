import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';
import 'channel_filter.dart';
import 'iptv_service.dart';
import 'livetv_controller.dart';

/// Test keys of the Live TV filter controls, shared by every form.
abstract final class LiveTvFilterKeys {
  static const search = ValueKey('livetv-search');
  static const sort = ValueKey('livetv-sort');
  static const clear = ValueKey('livetv-clear');
  static const favouritesOnly = ValueKey('livetv-favourites-only');
  static const workingOnly = ValueKey('livetv-working-only');
  static const viewToggle = ValueKey('livetv-view-toggle');
  static const sources = ValueKey('livetv-sources');
  static const allCategories = ValueKey('livetv-category-all');
  static ValueKey<String> facet(ChannelFacet f) =>
      ValueKey('livetv-facet-${f.name}');
  static ValueKey<String> option(ChannelFacet f, String key) =>
      ValueKey('livetv-option-${f.name}-$key');
  static ValueKey<String> sortOption(ChannelSort s) =>
      ValueKey('livetv-sort-${s.name}');
  static ValueKey<String> category(String key) =>
      ValueKey('livetv-category-$key');
  static ValueKey<String> favourite(String channelKey) =>
      ValueKey('livetv-fav-$channelKey');
  static ValueKey<String> channel(String channelKey) =>
      ValueKey('livetv-channel-$channelKey');
}

/// "3 channels, updated 2 h ago, last refresh failed".
String sourceDetail(Source s, int channels, bool busy) {
  if (busy) return 'Loading...';
  final parts = ['$channels channels'];
  final ok = s.lastSuccess;
  if (ok != null) {
    parts.add('updated ${_ago(DateTime.now().toUtc().difference(ok))}');
  }
  if (s.deprecated) {
    parts.add('turned off after repeated failures');
  } else if (s.lastError != null) {
    parts.add('last refresh failed');
  }
  return parts.join(', ');
}

String _ago(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// True when the source's last refresh failed or it was turned off.
bool sourceHasProblem(Source s) => s.deprecated || s.lastError != null;

/// Asks, then removes [s] and its channels.
Future<void> confirmRemoveSource(
  BuildContext context,
  IptvService service,
  Source s,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Remove ${s.name}?'),
      content: const Text('Its channels are deleted from this device.'),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (ok == true) await service.remove(s.id);
}

IconData facetIcon(ChannelFacet f) => switch (f) {
  ChannelFacet.category => Icons.category_rounded,
  ChannelFacet.language => Icons.translate_rounded,
  ChannelFacet.country => Icons.public_rounded,
  ChannelFacet.quality => Icons.high_quality_rounded,
  ChannelFacet.source => Icons.playlist_play_rounded,
};

/// "Language", "Language: Hindi" or "Language: Hindi +2".
String facetChipText(LiveTvController c, ChannelFacet f) {
  final sel = c.filter.selected(f);
  if (sel.isEmpty) return f.label;
  final first = c.index.label(f, sel.first);
  return sel.length == 1
      ? '${f.label}: $first'
      : '${f.label}: $first +${sel.length - 1}';
}

/// The facets worth a control: those with at least one known value (or a
/// value picked). Source only when there is more than one.
List<ChannelFacet> offeredFacets(LiveTvController c, {bool category = true}) =>
    [
      for (final f in ChannelFacet.values)
        if ((category || f != ChannelFacet.category) &&
            (c.filter.selected(f).isNotEmpty ||
                (f == ChannelFacet.source
                    ? (c.snapshot?.sources.length ?? 0) > 1
                    : c.result.options(f).any((o) => o.key.isNotEmpty))))
          f,
    ];

/// The category quick chips: the most used categories, "Other" last.
List<FacetOption> quickCategories(LiveTvController c, {int max = 24}) {
  final all = c.result.options(ChannelFacet.category);
  final known = [
    for (final o in all)
      if (o.key.isNotEmpty) o,
  ];
  final top = known.length <= max ? known : known.sublist(0, max);
  // Picked ones stay visible even when they are not in the top list.
  return [
    ...top,
    for (final o in known.skip(top.length))
      if (o.selected) o,
    for (final o in all)
      if (o.key.isEmpty) o,
  ];
}

enum BadgeTone { neutral, accent, warn, bad }

class ChannelBadge {
  const ChannelBadge(
    this.text, {
    this.icon,
    this.tone = BadgeTone.neutral,
    this.tooltip,
    this.dim = false,
  });

  final String text;
  final IconData? icon;
  final BadgeTone tone;
  final String? tooltip;

  /// A guess (a language inferred from the country) reads quieter.
  final bool dim;
}

/// The badges of a channel, most important first (rows cut the tail).
List<ChannelBadge> badgesFor(IndexedChannel ic, {bool status = true}) {
  final c = ic.channel;
  final m = ic.meta;
  return [
    if (status && c.missing)
      const ChannelBadge(
        'No longer in the source',
        icon: Icons.link_off_rounded,
        tone: BadgeTone.bad,
      )
    else if (status && c.dead)
      const ChannelBadge(
        'Not working',
        icon: Icons.error_outline_rounded,
        tone: BadgeTone.bad,
      ),
    if (m.quality != ChannelQuality.unknown)
      ChannelBadge(
        m.quality.label,
        tone: m.quality.index <= ChannelQuality.fhd.index
            ? BadgeTone.accent
            : BadgeTone.neutral,
      ),
    if (m.country != null) ChannelBadge(m.country!, tooltip: m.countryName),
    if (m.languages.isNotEmpty)
      ChannelBadge(
        m.languages.length == 1
            ? m.languages.first
            : '${m.languages.first} +${m.languages.length - 1}',
        dim: m.languagesInferred,
        tooltip: m.languagesInferred
            ? 'Guessed from the country'
            : m.languages.join(', '),
      ),
    if (m.geoBlocked)
      const ChannelBadge(
        'Geo-blocked',
        icon: Icons.public_off_rounded,
        tone: BadgeTone.warn,
      ),
    if (m.not247)
      const ChannelBadge(
        'Not 24/7',
        icon: Icons.schedule_rounded,
        tone: BadgeTone.warn,
      ),
  ];
}

/// One small badge. TV sizes come from [Dims.t] (16 dp floor).
class BadgeChip extends StatelessWidget {
  const BadgeChip(this.badge, {super.key});

  final ChannelBadge badge;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final d = Dims.of(context);
    final (Color fg, Color bg) = switch (badge.tone) {
      BadgeTone.accent => (c.accent, c.accent.withValues(alpha: 0.16)),
      BadgeTone.warn => (const Color(0xFFFFB74D), const Color(0x33FFB74D)),
      BadgeTone.bad => (const Color(0xFFFF8A80), const Color(0x33FF5252)),
      BadgeTone.neutral => (
        badge.dim ? c.textDim : c.text,
        c.text.withValues(alpha: 0.08),
      ),
    };
    final size = d.t(11);
    Widget chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: d.tv ? 8 : 6,
        vertical: d.tv ? 2 : 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge.icon != null) ...[
            Icon(badge.icon, size: size + 1, color: fg),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              badge.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: size,
                color: fg,
                fontWeight: FontWeight.w600,
                fontStyle: badge.dim ? FontStyle.italic : null,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
    if (badge.tooltip != null && !d.tv) {
      chip = Tooltip(message: badge.tooltip!, child: chip);
    }
    return chip;
  }
}

/// Badges in one line. Whole badges only: the ones that do not fit are left
/// out rather than cut to "N...", so the first (the status, when there is
/// one) always reads.
class BadgeRow extends StatelessWidget {
  const BadgeRow(this.badges, {super.key, this.max = 4});

  final List<ChannelBadge> badges;
  final int max;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // One line of BadgeChip: text at 1.3 line height (or the icon, one
    // point larger), plus its vertical padding.
    final size = d.t(11);
    final line = scaler.scale(size) * 1.3 > size + 1
        ? scaler.scale(size) * 1.3
        : size + 1;
    final height = (line + (d.tv ? 4 : 2)).ceilToDouble() + 1;
    return SizedBox(
      height: height,
      child: ClipRect(
        child: Wrap(
          spacing: 4,
          runSpacing: 8,
          clipBehavior: Clip.hardEdge,
          children: [for (final b in badges.take(max)) BadgeChip(b)],
        ),
      ),
    );
  }
}

const _logoTints = [
  Color(0xFF3A2A6B),
  Color(0xFF0F3D5E),
  Color(0xFF5B1F4A),
  Color(0xFF1D3B2A),
  Color(0xFF2B2F6B),
  Color(0xFF4A1C1C),
  Color(0xFF3B3320),
];

/// A channel logo on a rounded tile; initials on a tint when there is none
/// or it fails to load, so a list without logos still reads.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    this.size = 48,
    this.radius = 10,
  });

  final IndexedChannel channel;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final fallback = _Initials(
      name: channel.name,
      size: size,
      seed: channel.key.hashCode,
    );
    final logo = channel.channel.logo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: logo == null
            ? fallback
            : ColoredBox(
                color: c.surfaceHigh,
                child: Padding(
                  padding: EdgeInsets.all(size * 0.1),
                  child: Image.network(
                    logo,
                    cacheWidth: (size * 2).round(),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => fallback,
                  ),
                ),
              ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size, required this.seed});

  final String name;
  final double size;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final text = words.isEmpty
        ? '?'
        : (words.length == 1
                  ? words.first.characters.take(2).toString()
                  : '${words[0].characters.first}${words[1].characters.first}')
              .toUpperCase();
    return Container(
      color: _logoTints[seed.abs() % _logoTints.length],
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.92),
        ),
      ),
    );
  }
}

/// A checkable list of one facet's values with counts, with a search field
/// for long lists (countries, languages). Phone sheets and desktop popovers
/// use it; the TV has its own focusable picker.
class FacetOptionsList extends StatefulWidget {
  const FacetOptionsList({
    super.key,
    required this.controller,
    required this.facet,
    this.shrinkWrap = false,
  });

  final LiveTvController controller;
  final ChannelFacet facet;
  final bool shrinkWrap;

  @override
  State<FacetOptionsList> createState() => _FacetOptionsListState();
}

class _FacetOptionsListState extends State<FacetOptionsList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, _search]),
      builder: (context, _) {
        final all = widget.controller.result.options(widget.facet);
        final q = _search.text.trim().toLowerCase();
        final shown = q.isEmpty
            ? all
            : [
                for (final o in all)
                  if (o.label.toLowerCase().contains(q)) o,
              ];
        final list = ListView.builder(
          shrinkWrap: widget.shrinkWrap,
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final o = shown[i];
            return ListTile(
              key: LiveTvFilterKeys.option(widget.facet, o.key),
              dense: true,
              minTileHeight: 48,
              selected: o.selected,
              selectedColor: c.text,
              leading: ExcludeSemantics(
                child: IgnorePointer(
                  child: Checkbox(value: o.selected, onChanged: (_) {}),
                ),
              ),
              title: Text(
                o.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '${o.count}',
                style: TextStyle(
                  color: c.textDim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              onTap: () => widget.controller.toggleFacet(widget.facet, o.key),
            );
          },
        );
        return Column(
          mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (all.length > 10)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search ${widget.facet.label.toLowerCase()}',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: c.surfaceHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Nothing matches.',
                  style: TextStyle(color: c.textDim),
                ),
              )
            else if (widget.shrinkWrap)
              Flexible(child: list)
            else
              Expanded(child: list),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart';

import '../../../core/services.dart';
import '../../../player/play_request.dart';
import '../../../theme.dart';
import '../../../ui/phone/phone_widgets.dart';
import '../add_playlist.dart';
import '../iptv_service.dart';
import '../suggestions.dart';

/// Live TV on a phone: your sources (pull down to refresh them), group chips
/// that stay at the top while the channel list scrolls, and a tap on a
/// channel plays it. With no sources it offers to add one; nothing is
/// downloaded until you choose and confirm.
class PhoneLiveTvPage extends StatefulWidget {
  const PhoneLiveTvPage({super.key});

  @override
  State<PhoneLiveTvPage> createState() => _PhoneLiveTvPageState();
}

class _PhoneLiveTvPageState extends State<PhoneLiveTvPage> {
  IptvService? _service;
  LiveTvSnapshot? _snap;
  String? _sourceId;
  String? _group;
  var _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppServices.of(context).iptv;
    if (!identical(s, _service)) {
      _service?.removeListener(_reload);
      _service = s..addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final gen = ++_generation;
    final snap = await _service!.snapshot();
    if (!mounted || gen != _generation) return;
    setState(() {
      _snap = snap;
      if (_sourceId != null && !snap.sources.any((s) => s.id == _sourceId)) _sourceId = null;
    });
  }

  static String _groupOf(StoredChannel c) => (c.group == null || c.group!.isEmpty) ? 'Other' : c.group!;

  Future<void> _refreshAll() async {
    final service = _service!;
    final snap = _snap;
    if (snap == null) return;
    await Future.wait([for (final s in snap.sources) service.refresh(s.id)]);
  }

  void _play(List<StoredChannel> visible, int index) {
    final picked = visible[index];
    // Skip dead and missing channels when zapping; the one you chose stays.
    final zap = [for (final c in visible) if (c.playable || identical(c, picked)) c];
    openPlayer(context, _service!.playRequest(zap, zap.indexOf(picked)));
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final service = _service!;
    if (snap == null) return const Center(child: CircularProgressIndicator());
    if (snap.sources.isEmpty) return _Empty(service: service);

    final scope = [
      for (final s in snap.sources)
        if (_sourceId == null || s.id == _sourceId) ...?snap.channels[s.id],
    ];
    final groups = <String, int>{};
    for (final c in scope) {
      groups.update(_groupOf(c), (n) => n + 1, ifAbsent: () => 1);
    }
    final names = groups.keys.toList()..sort();
    if (_group != null && !groups.containsKey(_group)) _group = null;
    final visible = _group == null ? scope : [for (final c in scope) if (_groupOf(c) == _group) c];
    final busy = service.refreshing;

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: CustomScrollView(
        key: const PageStorageKey<String>('phone-livetv-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: PhoneSectionTitle('Sources')),
          SliverList.list(
            children: [
              for (final s in snap.sources)
                _SourceTile(
                  source: s,
                  channels: snap.channels[s.id]?.length ?? 0,
                  busy: busy.contains(s.id),
                  selected: _sourceId == s.id,
                  onSelect: () => setState(() {
                    _sourceId = _sourceId == s.id ? null : s.id;
                    _group = null;
                  }),
                  service: service,
                ),
              ListTile(
                key: LiveTvKeys.addPlaylist,
                minTileHeight: 56,
                leading: const Icon(Icons.add_rounded),
                title: const Text('Add playlist'),
                subtitle: const Text('A link or a community catalogue'),
                onTap: () => showAddPlaylist(context, service),
              ),
            ],
          ),
          if (names.length > 1)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ChipsHeader(
                children: [
                  _GroupChip(label: 'All (${scope.length})', selected: _group == null, onTap: () => setState(() => _group = null)),
                  for (final g in names)
                    _GroupChip(label: '$g (${groups[g]})', selected: _group == g, onTap: () => setState(() => _group = g)),
                ],
              ),
            )
          else
            const SliverToBoxAdapter(child: PhoneSectionTitle('Channels')),
          SliverFixedExtentList(
            itemExtent: 72,
            delegate: SliverChildBuilderDelegate(
              (context, i) => _ChannelTile(channel: visible[i], onPlay: () => _play(visible, i)),
              childCount: visible.length,
            ),
          ),
          if (visible.isEmpty) const SliverToBoxAdapter(child: PhoneNote('No channels here yet.')),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
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
          leading: const Icon(Icons.link_rounded, color: ChithramColors.accent),
          title: const Text('Add playlist'),
          subtitle: const Text('An M3U link'),
          onTap: () => addPlaylistFromUrl(context, service),
        ),
        for (final s in CatalogueSuggestion.values)
          ListTile(
            key: LiveTvKeys.suggestion(s),
            minTileHeight: 64,
            leading: const Icon(Icons.public_rounded, color: ChithramColors.accent),
            title: Text(s.name),
            subtitle: Text(s.blurb, maxLines: 3, overflow: TextOverflow.ellipsis),
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

  static String _detail(Source s, int channels, bool busy) {
    if (busy) return 'Loading...';
    final parts = ['$channels channels'];
    final ok = s.lastSuccess;
    if (ok != null) parts.add('updated ${_ago(DateTime.now().toUtc().difference(ok))}');
    if (s.deprecated) {
      parts.add('turned off after repeated failures');
    } else if (s.lastError != null) {
      parts.add('last refresh failed');
    }
    return parts.join(', ');
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${source.name}?'),
        content: const Text('Its channels are deleted from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await service.remove(source.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('livetv-source-${source.id}'),
      minTileHeight: 64,
      selected: selected,
      selectedTileColor: ChithramColors.accent.withValues(alpha: 0.18),
      leading: Icon(selected ? Icons.check_circle_rounded : Icons.list_alt_rounded),
      title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_detail(source, channels, busy), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<_SourceAction>(
        key: ValueKey('livetv-menu-${source.id}'),
        tooltip: 'Source options',
        onSelected: (a) {
          switch (a) {
            case _SourceAction.refresh:
              service.refresh(source.id);
            case _SourceAction.remove:
              _confirmRemove(context);
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

class _ChipsHeader extends SliverPersistentHeaderDelegate {
  _ChipsHeader({required this.children});

  final List<Widget> children;

  static const _height = 60.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: ChithramColors.background,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 6),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(child: children[i]),
      ),
    );
  }

  @override
  bool shouldRebuild(_ChipsHeader old) => true;
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.label, required this.selected, required this.onTap});

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

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onPlay});

  final StoredChannel channel;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = channel;
    final note = c.missing ? 'No longer in the source' : (c.dead ? 'Not working' : (c.group ?? ''));
    return Opacity(
      opacity: c.playable ? 1 : 0.5,
      child: ListTile(
        minTileHeight: 72,
        leading: SizedBox(
          width: 48,
          height: 48,
          child: c.logo == null
              ? const Icon(Icons.tv_rounded, color: ChithramColors.textDim)
              : Image.network(
                  c.logo!,
                  cacheWidth: 96,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(Icons.tv_rounded, color: ChithramColors.textDim),
                ),
        ),
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: note.isEmpty ? null : Text(note, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onPlay,
      ),
    );
  }
}

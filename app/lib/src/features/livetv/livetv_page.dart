import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart';

import '../../core/services.dart';
import '../../player/play_request.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import '../../ui/common/sections.dart';
import 'add_playlist.dart';
import 'iptv_service.dart';
import 'suggestions.dart';

/// Live TV: your sources, their groups and channels. With no sources it
/// offers to add a playlist or one of the community catalogues; nothing is
/// downloaded until you choose one and confirm.
class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends State<LiveTvPage> {
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

  /// Channels of the selected source (or all), before the group filter.
  List<StoredChannel> _inScope(LiveTvSnapshot snap) => [
        for (final s in snap.sources)
          if (_sourceId == null || s.id == _sourceId) ...?snap.channels[s.id],
      ];

  static String groupOf(StoredChannel c) => (c.group == null || c.group!.isEmpty) ? 'Other' : c.group!;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final snap = _snap;
    final pad = EdgeInsets.all(d.phone ? 16 : 32);
    if (snap == null) {
      return Padding(padding: pad, child: const Center(child: CircularProgressIndicator()));
    }
    final service = _service!;
    if (snap.sources.isEmpty) return _EmptyState(focus: widget.focus, service: service, padding: pad);

    final scope = _inScope(snap);
    final groups = <String, int>{};
    for (final c in scope) {
      groups.update(groupOf(c), (n) => n + 1, ifAbsent: () => 1);
    }
    final names = groups.keys.toList()..sort();
    if (_group != null && !groups.containsKey(_group)) _group = null;
    final visible = _group == null ? scope : [for (final c in scope) if (groupOf(c) == _group) c];

    return Padding(
      padding: pad,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Text('Live TV', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
          ),
          SliverToBoxAdapter(child: _Sources(
            snap: snap,
            service: service,
            focus: widget.focus,
            selected: _sourceId,
            onSelect: (id) => setState(() {
              _sourceId = _sourceId == id ? null : id;
              _group = null;
            }),
          )),
          if (names.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: d.u(64),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _Chip(label: 'All (${scope.length})', selected: _group == null, onTap: () => setState(() => _group = null)),
                    for (final g in names)
                      _Chip(label: '$g (${groups[g]})', selected: _group == g, onTap: () => setState(() => _group = g)),
                  ],
                ),
              ),
            ),
          SliverFixedExtentList(
            itemExtent: d.u(76),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _ChannelRow(
                channel: visible[i],
                section: widget.focus,
                onPlay: () => _play(context, service, visible, i),
              ),
              childCount: visible.length,
            ),
          ),
          if (visible.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(16), child: Text('No channels here yet.')),
            ),
        ],
      ),
    );
  }

  void _play(BuildContext context, IptvService service, List<StoredChannel> visible, int index) {
    final picked = visible[index];
    // Up and Down skip dead and missing channels; the one you chose stays.
    final zap = [for (final c in visible) if (c.playable || identical(c, picked)) c];
    openPlayer(context, service.playRequest(zap, zap.indexOf(picked)));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.focus, required this.service, required this.padding});

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
            Icon(Section.liveTv.icon, size: d.u(48), color: ChithramColors.accent),
            const SizedBox(height: 16),
            Text('Live TV', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Add an M3U playlist you have, or choose a community catalogue. '
              'Nothing is downloaded until you choose one and confirm.',
              style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
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
          color: ChithramColors.surfaceHigh,
          padding: EdgeInsets.all(d.u(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: ChithramColors.accent, size: d.u(28)),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: d.t(18), fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(detail,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: d.t(13), color: ChithramColors.textDim)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const _Sources({
    required this.snap,
    required this.service,
    required this.focus,
    required this.selected,
    required this.onSelect,
  });

  final LiveTvSnapshot snap;
  final IptvService service;
  final SectionFocus focus;
  final String? selected;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final busy = service.refreshing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _Card(
            key: LiveTvKeys.addPlaylist,
            focusNode: focus.entry,
            section: focus,
            icon: Icons.add_rounded,
            title: 'Add playlist',
            detail: 'A link or a community catalogue',
            onTap: () => showAddPlaylist(context, service),
          ),
          for (final s in snap.sources)
            SizedBox(
              width: d.u(300),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FocusCard(
                    key: ValueKey('livetv-source-${s.id}'),
                    section: focus,
                    radius: 18,
                    onActivate: () => onSelect(s.id),
                    child: Container(
                      width: double.infinity,
                      color: selected == s.id ? ChithramColors.accent.withValues(alpha: 0.25) : ChithramColors.surfaceHigh,
                      padding: EdgeInsets.all(d.u(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: d.t(18), fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(_detail(s, snap.channels[s.id]?.length ?? 0, busy.contains(s.id)),
                              style: TextStyle(fontSize: d.t(13), color: ChithramColors.textDim)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FocusCard(
                        key: ValueKey('livetv-refresh-${s.id}'),
                        section: focus,
                        radius: 24,
                        onActivate: () => service.refresh(s.id),
                        child: const ActionLabel(text: 'Refresh', icon: Icons.refresh_rounded),
                      ),
                      FocusCard(
                        key: ValueKey('livetv-remove-${s.id}'),
                        section: focus,
                        radius: 24,
                        onActivate: () => _confirmRemove(context, s),
                        child: const ActionLabel(text: 'Remove', icon: Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

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

  Future<void> _confirmRemove(BuildContext context, Source s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${s.name}?'),
        content: const Text('Its channels are deleted from this device.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await service.remove(s.id);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FocusCard(
        radius: 24,
        onActivate: onTap,
        child: Container(
          color: selected ? ChithramColors.accent : ChithramColors.surfaceHigh,
          padding: EdgeInsets.symmetric(horizontal: d.u(18), vertical: d.u(8)),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: d.t(14), color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, required this.section, required this.onPlay});

  final StoredChannel channel;
  final SectionFocus section;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = channel;
    final note = c.missing ? 'No longer in the source' : (c.dead ? 'Not working' : (c.group ?? ''));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: FocusCard(
        section: section,
        radius: 12,
        onActivate: onPlay,
        child: Opacity(
          opacity: c.playable ? 1 : 0.5,
          child: Container(
            color: ChithramColors.surface,
            padding: EdgeInsets.symmetric(horizontal: d.u(12)),
            child: Row(
              children: [
                SizedBox(
                  width: d.u(48),
                  height: d.u(48),
                  child: c.logo == null
                      ? const Icon(Icons.tv_rounded, color: ChithramColors.textDim)
                      : Image.network(c.logo!,
                          cacheWidth: 96,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(Icons.tv_rounded, color: ChithramColors.textDim)),
                ),
                SizedBox(width: d.u(16)),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: d.t(16))),
                      if (note.isNotEmpty)
                        Text(note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: d.t(12), color: ChithramColors.textDim)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

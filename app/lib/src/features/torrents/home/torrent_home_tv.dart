import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/tv/focus_card.dart';
import '../../../ui/tv/focus_rail.dart';
import '../../../ui/tv/home_page.dart' show ActionLabel;
import 'open_popular.dart';
import 'sources_page.dart';
import 'torrent_home_feed.dart';
import 'torrent_tile.dart';

/// Torrent Home on a TV or desktop: rails of the user's sources ranked by
/// seeders. Select adds and plays; Menu opens the file list.
class TorrentHomeRails extends StatefulWidget {
  const TorrentHomeRails({super.key, required this.focus});

  final SectionFocus focus;

  @override
  State<TorrentHomeRails> createState() => _TorrentHomeRailsState();
}

class _TorrentHomeRailsState extends State<TorrentHomeRails> {
  @override
  void initState() {
    super.initState();
    // After the first frame: nothing on the startup path reads the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppServices.of(context).torrentHome.open());
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = AppServices.of(context).torrentHome;
    final d = Dims.of(context);
    return ValueListenableBuilder<TorrentHomeState>(
      valueListenable: feed.state,
      builder: (context, state, _) {
        final children = <Widget>[
          for (final rail in state.rails)
            FocusRail(
              key: ValueKey('torrent-rail-${rail.id}'),
              title: rail.title,
              count: rail.items.length,
              section: widget.focus,
              itemBuilder: (_, i) => TorrentTileBody(item: rail.items[i]),
              onSelect: (i) => unawaited(openPopular(context, rail.items[i])),
              onMenu: (i) => unawaited(openPopular(context, rail.items[i], chooseFile: true)),
            ),
        ];
        if (state.rails.isEmpty) {
          children.add(_Status(state: state, focus: widget.focus, onRetry: () => feed.refresh(force: true)));
        } else {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  if (state.loading)
                    Text(
                      'Updating…',
                      style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
                    ),
                  if (state.sourceErrors.isNotEmpty)
                    Flexible(
                      child: Text(
                        'Could not read ${state.sourceErrors.keys.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state, required this.focus, required this.onRetry});

  final TorrentHomeState state;
  final SectionFocus focus;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final dim = TextStyle(color: ChithramColors.textDim, fontSize: d.t(14));
    final Widget body;
    if (state.hasSources == false) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Popular torrents',
            style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Chithram ships no sources. Add a Torznab indexer or a search plugin and what is popular shows here.',
            style: dim,
          ),
          const SizedBox(height: 12),
          FocusCard(
            key: const ValueKey('torrent-add-source'),
            section: focus,
            radius: 24,
            onActivate: () => unawaited(openSources(context)),
            child: const ActionLabel(icon: Icons.add_rounded, text: 'Add a source'),
          ),
        ],
      );
    } else if (state.loading || state.hasSources == null) {
      body = Text('Loading what is popular…', key: const ValueKey('torrent-home-loading'), style: dim);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.error ?? 'Nothing popular right now.', key: const ValueKey('torrent-home-empty'), style: dim),
          if (state.sourceErrors.isNotEmpty)
            Text(state.sourceErrors.entries.map((e) => '${e.key}: ${e.value}').join('\n'), style: dim),
          const SizedBox(height: 12),
          FocusCard(
            key: const ValueKey('torrent-home-retry'),
            section: focus,
            radius: 24,
            onActivate: onRetry,
            child: const ActionLabel(icon: Icons.refresh_rounded, text: 'Retry'),
          ),
        ],
      );
    }
    return Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0), child: body);
  }
}

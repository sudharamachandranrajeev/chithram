import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../../../theme.dart';
import '../../../ui/phone/phone_widgets.dart';
import 'open_popular.dart';
import 'sources_page.dart';
import 'torrent_home_feed.dart';
import 'torrent_tile.dart';

/// Opens Torrent Home's feed once the tab is on screen (after the first frame).
void openTorrentHomeAfterFrame(State state) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (state.mounted) unawaited(AppServices.of(state.context).torrentHome.open());
  });
}

/// The phone's rails, as list children: tap adds and plays, long press opens
/// the file list.
List<Widget> phoneTorrentHomeChildren(BuildContext context, TorrentHomeState state, Future<void> Function() retry) {
  final text = Theme.of(context).textTheme;
  final out = <Widget>[];
  for (final rail in state.rails) {
    out.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(phoneGutter, 20, phoneGutter, 8),
        child: Text(rail.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
    out.add(
      SizedBox(
        height: 128,
        child: ListView.separated(
          key: PageStorageKey<String>('torrent-phone-rail-${rail.id}'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: phoneGutter),
          itemCount: rail.items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) => Material(
            color: ChithramColors.of(context).surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => unawaited(openPopular(context, rail.items[i])),
              onLongPress: () => unawaited(openPopular(context, rail.items[i], chooseFile: true)),
              child: TorrentTileBody(item: rail.items[i], width: 260),
            ),
          ),
        ),
      ),
    );
  }
  if (state.rails.isEmpty) {
    if (state.hasSources == false) {
      out.addAll([
        const PhoneSectionTitle('Popular torrents'),
        const PhoneNote(
          'Chithram ships no sources. Add a Torznab indexer or a search plugin and what is popular shows here.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 4),
          child: FilledButton.tonalIcon(
            key: const ValueKey('torrent-add-source'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => unawaited(openSources(context)),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a source'),
          ),
        ),
      ]);
    } else if (state.loading || state.hasSources == null) {
      out.add(const PhoneNote('Loading what is popular…', key: ValueKey('torrent-home-loading')));
    } else {
      out.addAll([
        PhoneNote(state.error ?? 'Nothing popular right now.', key: const ValueKey('torrent-home-empty')),
        if (state.sourceErrors.isNotEmpty)
          PhoneNote(state.sourceErrors.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 4),
          child: FilledButton.tonalIcon(
            key: const ValueKey('torrent-home-retry'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => unawaited(retry()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      ]);
    }
  } else if (state.sourceErrors.isNotEmpty) {
    out.add(PhoneNote('Could not read ${state.sourceErrors.keys.join(', ')}'));
  }
  return out;
}

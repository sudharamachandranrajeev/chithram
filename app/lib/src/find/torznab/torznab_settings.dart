import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import 'torznab_actions.dart';

/// Settings > Torznab on a TV or desktop: the user's indexers, each a card
/// that opens Test / Enable / Remove, and an add card. [entry] is the page's
/// entry node when this is its first section.
class TorznabSettings extends StatefulWidget {
  const TorznabSettings({super.key, this.entry});

  final SectionFocus? entry;

  @override
  State<TorznabSettings> createState() => _TorznabSettingsState();
}

class _TorznabSettingsState extends State<TorznabSettings> {
  @override
  void initState() {
    super.initState();
    // After the first frame: the database is not touched before it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppServices.of(context).torznab.load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final service = AppServices.of(context).torznab;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Torznab',
              style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Add your own Torznab indexers. Torrent Home ranks what they list.',
              style: TextStyle(color: ChithramColors.of(context).textDim, fontSize: d.t(14)),
            ),
            const SizedBox(height: 12),
            for (final e in service.endpoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FocusCard(
                  key: ValueKey('torznab-${e.id}'),
                  section: widget.entry,
                  radius: 24,
                  onActivate: () => unawaited(torznabEndpointMenu(context, e)),
                  child: ActionLabel(
                    icon: e.enabled ? Icons.rss_feed_rounded : Icons.pause_circle_outline_rounded,
                    text: '${e.name}${e.enabled ? '' : ' (off)'} · ${healthLine(service, e, DateTime.now())}',
                  ),
                ),
              ),
            FocusCard(
              key: const ValueKey('torznab-add'),
              focusNode: widget.entry?.entry,
              section: widget.entry,
              radius: 24,
              onActivate: () => unawaited(addTorznabEndpoint(context)),
              child: const ActionLabel(icon: Icons.add_rounded, text: 'Add a Torznab indexer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same on a phone, as list tiles.
class PhoneTorznabSettings extends StatefulWidget {
  const PhoneTorznabSettings({super.key});

  @override
  State<PhoneTorznabSettings> createState() => _PhoneTorznabSettingsState();
}

class _PhoneTorznabSettingsState extends State<PhoneTorznabSettings> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppServices.of(context).torznab.load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).torznab;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        children: [
          for (final e in service.endpoints)
            ListTile(
              key: ValueKey('torznab-${e.id}'),
              minTileHeight: 56,
              leading: Icon(e.enabled ? Icons.rss_feed_rounded : Icons.pause_circle_outline_rounded),
              title: Text(e.name),
              subtitle: Text('${e.enabled ? '' : 'Off · '}${healthLine(service, e, DateTime.now())}'),
              onTap: () => unawaited(torznabEndpointMenu(context, e)),
            ),
          ListTile(
            key: const ValueKey('torznab-add'),
            minTileHeight: 56,
            leading: const Icon(Icons.add_rounded),
            title: const Text('Add a Torznab indexer'),
            subtitle: const Text('Address and API key'),
            onTap: () => unawaited(addTorznabEndpoint(context)),
          ),
        ],
      ),
    );
  }
}

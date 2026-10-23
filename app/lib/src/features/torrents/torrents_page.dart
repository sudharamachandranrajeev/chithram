import 'dart:async';

import 'package:flutter/material.dart';
import 'package:torrent/torrent.dart';

import '../../core/redact.dart';
import '../../core/services.dart';
import '../../player/play_request.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/form_factor.dart';
import '../../ui/common/sections.dart';
import '../../ui/common/text_entry.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import '../receive/receive_page.dart';
import 'phone/phone_torrents_page.dart';
import 'torrent_files_page.dart';
import 'torrent_logic.dart';

/// Torrents section: paste a magnet, receive one from a phone, see the network
/// choice, and the files of the active torrent with its live stats.
class TorrentsPage extends StatelessWidget {
  const TorrentsPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) =>
      FormSwitch(tv: _TvTorrentsPage(focus: focus), phone: const PhoneTorrentsPage());
}

class _TvTorrentsPage extends StatefulWidget {
  const _TvTorrentsPage({required this.focus});

  final SectionFocus focus;

  @override
  State<_TvTorrentsPage> createState() => _TorrentsPageState();
}

class _TorrentsPageState extends State<_TvTorrentsPage> {
  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pasteMagnet() async {
    final service = AppServices.of(context).torrents;
    final text = await askText(context, title: 'Paste a magnet link', hint: 'magnet:?xt=urn:btih:...', kind: TextEntryKind.magnet);
    if (text == null || text.isEmpty || !mounted) return;
    if (btihFromMagnet(text) == null) {
      _say('That is not a magnet link');
      return;
    }
    if (!await service.ensureNetworkChoice(context) || !mounted) return;
    try {
      final info = await service.addMagnet(text);
      if (!mounted) {
        await service.removeActive(id: info.id);
        return;
      }
      await service.openFiles(context, info);
    } on TorrentException catch (e) {
      _say(redactText(e.message));
    } catch (e) {
      _say(redactText('$e'));
    }
  }

  Future<void> _play(TorrentInfo info, TorrentFile f) async {
    final service = AppServices.of(context).torrents;
    if (!f.streamable) {
      _say('Not a media file');
      return;
    }
    await openPlayer(context, service.playRequest(info, f));
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final service = AppServices.of(context).torrents;
    return Padding(
      padding: EdgeInsets.all(d.phone ? 16 : 32),
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final active = service.active;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Section.torrents.icon, size: d.u(48), color: ChithramColors.accent),
                const SizedBox(height: 16),
                Text('Torrents', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Stream a torrent while it downloads. It seeds only while you watch.',
                  style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    FocusCard(
                      key: TorrentKeys.pasteMagnet,
                      focusNode: widget.focus.entry,
                      section: widget.focus,
                      radius: 28,
                      onActivate: service.resolving ? null : _pasteMagnet,
                      child: ActionLabel(
                        icon: Icons.link_rounded,
                        text: service.resolving ? 'Finding peers...' : 'Paste magnet',
                        primary: true,
                      ),
                    ),
                    FocusCard(
                      key: TorrentKeys.sendFromPhone,
                      section: widget.focus,
                      radius: 28,
                      onActivate: () => openReceive(context),
                      child: const ActionLabel(icon: Icons.phone_android_rounded, text: 'Send from phone'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: FocusCard(
                    key: TorrentKeys.network,
                    section: widget.focus,
                    radius: 24,
                    onActivate: () => unawaited(service.changeNetworkChoice(context)),
                    child: ActionLabel(
                      icon: Icons.shield_outlined,
                      text: 'Network: ${service.guard.choice.label}',
                    ),
                  ),
                ),
                if (active != null) ...[
                  const SizedBox(height: 24),
                  Text(active.name ?? 'Torrent',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    statusLine(service.stats),
                    key: TorrentKeys.stats,
                    style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
                  ),
                  const SizedBox(height: 12),
                  TorrentFileList(
                    info: active,
                    focus: widget.focus,
                    takeEntry: false,
                    onPlay: (f) => unawaited(_play(active, f)),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

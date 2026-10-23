import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torrent/torrent.dart';

import '../../../core/redact.dart';
import '../../../core/services.dart';
import '../../../player/play_request.dart';
import '../../../theme.dart';
import '../../../ui/phone/phone_widgets.dart';
import '../torrent_files_page.dart' show TorrentKeys;
import '../torrent_logic.dart';
import 'phone_torrent_files.dart';

/// Torrents on a phone: paste or type a magnet link with the system keyboard,
/// the network choice, and the files of the active torrent.
class PhoneTorrentsPage extends StatefulWidget {
  const PhoneTorrentsPage({super.key});

  @override
  State<PhoneTorrentsPage> createState() => _PhoneTorrentsPageState();
}

class _PhoneTorrentsPageState extends State<PhoneTorrentsPage> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) _field.text = text.trim();
  }

  Future<void> _add() async {
    final service = AppServices.of(context).torrents;
    final text = _field.text.trim();
    if (text.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
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
      _field.clear();
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
    final service = AppServices.of(context).torrents;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final active = service.active;
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const PhoneNote('Stream a torrent while it downloads. It seeds only while you watch.'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 4),
              child: TextField(
                key: const ValueKey('torrent-magnet-field'),
                controller: _field,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  labelText: 'Magnet link',
                  hintText: 'magnet:?xt=urn:btih:...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    key: const ValueKey('torrent-magnet-paste'),
                    tooltip: 'Paste from clipboard',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _paste,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 8),
              child: FilledButton.icon(
                key: const ValueKey('torrent-magnet-add'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: service.resolving ? null : _add,
                icon: const Icon(Icons.link_rounded),
                label: Text(service.resolving ? 'Finding peers...' : 'Add magnet'),
              ),
            ),
            ListTile(
              key: TorrentKeys.network,
              minTileHeight: 56,
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Network'),
              subtitle: Text(service.guard.choice.label),
              onTap: () => unawaited(service.changeNetworkChoice(context)),
            ),
            if (active != null) ...[
              PhoneSectionTitle(active.name ?? 'Torrent'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: phoneGutter),
                child: Text(
                  statusLine(service.stats),
                  key: TorrentKeys.stats,
                  style: const TextStyle(color: ChithramColors.textDim),
                ),
              ),
              PhoneFileTiles(info: active, onPlay: (f) => unawaited(_play(active, f))),
            ],
          ],
        );
      },
    );
  }
}

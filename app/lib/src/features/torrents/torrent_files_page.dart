import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torrent/torrent.dart';

import '../../core/services.dart';
import '../../player/play_request.dart';
import '../../theme.dart';
import '../../ui/dims.dart';
import '../../ui/focus_card.dart';
import 'phone/phone_torrent_files.dart';
import 'torrent_logic.dart';

/// Widget keys for the file list, for tests.
abstract final class TorrentKeys {
  static const stats = ValueKey('torrent-stats');
  static const pasteMagnet = ValueKey('torrent-paste-magnet');
  static const sendFromPhone = ValueKey('torrent-send-from-phone');
  static const network = ValueKey('torrent-network');
  static ValueKey<String> file(int index) => ValueKey('torrent-file-$index');
}

/// The files of one torrent. Choosing a streamable file plays it; when the
/// player closes the torrent is gone and the page closes with it. Backing out
/// without playing removes the torrent too, so nothing keeps downloading.
class TorrentFilesPage extends StatefulWidget {
  const TorrentFilesPage({super.key, required this.info});

  final TorrentInfo info;

  @override
  State<TorrentFilesPage> createState() => _TorrentFilesPageState();
}

class _TorrentFilesPageState extends State<TorrentFilesPage> {
  final _focus = SectionFocus();
  late final _service = AppServices.of(context).torrents;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.entry.requestFocus();
    });
  }

  @override
  void dispose() {
    unawaited(_service.removeActive(id: widget.info.id));
    _focus.dispose();
    super.dispose();
  }

  Future<void> _play(TorrentFile f) async {
    if (!f.streamable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not a media file')));
      return;
    }
    await openPlayer(context, _service.playRequest(widget.info, f));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    if (d.phone) return PhoneTorrentFiles(info: widget.info, service: _service, onPlay: _play);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        body: Overscan(
          child: FocusScope(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(d.phone ? 12 : 24, 24, d.phone ? 12 : 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.info.name ?? 'Torrent',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: _service,
                    builder: (_, _) => Text(
                      statusLine(_service.stats),
                      key: TorrentKeys.stats,
                      style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TorrentFileList(info: widget.info, focus: _focus, onPlay: _play),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One focusable row per file: streamable first, largest first.
class TorrentFileList extends StatelessWidget {
  const TorrentFileList({
    super.key,
    required this.info,
    required this.focus,
    required this.onPlay,
    this.takeEntry = true,
  });

  final TorrentInfo info;
  final SectionFocus focus;
  final void Function(TorrentFile) onPlay;

  /// Gives the first row the section's entry node (when nothing above it does).
  final bool takeEntry;

  @override
  Widget build(BuildContext context) {
    final files = orderFiles(info.files);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < files.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: FocusCard(
              key: TorrentKeys.file(files[i].index),
              focusNode: takeEntry && i == 0 ? focus.entry : null,
              section: focus,
              radius: 18,
              onActivate: () => onPlay(files[i]),
              child: _FileRow(file: files[i]),
            ),
          ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final TorrentFile file;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final color = file.streamable ? Colors.white : ChithramColors.textDim;
    return Container(
      color: ChithramColors.surfaceHigh,
      padding: EdgeInsets.symmetric(horizontal: d.u(20), vertical: d.u(12)),
      child: Row(
        children: [
          Icon(file.streamable ? Icons.play_arrow_rounded : Icons.insert_drive_file_outlined,
              color: file.streamable ? ChithramColors.accent : ChithramColors.textDim, size: d.t(24)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(file.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: d.t(16), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Text(formatBytes(file.length), style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14))),
        ],
      ),
    );
  }
}

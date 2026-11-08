// The Downloads list on the Torrents pages, and the page of one download:
// progress, pause and resume, which files to fetch, play, open the folder,
// remove (keeping or deleting the files).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torrent/torrent.dart';

import '../../core/redact.dart';
import '../../core/services.dart';
import '../../player/play_request.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/phone/phone_widgets.dart';
import '../../ui/tv/focus_card.dart';
import 'downloads.dart';
import 'torrent_logic.dart';
import 'torrent_service.dart';

/// Widget keys, for tests.
abstract final class DownloadKeys {
  static ValueKey<String> row(String infoHash) => ValueKey('download-$infoHash');
  static const pause = ValueKey('download-pause');
  static const folder = ValueKey('download-folder');
  static const remove = ValueKey('download-remove');
  static ValueKey<String> file(int index) => ValueKey('download-file-$index');
}

/// Opens the page of [d].
Future<void> openDownload(BuildContext context, Download d) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DownloadPage(infoHash: d.infoHash)));

/// TV and desktop: one focusable row per download.
class DownloadsSection extends StatelessWidget {
  const DownloadsSection({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).torrents;
    final d = Dims.of(context);
    final list = service.downloads;
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text('Downloads',
            style: TextStyle(color: ChithramColors.of(context).accent, fontSize: d.t(14), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final dl in list.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: FocusCard(
              key: DownloadKeys.row(dl.infoHash),
              section: focus,
              radius: 18,
              onActivate: () => unawaited(openDownload(context, dl)),
              child: Container(
                color: ChithramColors.of(context).surfaceHigh,
                padding: EdgeInsets.symmetric(horizontal: d.u(20), vertical: d.u(12)),
                child: _DownloadSummary(download: dl, titleSize: d.t(16), lineSize: d.t(13)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Phone: a section title and one tile per download.
List<Widget> phoneDownloadTiles(BuildContext context, TorrentService service) {
  final list = service.downloads;
  if (list.isEmpty) return const [];
  return [
    const PhoneSectionTitle('Downloads'),
    for (final dl in list.reversed)
      ListTile(
        key: DownloadKeys.row(dl.infoHash),
        minTileHeight: 64,
        leading: Icon(_icon(dl)),
        title: Text(dl.name.isEmpty ? 'Torrent' : dl.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(value: dl.info == null ? null : dl.progress),
            const SizedBox(height: 4),
            Text(downloadLine(dl), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        onTap: () => unawaited(openDownload(context, dl)),
      ),
  ];
}

IconData _icon(Download d) {
  if (d.error != null || d.stats?.error != null) return Icons.error_outline_rounded;
  if (d.paused) return Icons.pause_circle_outline_rounded;
  if (d.finished) return Icons.download_done_rounded;
  return Icons.downloading_rounded;
}

class _DownloadSummary extends StatelessWidget {
  const _DownloadSummary({required this.download, required this.titleSize, required this.lineSize});

  final Download download;
  final double titleSize, lineSize;

  @override
  Widget build(BuildContext context) {
    final colors = ChithramColors.of(context);
    return Row(
      children: [
        Icon(_icon(download), color: colors.accent, size: titleSize * 1.6),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(download.name.isEmpty ? 'Torrent' : download.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(minHeight: 5, value: download.info == null ? null : download.progress),
              ),
              const SizedBox(height: 6),
              Text(downloadLine(download),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textDim, fontSize: lineSize)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One download. Looks it up by infohash on every build, so it follows the
/// engine restarting and closes when the download is removed.
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key, required this.infoHash});

  final String infoHash;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  late final TorrentService _service = AppServices.of(context).torrents;
  bool _busy = false;

  void _say(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } on TorrentException catch (e) {
      _say(redactText(e.message));
    } catch (e) {
      _say(redactText('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _chosen(Download d, int index) => d.record.onlyFiles?.contains(index) ?? true;

  Future<void> _toggle(Download d, TorrentFile f) => _run(() async {
        final all = [for (final x in d.info!.files) x.index];
        final now = {...(d.record.onlyFiles ?? all)};
        if (!now.remove(f.index)) now.add(f.index);
        if (now.isEmpty) {
          _say('Keep at least one file');
          return;
        }
        await _service.setDownloadFiles(d, now.toList());
      });

  Future<void> _play(Download d, TorrentFile f) async {
    if (!f.streamable) {
      _say('Not a media file');
      return;
    }
    // A file left out would never arrive: fetch it from now on.
    if (!_chosen(d, f.index)) await _toggle(d, f);
    if (d.paused) await _run(() => _service.resumeDownload(d));
    if (!mounted || d.info == null) return;
    await openPlayer(context, _service.playRequest(d.info!, f));
  }

  Future<void> _remove(Download d) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this download?'),
        content: Text('The files are in ${d.record.folder}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Remove, keep files')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove and delete files')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _run(() => _service.removeDownload(d, deleteFiles: choice));
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final d = _service.downloadFor(widget.infoHash);
          if (d == null) {
            return Scaffold(appBar: AppBar(), body: const Center(child: Text('Removed')));
          }
          return Scaffold(
            appBar: AppBar(title: Text(d.name.isEmpty ? 'Download' : d.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            body: SafeArea(child: _body(d)),
          );
        },
      ),
    );
  }

  Widget _body(Download d) {
    final colors = ChithramColors.of(context);
    final info = d.info;
    final progress = d.stats?.fileProgress ?? const <int>[];
    final canOpenFolder = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        LinearProgressIndicator(value: info == null ? null : d.progress, minHeight: 6),
        const SizedBox(height: 8),
        Text(downloadLine(d), style: TextStyle(color: colors.textDim)),
        const SizedBox(height: 4),
        SelectableText(d.record.folder, style: TextStyle(color: colors.textDim, fontSize: 12)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: DownloadKeys.pause,
              autofocus: true,
              onPressed: _busy
                  ? null
                  : () => _run(() => d.paused ? _service.resumeDownload(d) : _service.pauseDownload(d)),
              icon: Icon(d.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              label: Text(d.paused ? (d.info == null ? 'Start' : 'Resume') : 'Pause'),
            ),
            if (canOpenFolder)
              OutlinedButton.icon(
                key: DownloadKeys.folder,
                onPressed: () async {
                  if (!await _service.openFolder(d)) _say(d.record.folder);
                },
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open folder'),
              ),
            OutlinedButton.icon(
              key: DownloadKeys.remove,
              onPressed: _busy ? null : () => _remove(d),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (info == null)
          Text(d.error != null ? 'Not running: ${d.error}' : 'Waiting for the file list...',
              style: TextStyle(color: colors.textDim))
        else ...[
          Text('Files', style: TextStyle(color: colors.accent, fontWeight: FontWeight.w600)),
          Text('Untick a file to skip it. Select a media file to play it.',
              style: TextStyle(color: colors.textDim, fontSize: 12)),
          const SizedBox(height: 8),
          for (final f in orderFiles(info.files))
            ListTile(
              key: DownloadKeys.file(f.index),
              contentPadding: EdgeInsets.zero,
              leading: Checkbox(
                value: _chosen(d, f.index),
                onChanged: _busy ? null : (_) => unawaited(_toggle(d, f)),
              ),
              title: Text(f.path, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(_fileLine(f, f.index < progress.length ? progress[f.index] : null, _chosen(d, f.index))),
              trailing: f.streamable ? Icon(Icons.play_arrow_rounded, color: colors.accent) : null,
              onTap: f.streamable ? () => unawaited(_play(d, f)) : () => unawaited(_toggle(d, f)),
            ),
        ],
      ],
    );
  }
}

String _fileLine(TorrentFile f, int? done, bool chosen) {
  final size = formatBytes(f.length);
  if (!chosen) return '$size · skipped';
  if (done == null || f.length <= 0) return size;
  if (done >= f.length) return '$size · done';
  return '$size · ${(done * 100 / f.length).toStringAsFixed(0)}%';
}

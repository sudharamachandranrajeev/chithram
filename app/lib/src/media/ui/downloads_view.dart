import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/tokens.dart';
import '../../ui/tv/focus_card.dart';
import '../media_service.dart';
import '../models.dart';
import 'media_widgets.dart';

/// What the download clients are fetching right now (admins). Refreshes every
/// [refresh] while the screen is shown.
class DownloadsView extends StatefulWidget {
  const DownloadsView({super.key, required this.service, this.focus, this.refresh = const Duration(seconds: 15)});

  final MediaService service;
  final SectionFocus? focus;
  final Duration refresh;

  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  List<DownloadItem>? _items;
  String? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(widget.refresh, (_) => unawaited(_load(quiet: true)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await widget.service.call((c) => c.downloads());
      if (!mounted) return;
      setState(() {
        _items = r;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mediaErrorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final items = _items;
    if (!(widget.service.role?.canSeeDownloads ?? false)) {
      return const MediaMessage(icon: Icons.lock_outline_rounded, text: 'Downloads are for admins.');
    }
    if (_loading && items == null) {
      return const MediaMessage(icon: Icons.hourglass_empty_rounded, text: 'Loading downloads…', busy: true);
    }
    if (items == null) {
      return MediaMessage(
        icon: Icons.error_outline_rounded,
        text: _error ?? 'Could not load downloads.',
        actionLabel: 'Try again',
        onAction: () => unawaited(_load()),
      );
    }
    return ListView(
      padding: EdgeInsets.all(d.gutter),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Downloads', style: d.type.h1),
            const SizedBox(width: Space.s12),
            MediaButton(
              key: const ValueKey('media-downloads-refresh'),
              label: 'Refresh',
              icon: Icons.refresh_rounded,
              onPressed: () => unawaited(_load()),
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: d.type.meta.copyWith(color: ChithramColors.of(context).status.failed)),
        if (items.isEmpty)
          const MediaMessage(icon: Icons.download_done_rounded, text: 'Nothing is downloading.')
        else
          for (final (i, it) in items.indexed) _DownloadRow(key: ValueKey('media-download-$i'), item: it),
      ],
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({super.key, required this.item});

  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final p = item.progress;
    final pct = p == null ? null : (p * 100).round();
    final left = item.timeLeft;
    return Semantics(
      container: true,
      label: '${item.title}, ${item.status.label}${pct == null ? '' : ', $pct percent'}${left == null ? '' : ', $left left'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Text(item.title, style: d.type.row, maxLines: 2, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: Space.s8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.s8,
              runSpacing: Space.s4,
              children: [
                MediaStatusChip(item.status, progress: p),
                if (left != null && item.status == MediaStatus.downloading)
                  ExcludeSemantics(child: Text('$left left', style: d.type.meta.copyWith(color: c.textDim))),
              ],
            ),
            if (p != null) ...[
              const SizedBox(height: Space.s8),
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.chip),
                  child: LinearProgressIndicator(value: p, minHeight: 8, color: c.accent, backgroundColor: c.surfaceHigh),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

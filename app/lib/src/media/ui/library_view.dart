import 'dart:async';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';

import '../../player/play_request.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/tokens.dart';
import '../../ui/tv/focus_card.dart';
import '../gateway_client.dart';
import '../media_service.dart';
import '../models.dart';
import '../stream_proxy.dart';
import 'media_widgets.dart';

/// Plays a library item. Players cannot pin the gateway's certificate or send
/// the token, so this starts a loopback proxy (see [StreamProxy]) and hands the
/// player its plain-http loopback URL: no token in any URL.
Future<void> playLibraryItem(BuildContext context, MediaService service, LibraryItem item) async {
  final StreamProxy? started;
  try {
    started = await service.startStream(item.id);
  } catch (_) {
    return;
  }
  if (started == null) return;
  final StreamProxy proxy = started;
  if (!context.mounted) {
    await proxy.close();
    return;
  }
  try {
    await openPlayer(
      context,
      PlayRequest(
        itemId: 'media:${item.id}',
        title: item.title,
        subtitle: item.year?.toString(),
        resolve: () async => MediaSpec(videoUrl: proxy.url),
        onClose: proxy.close,
      ),
    );
  } finally {
    await proxy.close();
  }
}

/// The user's library as a poster grid. Movies play; series and albums are
/// listed but the gateway has no way to list their episodes or tracks yet.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key, required this.service, this.focus, this.onPlay});

  final MediaService service;
  final SectionFocus? focus;

  /// Overrides [playLibraryItem] (tests).
  final Future<void> Function(BuildContext context, LibraryItem item)? onPlay;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  LibraryKind _kind = LibraryKind.movies;
  final List<LibraryItem> _items = [];
  String? _next;
  bool _loading = true;
  bool _more = false;
  String? _error;
  String? _note;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    final gen = ++_gen;
    final kind = _kind;
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
        _items.clear();
        _next = null;
      }
      _error = null;
    });
    try {
      final cursor = more ? _next : null;
      final page = await widget.service.call((c) => c.library(kind, cursor: cursor));
      if (!mounted || gen != _gen) return;
      setState(() {
        _items.addAll(page.items);
        _next = page.nextCursor;
        _loading = false;
        _more = false;
      });
    } on GatewayException catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _more = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = mediaErrorText(e);
        _loading = false;
        _more = false;
      });
    }
  }

  void _pick(LibraryKind k) {
    if (k == _kind) return;
    setState(() {
      _kind = k;
      _note = null;
    });
    unawaited(_load());
  }

  void _open(LibraryItem item) {
    if (item.playable) {
      setState(() => _note = null);
      final play = widget.onPlay ?? (c, i) => playLibraryItem(c, widget.service, i);
      unawaited(play(context, item));
    } else {
      setState(() => _note = 'Episodes and tracks are not available in the app yet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final tileWidth = d.tv ? 170.0 : (d.phone ? 130.0 : 160.0);
    return ListView(
      padding: EdgeInsets.all(d.gutter),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final k in LibraryKind.values)
              MediaButton(
                key: ValueKey('media-library-${k.name}'),
                label: k.label,
                primary: k == _kind,
                onPressed: () => _pick(k),
              ),
          ],
        ),
        if (_note != null) Text(_note!, key: const ValueKey('media-library-note'), style: d.type.meta.copyWith(color: c.textDim)),
        const SizedBox(height: Space.s8),
        if (_loading)
          const MediaMessage(icon: Icons.hourglass_empty_rounded, text: 'Loading library…', busy: true)
        else if (_error != null && _items.isEmpty)
          MediaMessage(
            icon: Icons.error_outline_rounded,
            text: _error!,
            actionLabel: 'Try again',
            onAction: () => unawaited(_load()),
          )
        else if (_items.isEmpty)
          const MediaMessage(icon: Icons.video_library_outlined, text: 'Nothing in this library yet.')
        else ...[
          Wrap(
            spacing: Space.s16,
            runSpacing: Space.s16,
            children: [
              for (final it in _items)
                SizedBox(
                  width: tileWidth,
                  child: _PosterTile(key: ValueKey('media-item-${it.id}'), item: it, onOpen: () => _open(it)),
                ),
            ],
          ),
          if (_error != null) Text(_error!, style: d.type.meta.copyWith(color: c.status.failed)),
          if (_next != null)
            MediaButton(
              key: const ValueKey('media-library-more'),
              label: _more ? 'Loading…' : 'Load more',
              onPressed: _more ? null : () => unawaited(_load(more: true)),
            ),
        ],
      ],
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({super.key, required this.item, required this.onOpen});

  final LibraryItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final meta = [if (item.year != null) '${item.year}', if (!item.playable) _typeLabel(item.type)].join(' · ');
    return Semantics(
      button: true,
      label: '${item.playable ? 'Play ' : ''}${item.title}${meta.isEmpty ? '' : ', $meta'}',
      excludeSemantics: true,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FocusCard(
              radius: Radii.card(d.form),
              onActivate: onOpen,
              child: ColoredBox(
                color: c.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        MediaImage(path: item.poster, label: '${item.title} poster'),
                        if (item.playable)
                          Positioned(
                            right: Space.s8,
                            bottom: Space.s8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: c.background.withValues(alpha: 0.7), shape: BoxShape.circle),
                              child: Padding(
                                padding: const EdgeInsets.all(Space.s4),
                                child: Icon(Icons.play_arrow_rounded, color: c.text, size: 24),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Space.s8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: d.type.card, maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (meta.isNotEmpty)
                            Text(meta, style: d.type.meta.copyWith(color: c.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(String t) => switch (t) {
        'Series' => 'Show',
        'MusicAlbum' => 'Album',
        _ => t,
      };
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/text_entry.dart';
import '../../ui/common/tokens.dart';
import '../../ui/tv/focus_card.dart';
import '../gateway_client.dart';
import '../media_service.dart';
import '../models.dart';
import 'media_widgets.dart';

/// How long typing must pause before a search goes out. The gateway allows 30
/// a minute per device.
const searchDebounce = Duration(milliseconds: 600);

/// Search the catalogue through the gateway; request what is missing.
class SearchView extends StatefulWidget {
  const SearchView({super.key, required this.service, this.focus, this.debounce = searchDebounce});

  final MediaService service;
  final SectionFocus? focus;
  final Duration debounce;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  String _query = '';
  Timer? _timer;
  int _gen = 0;
  bool _loading = false;
  String? _error;
  List<SearchItem>? _results;
  DateTime? _blockedUntil;
  final Set<int> _requesting = {};
  final Map<int, String> _notes = {};

  MediaRole get _role => widget.service.role ?? MediaRole.viewer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _typed(String v) {
    setState(() => _query = v);
    _timer?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      _gen++;
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    _timer = Timer(widget.debounce, () => unawaited(_search(q)));
  }

  void _submitted(String v) {
    _timer?.cancel();
    final q = v.trim();
    if (q.length >= 2) unawaited(_search(q));
  }

  Future<void> _search(String q) async {
    final until = _blockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final s = until.difference(DateTime.now()).inSeconds + 1;
      setState(() => _error = 'Too many searches. Try again in $s s.');
      return;
    }
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.service.call((c) => c.search(q));
      if (!mounted || gen != _gen) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } on GatewayException catch (e) {
      if (!mounted || gen != _gen) return;
      if (e.kind == GatewayErrorKind.rateLimited) {
        _blockedUntil = DateTime.now().add(e.retryAfter ?? const Duration(seconds: 60));
      }
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = mediaErrorText(e);
      });
    }
  }

  Future<void> _request(SearchItem item) async {
    if (!_role.canRequest || !_requesting.add(item.tmdbId)) return;
    setState(() => _notes.remove(item.tmdbId));
    try {
      final r = await widget.service.call((c) => c.createRequest(item.tmdbId, item.type));
      _setStatus(item, r.status == MediaStatus.none ? MediaStatus.requested : r.status);
    } on GatewayException catch (e) {
      if (!mounted) return;
      if (e.kind == GatewayErrorKind.conflict) {
        _setStatus(item, MediaStatus.requested);
      } else {
        setState(() => _notes[item.tmdbId] = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _notes[item.tmdbId] = mediaErrorText(e));
    } finally {
      _requesting.remove(item.tmdbId);
      if (mounted) setState(() {});
    }
  }

  void _setStatus(SearchItem item, MediaStatus s) {
    if (!mounted) return;
    final list = _results;
    if (list == null) return;
    setState(() {
      _results = [for (final e in list) e.tmdbId == item.tmdbId && e.type == item.type ? e.withStatus(s) : e];
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final results = _results;
    return ListView(
      padding: EdgeInsets.all(d.gutter),
      children: [
        MediaField(
          fieldKey: const ValueKey('media-search-field'),
          label: 'Search movies and shows',
          hint: 'Title',
          value: _query,
          kind: TextEntryKind.search,
          section: widget.focus,
          onChanged: _typed,
          onSubmitted: _submitted,
        ),
        const SizedBox(height: Space.s8),
        if (_loading)
          const MediaMessage(icon: Icons.search_rounded, text: 'Searching…', busy: true)
        else if (_error != null)
          MediaMessage(icon: Icons.error_outline_rounded, text: _error!)
        else if (results == null)
          MediaMessage(
            icon: Icons.search_rounded,
            text: 'Type at least two letters. Results come from your media server.',
            key: const ValueKey('media-search-hint'),
          )
        else if (results.isEmpty)
          const MediaMessage(icon: Icons.search_off_rounded, text: 'No matches.')
        else
          for (final item in results)
            _ResultRow(
              key: ValueKey('media-result-${item.type}-${item.tmdbId}'),
              item: item,
              canRequest: _role.canRequest,
              busy: _requesting.contains(item.tmdbId),
              note: _notes[item.tmdbId],
              onRequest: () => unawaited(_request(item)),
              dim: c.textDim,
            ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.item,
    required this.canRequest,
    required this.busy,
    required this.note,
    required this.onRequest,
    required this.dim,
  });

  final SearchItem item;
  final bool canRequest;
  final bool busy;
  final String? note;
  final VoidCallback onRequest;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final kind = item.type == 'tv' ? 'Show' : 'Movie';
    final meta = [kind, if (item.year != null) '${item.year}'].join(' · ');
    return Semantics(
      container: true,
      label: '${item.title}, $meta, ${item.status.label}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Text(item.title, style: d.type.row, maxLines: 2, overflow: TextOverflow.ellipsis)),
            ExcludeSemantics(child: Text(meta, style: d.type.meta.copyWith(color: dim))),
            if (item.overview != null)
              ExcludeSemantics(
                child: Text(item.overview!, style: d.type.body.copyWith(color: dim), maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: Space.s8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.s8,
              runSpacing: Space.s4,
              children: [
                MediaStatusChip(item.status),
                // Viewers cannot request; a title that is already in the pipeline has nothing to request.
                if (canRequest && item.status == MediaStatus.none)
                  MediaButton(
                    key: ValueKey('media-request-${item.type}-${item.tmdbId}'),
                    label: busy ? 'Requesting…' : 'Request',
                    icon: Icons.add_rounded,
                    semanticLabel: 'Request ${item.title}',
                    onPressed: busy ? null : onRequest,
                  ),
              ],
            ),
            if (note != null) Text(note!, style: d.type.meta.copyWith(color: ChithramColors.of(context).status.failed)),
          ],
        ),
      ),
    );
  }
}

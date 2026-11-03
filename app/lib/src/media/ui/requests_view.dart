import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/tokens.dart';
import '../../ui/tv/focus_card.dart';
import '../media_service.dart';
import '../models.dart';
import 'media_widgets.dart';

/// The user's requests (all of them for an admin), with approve and decline
/// for admins on those awaiting approval.
class RequestsView extends StatefulWidget {
  const RequestsView({super.key, required this.service, this.focus});

  final MediaService service;
  final SectionFocus? focus;

  @override
  State<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<RequestsView> {
  final List<RequestItem> _items = [];
  String? _next;
  bool _loading = true;
  bool _more = false;
  String? _error;
  final Set<int> _deciding = {};
  final Map<int, String> _notes = {};
  int _gen = 0;

  bool get _admin => widget.service.role?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    final gen = ++_gen;
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final cursor = more ? _next : null;
      final page = await widget.service.call((c) => c.requests(cursor: cursor));
      if (!mounted || gen != _gen) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        _next = page.nextCursor;
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

  Future<void> _decide(RequestItem r, bool approve) async {
    if (!_admin || !r.status.decidable || !_deciding.add(r.id)) return;
    setState(() => _notes.remove(r.id));
    try {
      final updated = await widget.service.call((c) => c.decide(r.id, approve: approve));
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((e) => e.id == r.id);
        if (i >= 0) _items[i] = r.withStatus(updated.status);
      });
    } catch (e) {
      if (mounted) setState(() => _notes[r.id] = mediaErrorText(e));
    } finally {
      _deciding.remove(r.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    if (_loading) return const MediaMessage(icon: Icons.hourglass_empty_rounded, text: 'Loading requests…', busy: true);
    if (_error != null && _items.isEmpty) {
      return MediaMessage(
        icon: Icons.error_outline_rounded,
        text: _error!,
        actionLabel: 'Try again',
        onAction: () => unawaited(_load()),
      );
    }
    if (_items.isEmpty) {
      return MediaMessage(
        icon: Icons.inbox_outlined,
        text: 'No requests yet. Search for a title and request it.',
        actionLabel: 'Refresh',
        onAction: () => unawaited(_load()),
      );
    }
    return ListView(
      padding: EdgeInsets.all(d.gutter),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_admin ? 'All requests' : 'Your requests', style: d.type.h1),
            const SizedBox(width: Space.s12),
            MediaButton(
              key: const ValueKey('media-requests-refresh'),
              label: 'Refresh',
              icon: Icons.refresh_rounded,
              onPressed: () => unawaited(_load()),
            ),
          ],
        ),
        for (final r in _items)
          _RequestRow(
            key: ValueKey('media-request-row-${r.id}'),
            item: r,
            admin: _admin,
            busy: _deciding.contains(r.id),
            note: _notes[r.id],
            onApprove: () => unawaited(_decide(r, true)),
            onDecline: () => unawaited(_decide(r, false)),
          ),
        if (_error != null) Text(_error!, style: d.type.meta.copyWith(color: ChithramColors.of(context).status.failed)),
        if (_next != null)
          MediaButton(
            key: const ValueKey('media-requests-more'),
            label: _more ? 'Loading…' : 'Load more',
            onPressed: _more ? null : () => unawaited(_load(more: true)),
          ),
      ],
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    super.key,
    required this.item,
    required this.admin,
    required this.busy,
    required this.note,
    required this.onApprove,
    required this.onDecline,
  });

  final RequestItem item;
  final bool admin;
  final bool busy;
  final String? note;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final kind = item.type == null ? null : (item.type == 'tv' ? 'Show' : 'Movie');
    final meta = [?kind, if (admin && item.requestedBy != null) 'by ${item.requestedBy}'].join(' · ');
    return Semantics(
      container: true,
      label: '${item.displayTitle}, ${item.status.label}${meta.isEmpty ? '' : ', $meta'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Text(item.displayTitle, style: d.type.row, maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (meta.isNotEmpty) ExcludeSemantics(child: Text(meta, style: d.type.meta.copyWith(color: c.textDim))),
            const SizedBox(height: Space.s8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.s8,
              runSpacing: Space.s4,
              children: [
                MediaStatusChip(item.status),
                // The server refuses these for non-admins; do not offer them.
                if (admin && item.status.decidable) ...[
                  MediaButton(
                    key: ValueKey('media-approve-${item.id}'),
                    label: 'Approve',
                    icon: Icons.check_rounded,
                    semanticLabel: 'Approve request for ${item.displayTitle}',
                    onPressed: busy ? null : onApprove,
                  ),
                  MediaButton(
                    key: ValueKey('media-decline-${item.id}'),
                    label: 'Decline',
                    icon: Icons.close_rounded,
                    semanticLabel: 'Decline request for ${item.displayTitle}',
                    onPressed: busy ? null : onDecline,
                  ),
                ],
              ],
            ),
            if (note != null) Text(note!, style: d.type.meta.copyWith(color: c.status.failed)),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services.dart';
import '../theme.dart';
import '../ui/common/dims.dart';
import 'find_api.dart';

/// R0 stub (WP-E replaces it): asks every available provider and lists the
/// raw results as they arrive, unranked.
class FindPage extends StatefulWidget {
  const FindPage({super.key, required this.query});

  final FindQuery query;

  @override
  State<FindPage> createState() => _FindPageState();
}

class _FindPageState extends State<FindPage> {
  final _cancel = CancelToken();
  final _results = <FindResult>[];
  final _subs = <StreamSubscription<FindResult>>[];
  int _providers = 0;
  bool _started = false;

  String get _what => switch (widget.query) {
        TitleQuery(:final title) => title,
        EpisodeQuery(:final show, :final season, :final episode) => '$show S${season}E$episode',
        TextQuery(:final text) => text,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppServices.of(context);
    final providers = [
      for (final s in services.findSources) ...s.providers.value.where((p) => p.available),
    ];
    _providers = providers.length;
    for (final p in providers) {
      _subs.add(p.search(widget.query, _cancel).listen(
        (r) {
          if (mounted) setState(() => _results.add(r));
        },
        onError: (Object _) {},
      ));
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Scaffold(
      appBar: AppBar(title: Text("Find sources for '$_what'")),
      body: _results.isEmpty
          ? Center(
              child: Text(
                _providers == 0 ? 'No search providers added yet.' : 'Searching...',
                style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(16)),
              ),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                return ListTile(
                  autofocus: i == 0,
                  title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${r.providerId}${r.seeders != null ? ' · ${r.seeders} seeders' : ''}'),
                );
              },
            ),
    );
  }
}

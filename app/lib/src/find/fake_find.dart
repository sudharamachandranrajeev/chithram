import 'dart:async';

import 'package:flutter/foundation.dart';

import '../player/play_request.dart';
import 'find_api.dart';

/// A [FindProvider] that emits [results] one by one (after [delay]) and stops
/// early when cancelled. `fetchTorrent` returns [torrentBytes].
class FakeFindProvider implements FindProvider {
  FakeFindProvider({
    this.id = 'fake',
    this.label = 'Fake',
    this.available = true,
    this.unavailableReason,
    this.results = const [],
    this.delay = Duration.zero,
    Uint8List? torrentBytes,
  }) : torrentBytes = torrentBytes ?? Uint8List(0);

  @override
  final String id, label;
  @override
  bool available;
  @override
  String? unavailableReason;
  final List<FindResult> results;
  final Duration delay;
  final Uint8List torrentBytes;
  final queries = <FindQuery>[];

  @override
  Stream<FindResult> search(FindQuery q, CancelToken c) async* {
    queries.add(q);
    for (final r in results) {
      if (delay > Duration.zero) await Future.any([Future<void>.delayed(delay), c.whenCancelled]);
      if (c.cancelled) return;
      yield r;
    }
  }

  @override
  Future<Uint8List> fetchTorrent(FindResult r) async => torrentBytes;

  @override
  Future<PlayRequest> playRequest(FindResult r) =>
      Future.error(UnsupportedError('FakeFindProvider has nothing to play'));
}

class FakeFindProviderSource implements FindProviderSource {
  FakeFindProviderSource([List<FindProvider> providers = const []])
      : _providers = ValueNotifier(providers);

  final ValueNotifier<List<FindProvider>> _providers;

  set value(List<FindProvider> p) => _providers.value = p;

  @override
  ValueListenable<List<FindProvider>> get providers => _providers;
}

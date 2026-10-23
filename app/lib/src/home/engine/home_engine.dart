import 'package:flutter/foundation.dart';

import '../home_repository.dart';
import '../home_source.dart';
import '../snapshot.dart';

/// R0 stub (WP-B replaces it): serves the snapshot read at launch and never
/// refreshes.
class HomeEngine implements HomeRepository {
  HomeEngine({HomeSnapshot? snapshot, this.source = const UnconfiguredHomeSource()})
      : _state = ValueNotifier(HomeState(
          snapshot: snapshot,
          configured: source.configured,
          status: {
            if (snapshot != null) for (final r in snapshot.rails) r.id: RailStatus.stale,
          },
        ));

  final HomeSource source;
  final ValueNotifier<HomeState> _state;

  @override
  ValueListenable<HomeState> get state => _state;

  @override
  Future<void> refresh({bool force = false}) async {}

  @override
  void setVisible(bool v) {}

  @override
  void noteInteraction() {}
}

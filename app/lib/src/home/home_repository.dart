import 'package:flutter/foundation.dart';

import 'snapshot.dart';

enum RailStatus { fresh, stale, loading, failed }

class HomeState {
  const HomeState({
    this.snapshot,
    this.status = const {},
    this.configured = false,
    this.keyRejected = false,
  });

  final HomeSnapshot? snapshot;
  final Map<String, RailStatus> status;
  final bool configured, keyRejected;
}

/// Home's data (WP-B implements; WP-C consumes). [state] changes only on the
/// UI isolate; a refresh never moves focus or reorders the focused rail.
abstract interface class HomeRepository {
  ValueListenable<HomeState> get state;

  /// Fetches stale rails (all with [force]). Does nothing without a key.
  Future<void> refresh({bool force = false});

  /// Home is on screen: refresh every 30 min and apply new data live.
  void setVisible(bool v);

  /// Input happened: the focused rail may update after 20 s without it.
  void noteInteraction();
}

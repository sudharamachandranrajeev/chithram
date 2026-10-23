import 'package:flutter/widgets.dart';

/// Widget keys of the player route, for tests. `Keys.playerRoot`,
/// `Keys.playerPosition` and `Keys.playerError` live in `ui/common/keys.dart`.
abstract final class PlayerKeys {
  /// A `Text` with the duration as `m:ss`; absent until known.
  static const duration = ValueKey('player-duration');
  static const title = ValueKey('player-title');
  static const status = ValueKey('player-status');
  static const spinner = ValueKey('player-spinner');
  static const retry = ValueKey('player-retry');
  static const back = ValueKey('player-back');
  static const resume = ValueKey('player-resume');
  static const startOver = ValueKey('player-start-over');
}

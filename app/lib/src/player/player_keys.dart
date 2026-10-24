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

  static const seekBar = ValueKey('player-seek-bar');
  static const heatmap = ValueKey('player-heatmap');
  static const previewThumb = ValueKey('player-preview-thumb');
  static const bubbleTime = ValueKey('player-bubble-time');
  static const bubbleChapter = ValueKey('player-bubble-chapter');
  static const livePill = ValueKey('player-live-pill');
  static const remaining = ValueKey('player-remaining');
  static const previous = ValueKey('player-previous');
  static const next = ValueKey('player-next');
  static const playPause = ValueKey('player-play-pause');
  static const upNext = ValueKey('player-up-next');
  static const upNextTitle = ValueKey('player-up-next-title');
  static const upNextCount = ValueKey('player-up-next-count');
  static const upNextPlay = ValueKey('player-up-next-play');
  static const upNextCancel = ValueKey('player-up-next-cancel');
}

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';

import 'player_route.dart';

/// Everything the player route needs to play one item. Every source (YouTube,
/// IPTV, torrents, plain links) produces one.
class PlayRequest {
  const PlayRequest({
    required this.itemId,
    required this.title,
    this.subtitle,
    this.artwork,
    this.isLive = false,
    required this.resolve,
    this.onClose,
    this.onWatched,
    this.status,
    this.zap,
  });

  /// A stable id, see `core/item_id.dart`.
  final String itemId;
  final String title;
  final String? subtitle;
  final String? artwork;
  final bool isLive;

  /// Called on open and on Retry.
  final Future<MediaSpec> Function() resolve;

  /// Called when the route closes, e.g. to stop a torrent.
  final Future<void> Function()? onClose;

  /// Called once when the item stops (closed, or zapped away from) with the
  /// last position and the length (zero for live), e.g. for watch history.
  final void Function(Duration position, Duration duration)? onWatched;

  /// A status line for the OSD, e.g. torrent speed and peers.
  final Stream<String>? status;

  /// Set for live TV: Up and Down move through it.
  final ZapList? zap;
}

/// A list of channels the player can step through.
abstract interface class ZapList {
  int get length;
  int get initialIndex;
  String titleAt(int i);
  PlayRequest requestAt(int i);
}

/// How many players are open (0 or 1). Telegram's auto-play waits for 0.
abstract final class PlayerActivity {
  static final open = ValueNotifier<int>(0);
  static bool get idle => open.value == 0;
}

/// Pushes the fullscreen player. Completes when it closes.
Future<void> openPlayer(BuildContext context, PlayRequest request) async {
  PlayerActivity.open.value++;
  try {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerRoute(request: request)),
    );
  } finally {
    PlayerActivity.open.value--;
  }
}

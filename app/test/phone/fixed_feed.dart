import 'package:chithram/src/features/youtube/feed/youtube_feed.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:flutter/foundation.dart';

/// A feed that shows one fixed [FeedState] and never touches disk or network.
class FixedFeed extends YouTubeFeed {
  FixedFeed(FeedState state)
      : _state = ValueNotifier(state),
        super(youtube: YouTubeService(browse: FixtureBrowse('')));

  final ValueNotifier<FeedState> _state;

  @override
  ValueListenable<FeedState> get state => _state;

  @override
  Future<void> open() async {}

  @override
  Future<void> refresh({bool force = false}) async {}
}

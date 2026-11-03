import 'package:chithram/src/features/youtube/feed/youtube_feed.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:flutter/foundation.dart';

/// A feed that shows a fixed [FeedState] and never touches disk or network:
/// a Continue watching row with progress, and two popular rows.
class StaticFeed extends YouTubeFeed {
  StaticFeed()
      : _state = ValueNotifier(_fixture),
        super(youtube: YouTubeService(browse: FixtureBrowse('')));

  final ValueNotifier<FeedState> _state;

  static final _fixture = () {
    final cont = FixtureBrowse.videos('c', 6);
    final music = FixtureBrowse.videos('m', 8);
    final live = FixtureBrowse.videos('l', 5);
    return FeedState(
      hero: music.take(5).toList(),
      rails: [
        FeedRail(
          'continue',
          'Continue watching',
          cont,
          progress: {for (final (i, v) in cont.indexed) v.videoId: 0.15 + 0.12 * i},
        ),
        FeedRail('popular-music', 'Popular music', music),
        FeedRail('popular-live', 'Live now', live),
      ],
    );
  }();

  @override
  ValueListenable<FeedState> get state => _state;

  @override
  Future<void> open() async {}

  @override
  Future<void> refresh({bool force = false}) async {}
}

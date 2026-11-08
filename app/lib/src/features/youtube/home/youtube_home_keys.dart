import 'package:flutter/widgets.dart';

/// Keys of the YouTube home and its results page, for tests.
abstract final class YouTubeHomeKeys {
  /// The search field (desktop, phone). The phone tests have always looked
  /// for this key on the YouTube tab.
  static const searchField = ValueKey('search-field');

  /// The TV search bar, which opens the on-screen keyboard.
  static const searchBar = ValueKey('yt-search-bar');

  /// A suggestion row under the search field.
  static ValueKey<String> suggestion(int i) => ValueKey('yt-suggestion-$i');

  /// A topic chip: `for-you`, `continue`, `music`, `live`, `sports`, `news`, `gaming`.
  static ValueKey<String> chip(String topic) => ValueKey('yt-chip-$topic');

  /// The content shown for a topic (changes as chips switch it).
  static ValueKey<String> topic(String topic) => ValueKey('yt-topic-$topic');

  /// The loading skeleton, the error panel and its Retry.
  static const skeleton = ValueKey('yt-home-skeleton');
  static const error = ValueKey('yt-home-error');
  static const retry = ValueKey('yt-home-retry');

  /// The billboard and its buttons.
  static const hero = ValueKey('yt-hero');
  static const heroPlay = ValueKey('yt-hero-play');
  static const heroDetails = ValueKey('yt-hero-details');

  /// The results page, its search field and back button.
  static const results = ValueKey('yt-results');
  static const resultsField = ValueKey('yt-results-field');
  static const resultsBack = ValueKey('yt-results-back');
  static const resultsStatus = ValueKey('yt-results-status');

  /// The details sheet and its Play.
  static const details = ValueKey('yt-details');
  static const detailsPlay = ValueKey('yt-details-play');
}

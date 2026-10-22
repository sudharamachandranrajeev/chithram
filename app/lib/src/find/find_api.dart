import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../player/play_request.dart';
import 'find_page.dart';

/// What to look for. Built from a TMDB title, an episode, or free text.
sealed class FindQuery {
  const FindQuery();
}

final class TitleQuery extends FindQuery {
  const TitleQuery({
    required this.tmdbId,
    required this.title,
    this.originalTitle,
    this.imdbId,
    this.artwork,
    this.year,
    this.runtimeMin,
  });
  final int tmdbId;
  final String title;
  final String? originalTitle, imdbId, artwork;
  final int? year, runtimeMin;
}

final class EpisodeQuery extends FindQuery {
  const EpisodeQuery({
    required this.tmdbId,
    required this.show,
    this.originalShow,
    this.episodeTitle,
    this.imdbId,
    this.artwork,
    this.year,
    this.tvdbId,
    this.runtimeMin,
    required this.season,
    required this.episode,
  });
  final int tmdbId;
  final String show;
  final String? originalShow, episodeTitle, imdbId, artwork;
  final int? year, tvdbId, runtimeMin;
  final int season, episode;
}

final class TextQuery extends FindQuery {
  const TextQuery(this.text);
  final String text;
}

enum ResultKind { torrent, video, live }

class FindResult {
  const FindResult({
    required this.providerId,
    required this.title,
    required this.kind,
    this.sizeBytes,
    this.seeders,
    this.leechers,
    this.infoHash,
    this.magnet,
    this.itemId,
    this.detailsUrl,
    this.published,
    this.hasTorrentFile = false,
  });

  final String providerId, title;
  final ResultKind kind;
  final int? sizeBytes, seeders, leechers;

  /// `itemId` is the `yt:...` or `iptv:...` id of a video or live result.
  final String? infoHash, magnet, itemId, detailsUrl;
  final DateTime? published;
  final bool hasTorrentFile;
}

class CancelToken {
  final _done = Completer<void>();

  bool get cancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;

  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// One place results come from: a plugin, a Torznab endpoint, YouTube, IPTV.
abstract interface class FindProvider {
  String get id;
  String get label;
  bool get available;
  String? get unavailableReason;

  /// Streams results as they arrive; closes when done or [c] is cancelled.
  Stream<FindResult> search(FindQuery q, CancelToken c);

  /// The .torrent bytes for a result, through the provider's own allowlisted
  /// channel, at most 2 MiB.
  Future<Uint8List> fetchTorrent(FindResult r);

  /// For video and live results.
  Future<PlayRequest> playRequest(FindResult r);
}

/// A provider list that changes (plugins installed, endpoints enabled).
abstract interface class FindProviderSource {
  ValueListenable<List<FindProvider>> get providers;
}

/// Opens the Find sources page for [q].
Future<void> openFindSources(BuildContext c, FindQuery q) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => FindPage(query: q)));

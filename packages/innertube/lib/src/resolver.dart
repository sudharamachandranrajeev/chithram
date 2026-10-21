import 'package:http/http.dart' as http;

import 'clients.dart';
import 'errors.dart';
import 'explode_tier.dart';
import 'models.dart';
import 'net.dart';
import 'player_parser.dart';

const defaultTierTimeouts = {
  Tier.visionos: Duration(seconds: 8),
  Tier.androidVr: Duration(seconds: 8),
  Tier.tv: Duration(seconds: 8),
  Tier.explode: Duration(seconds: 25),
};

/// Resolves a video id to streams through tiers in order:
/// VISIONOS (visitor data cached, refreshed on LOGIN_REQUIRED) -> android_vr
/// -> tv -> youtube_explode_dart. Each tier has a short timeout; the winner
/// is recorded in [VideoStreams.tier] and every try in
/// [VideoStreams.attempts].
class YouTubeResolver {
  YouTubeResolver({
    http.Client? client,
    this.tiers = const [Tier.visionos, Tier.androidVr, Tier.tv, Tier.explode],
    this.timeouts = defaultTierTimeouts,
    ExplodeResolver? explode,
  })  : net = Net(client),
        _explode = explode {
    visitor = VisitorData(net);
  }

  final Net net;
  final List<Tier> tiers;
  final Map<Tier, Duration> timeouts;
  late final VisitorData visitor;
  ExplodeResolver? _explode;

  static const _clients = {
    Tier.visionos: visionosClient,
    Tier.androidVr: androidVrClient,
    Tier.tv: tvClient,
  };

  Future<VideoStreams> resolve(String videoId) async {
    final attempts = <TierAttempt>[];
    for (final tier in tiers) {
      final watch = Stopwatch()..start();
      try {
        final streams = await _tryTier(tier, videoId);
        attempts.add(TierAttempt(tier, watch.elapsed));
        return streams.withAttempts(tier, List.unmodifiable(attempts));
      } catch (error) {
        attempts.add(TierAttempt(tier, watch.elapsed, error: _describe(error)));
      }
    }
    throw AllTiersFailed(videoId, attempts);
  }

  String _describe(Object error) =>
      error is InnertubeException ? error.message : '${error.runtimeType}: $error';

  Future<VideoStreams> _tryTier(Tier tier, String videoId) {
    final limit = timeouts[tier] ?? const Duration(seconds: 8);
    if (tier == Tier.explode) {
      final explode = _explode ??= explodeResolver();
      return explode(videoId).timeout(limit);
    }
    return _innertube(_clients[tier]!, videoId, limit);
  }

  Future<VideoStreams> _innertube(PlayerClient client, String videoId, Duration limit) async {
    Future<VideoStreams> once({required bool fresh}) async {
      final id = await visitor.get(fresh: fresh);
      final response = await fetchPlayer(net, client, videoId, id, timeout: limit);
      return parsePlayerResponse(response, tier: client.tier, userAgent: client.userAgent);
    }

    // The timeout covers the whole tier, including the visitor-data refresh.
    return Future(() async {
      try {
        return await once(fresh: false);
      } on PlayabilityException catch (error) {
        if (!error.loginRequired || client.tier != Tier.visionos) rethrow;
        // Bot check: a new visitor id often clears it.
        return once(fresh: true);
      }
    }).timeout(limit * 2);
  }
}

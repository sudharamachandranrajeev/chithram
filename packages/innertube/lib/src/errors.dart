import 'models.dart';

class InnertubeException implements Exception {
  InnertubeException(this.message);
  final String message;
  @override
  String toString() => 'InnertubeException: $message';
}

/// An HTTP status of 400 or above.
class HttpStatusException extends InnertubeException {
  HttpStatusException(this.status, String host) : super('$host said $status');
  final int status;
}

/// The player response's `playabilityStatus` was not OK.
class PlayabilityException extends InnertubeException {
  PlayabilityException(this.status, this.reason) : super('$status: $reason');
  final String status;
  final String reason;

  /// The bot check: retry with fresh visitor data or another client.
  bool get loginRequired => status == 'LOGIN_REQUIRED';
}

/// Every tier failed.
class AllTiersFailed extends InnertubeException {
  AllTiersFailed(this.videoId, this.attempts)
      : super('no tier could resolve $videoId: ${attempts.map((a) => '${a.tier.name}: ${a.error}').join('; ')}');
  final String videoId;
  final List<TierAttempt> attempts;
}

import '../ui/common/status_chip.dart';

/// What the gateway lets a paired device do. The server is authoritative; the
/// app only hides what would be refused.
enum MediaRole {
  admin('Admin'),
  requester('Requester'),
  viewer('Viewer');

  const MediaRole(this.label);

  final String label;

  bool get canRequest => this == admin || this == requester;
  bool get isAdmin => this == admin;

  /// `GET /v1/downloads` is admin only.
  bool get canSeeDownloads => isAdmin;

  static MediaRole? parse(Object? s) {
    for (final r in values) {
      if (r.name == s) return r;
    }
    return null;
  }
}

/// A response that does not match the contract.
class ModelError implements Exception {
  const ModelError(this.message);

  final String message;

  @override
  String toString() => 'ModelError: $message';
}

final _ctl = RegExp(r'[\u0000-\u001f\u007f]');

/// Text from the server for display: control characters out, length capped.
String _text(Object? v, String what, {int max = 500, bool required = true}) {
  if (v == null) {
    if (required) throw ModelError('$what missing');
    return '';
  }
  if (v is! String) throw ModelError('$what is not text');
  final s = v.replaceAll(_ctl, ' ').trim();
  if (required && s.isEmpty) throw ModelError('$what empty');
  return s.length > max ? s.substring(0, max) : s;
}

String? _optText(Object? v, String what, {int max = 500}) {
  if (v == null) return null;
  final s = _text(v, what, max: max, required: false);
  return s.isEmpty ? null : s;
}

int _int(Object? v, String what) {
  if (v is! int) throw ModelError('$what is not an integer');
  return v;
}

int? _optInt(Object? v, String what) => v == null ? null : _int(v, what);

Map<String, Object?> asMap(Object? v, String what) {
  if (v is! Map) throw ModelError('$what is not an object');
  return v.cast<String, Object?>();
}

List<Object?> asList(Object? v, String what, {int max = 200}) {
  if (v is! List) throw ModelError('$what is not a list');
  if (v.length > max) throw ModelError('$what too long');
  return v;
}

/// Where a request or title stands, as the gateway names it (see its
/// `status_map.dart`).
enum MediaStatus {
  none,
  requested,
  awaitingApproval,
  approved,
  searching,
  downloading,
  importing,
  available,
  failed;

  static MediaStatus parse(Object? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    throw const ModelError('unknown status');
  }

  /// The short label, also the screen reader's text.
  String get label => switch (this) {
        none => 'Not requested',
        requested => 'Requested',
        awaitingApproval => 'Awaiting approval',
        approved => 'Approved',
        searching => 'Searching',
        downloading => 'Downloading',
        importing => 'Importing',
        available => 'Available',
        failed => 'Failed',
      };

  /// The shared chip's status; null for [none] and [approved] (the media
  /// chip draws [approved] itself).
  RequestStatus? get chip => switch (this) {
        none || approved => null,
        requested => RequestStatus.requested,
        awaitingApproval => RequestStatus.awaitingApproval,
        searching => RequestStatus.searching,
        downloading => RequestStatus.downloading,
        importing => RequestStatus.importing,
        available => RequestStatus.available,
        failed => RequestStatus.failed,
      };

  /// Admins may approve or decline only this.
  bool get decidable => this == awaitingApproval;
}

class PairResult {
  const PairResult({required this.token, required this.deviceId, required this.user, required this.role});

  final String token;
  final String deviceId;
  final String user;
  final MediaRole role;

  static final _tokenChars = RegExp(r'^[A-Za-z0-9_\-]{20,128}$');

  static PairResult fromJson(Object? j) {
    final m = asMap(j, 'pair');
    final token = m['token'];
    if (token is! String || !_tokenChars.hasMatch(token)) throw const ModelError('bad token');
    final role = MediaRole.parse(m['role']);
    if (role == null) throw const ModelError('unknown role');
    return PairResult(
      token: token,
      deviceId: _text(m['deviceId'], 'deviceId', max: 64),
      user: _text(m['user'], 'user', max: 100),
      role: role,
    );
  }
}

class Me {
  const Me({required this.user, required this.role});

  final String user;
  final MediaRole role;

  static Me fromJson(Object? j) {
    final m = asMap(j, 'me');
    final role = MediaRole.parse(m['role']);
    if (role == null) throw const ModelError('unknown role');
    return Me(user: _text(m['user'], 'user', max: 100), role: role);
  }
}

bool _validType(Object? t) => t == 'movie' || t == 'tv';

class SearchItem {
  const SearchItem({
    required this.tmdbId,
    required this.type,
    required this.title,
    this.year,
    this.overview,
    required this.status,
  });

  final int tmdbId;

  /// `movie` or `tv`.
  final String type;
  final String title;
  final int? year;
  final String? overview;
  final MediaStatus status;

  /// A copy with another [status] (after a request).
  SearchItem withStatus(MediaStatus s) =>
      SearchItem(tmdbId: tmdbId, type: type, title: title, year: year, overview: overview, status: s);

  static SearchItem fromJson(Object? j) {
    final m = asMap(j, 'result');
    final type = m['type'];
    if (!_validType(type)) throw const ModelError('unknown media type');
    return SearchItem(
      tmdbId: _int(m['tmdbId'], 'tmdbId'),
      type: type as String,
      title: _text(m['title'], 'title', max: 300),
      year: _optInt(m['year'], 'year'),
      overview: _optText(m['overview'], 'overview'),
      status: MediaStatus.parse(m['mediaStatus']),
    );
  }

  static List<SearchItem> listFrom(Object? j) {
    final m = asMap(j, 'search');
    return [for (final e in asList(m['results'], 'results', max: 100)) fromJson(e)];
  }
}

class RequestItem {
  const RequestItem({
    required this.id,
    this.tmdbId,
    this.type,
    this.title,
    required this.status,
    this.createdAt,
    this.requestedBy,
  });

  final int id;
  final int? tmdbId;
  final String? type;
  final String? title;
  final MediaStatus status;
  final String? createdAt;

  /// Admins only.
  final String? requestedBy;

  String get displayTitle => title ?? 'Unknown title';

  RequestItem withStatus(MediaStatus s) => RequestItem(
        id: id,
        tmdbId: tmdbId,
        type: type,
        title: title,
        status: s,
        createdAt: createdAt,
        requestedBy: requestedBy,
      );

  static RequestItem fromJson(Object? j) {
    final m = asMap(j, 'request');
    final type = m['type'];
    return RequestItem(
      id: _int(m['id'], 'id'),
      tmdbId: _optInt(m['tmdbId'], 'tmdbId'),
      type: _validType(type) ? type as String : null,
      title: _optText(m['title'], 'title', max: 300),
      status: MediaStatus.parse(m['status']),
      createdAt: _optText(m['createdAt'], 'createdAt', max: 40),
      requestedBy: _optText(m['requestedBy'], 'requestedBy', max: 100),
    );
  }
}

class Paged<T> {
  const Paged(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;
}

String? _cursor(Object? v) {
  if (v == null) return null;
  if (v is! String || !RegExp(r'^[0-9]{1,8}$').hasMatch(v)) throw const ModelError('bad cursor');
  return v;
}

Paged<RequestItem> requestPageFrom(Object? j) {
  final m = asMap(j, 'requests');
  return Paged([for (final e in asList(m['requests'], 'requests')) RequestItem.fromJson(e)], _cursor(m['nextCursor']));
}

/// Most downloads kept from one answer.
const maxDownloadsShown = 200;

class DownloadItem {
  const DownloadItem({required this.type, required this.title, required this.status, this.progress, this.timeLeft});

  final String type;
  final String title;

  /// `downloading` or `importing`.
  final MediaStatus status;

  /// 0 to 1, or null when unknown.
  final double? progress;
  final String? timeLeft;

  static DownloadItem fromJson(Object? j) {
    final m = asMap(j, 'download');
    final status = MediaStatus.parse(m['status']);
    if (status != MediaStatus.downloading && status != MediaStatus.importing) {
      throw const ModelError('unexpected download status');
    }
    final p = m['progress'];
    if (p != null && p is! num) throw const ModelError('progress is not a number');
    final title = _text(m['title'], 'title', max: 300, required: false);
    return DownloadItem(
      type: _validType(m['type']) ? m['type'] as String : 'movie',
      title: title.isEmpty ? 'Unknown title' : title,
      status: status,
      progress: p == null ? null : (p as num).toDouble().clamp(0.0, 1.0),
      timeLeft: _optText(m['timeLeft'], 'timeLeft', max: 20),
    );
  }

  static List<DownloadItem> listFrom(Object? j) {
    final m = asMap(j, 'downloads');
    // A long queue shows its first 200 entries; it is not an error.
    return [for (final e in asList(m['downloads'], 'downloads', max: 10000).take(maxDownloadsShown)) fromJson(e)];
  }
}

/// A library kind, as `?type=` names it.
enum LibraryKind {
  movies('Movies'),
  tv('TV'),
  music('Music');

  const LibraryKind(this.label);

  final String label;
}

final _imagePath = RegExp(r'^/v1/images/[0-9a-f]{32}(\?w=[0-9]{2,4})?$');

/// True for the only image paths the app fetches.
bool validImagePath(String? p) => p != null && _imagePath.hasMatch(p);

class LibraryItem {
  const LibraryItem({required this.id, required this.title, this.year, required this.type, this.poster});

  /// 32 lowercase hex.
  final String id;
  final String title;
  final int? year;

  /// Jellyfin's type: `Movie`, `Series`, `MusicAlbum`...
  final String type;

  /// A gateway path (`/v1/images/<id>?w=342`); fetched with the token header.
  final String? poster;

  /// The gateway streams movies (and episodes, videos, audio) only; it has no
  /// endpoint to list a series' episodes yet.
  bool get playable => type == 'Movie';

  static LibraryItem fromJson(Object? j) {
    final m = asMap(j, 'item');
    final id = m['id'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) throw const ModelError('bad item id');
    final poster = m['poster'];
    if (poster != null && !validImagePath(poster is String ? poster : null)) {
      throw const ModelError('bad poster path');
    }
    return LibraryItem(
      id: id,
      title: _text(m['title'], 'title', max: 300),
      year: _optInt(m['year'], 'year'),
      type: _text(m['type'], 'type', max: 40),
      poster: poster as String?,
    );
  }
}

Paged<LibraryItem> libraryPageFrom(Object? j) {
  final m = asMap(j, 'library');
  return Paged([for (final e in asList(m['items'], 'items')) LibraryItem.fromJson(e)], _cursor(m['nextCursor']));
}

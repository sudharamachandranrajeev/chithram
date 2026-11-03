final _code = RegExp(r'^[0-9]{6}$');
final _hexId = RegExp(r'^[0-9a-f]{32}$');
final _ctl = RegExp(r'[\u0000-\u001f\u007f]');

const maxBodyBytes = 4096;

bool validCode(Object? v) => v is String && _code.hasMatch(v);

/// Jellyfin item ids as the gateway accepts them: 32 lowercase hex (dashes stripped).
String? normalizeItemId(String? v) {
  if (v == null) return null;
  final s = v.replaceAll('-', '').toLowerCase();
  return _hexId.hasMatch(s) ? s : null;
}

/// Device name: 1..64 chars, no control characters.
String? validDeviceName(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  if (s.isEmpty || s.length > 64 || _ctl.hasMatch(s)) return null;
  return s;
}

/// TMDB id: positive int <= 10^9.
int? validTmdbId(Object? v) {
  if (v is! int) return null;
  return (v > 0 && v <= 1000000000) ? v : null;
}

String? validMediaType(Object? v) =>
    (v == 'movie' || v == 'tv') ? v as String : null;

/// Search text: 1..100 chars after trimming, no control characters.
String? validQuery(String? v) {
  if (v == null) return null;
  final s = v.trim();
  if (s.isEmpty || s.length > 100 || _ctl.hasMatch(s)) return null;
  return s;
}

/// Positive decimal id (Seerr request id), <= 10^9.
int? validNumericId(String? v) {
  if (v == null || v.length > 10 || !RegExp(r'^[0-9]+$').hasMatch(v))
    return null;
  final n = int.parse(v);
  return (n > 0 && n <= 1000000000) ? n : null;
}

/// Library type -> Jellyfin item type.
String? libraryItemType(String? v) => switch (v) {
  'movies' => 'Movie',
  'tv' => 'Series',
  'music' => 'MusicAlbum',
  _ => null,
};

/// Opaque cursor = non-negative offset as decimal text (<= 10^7).
int? validCursor(String? v) {
  if (v == null || v.isEmpty) return 0;
  if (v.length > 8 || !RegExp(r'^[0-9]+$').hasMatch(v)) return null;
  return int.parse(v);
}

/// Image width: clamp to 64..1280, default 342.
int? validWidth(String? v) {
  if (v == null || v.isEmpty) return 342;
  if (v.length > 5 || !RegExp(r'^[0-9]+$').hasMatch(v)) return null;
  final n = int.parse(v);
  if (n < 64 || n > 1280) return null;
  return n;
}

/// Turns arbitrary route paths into a template safe to log (ids replaced).
String routeTemplate(String path) {
  final parts = path.split('/').map((s) {
    if (s.isEmpty) return s;
    if (RegExp(r'^[0-9]+$').hasMatch(s)) return ':id';
    if (RegExp(r'^[0-9a-fA-F-]{32,36}$').hasMatch(s)) return ':id';
    return s.length > 24 ? ':x' : s;
  });
  final t = parts.join('/');
  return t.length > 80 ? t.substring(0, 80) : t;
}

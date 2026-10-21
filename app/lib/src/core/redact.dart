/// Reduces URLs to their host before they reach a log. Tokens, passwords and
/// query strings are never logged.
String redactUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return '<invalid url>';
  if (uri.host.isEmpty) return '${uri.scheme}:';
  return '${uri.scheme}://${uri.host}';
}

final _urlInText = RegExp(r'''[a-zA-Z][a-zA-Z0-9+.-]*:(//)?[^\s<>"']+''');

/// Replaces every URL-like token in [text] with its host (magnet links with
/// `magnet:`).
String redactText(String text) => text.replaceAllMapped(_urlInText, (m) {
      final s = m[0]!;
      if (s.toLowerCase().startsWith('magnet:')) return 'magnet:';
      return redactUrl(s);
    });

/// A URL for showing to the user: credentials masked, host kept.
String maskUrlCredentials(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.userInfo.isEmpty) return url;
  return uri.replace(userInfo: '***').toString();
}

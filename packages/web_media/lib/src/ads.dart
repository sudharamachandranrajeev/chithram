/// Ad detection by the shape of a URL. Chithram never renders a page or runs
/// its scripts, so banners, pop-ups and script-driven pre-rolls never load;
/// this catches what is left: media files and frames that are ads themselves.
library;

final _adHostLabel = RegExp(
  r'^(ads?|adserv\w*|adsystem|adtech|adnxs|advert\w*|banners?|popunders?|popads?|'
  r'tracking|tracker|analytics|pixel|imasdk|adclick\w*|clickunder)$',
);

final _adPathSegment = RegExp(
  r'^(ads?|adverts?|advertis\w*|adserv\w*|preroll|midroll|postroll|pre-roll|mid-roll|post-roll|'
  r'vast|vmap|vpaid|banners?|popunders?|sponsor\w*|commercials?)$',
);

final _adFileName = RegExp(r'(^|[_.\-])(vast|vmap|vpaid|preroll|midroll|postroll|advert\w*|adbreak)([_.\-]|$)');

/// True when [url] looks like an ad, an ad server or an ad tracker: a host
/// label such as `ads` or `adserver`, a path segment such as `/vast/` or
/// `/preroll/`, or a file named like `preroll_15s.mp4`.
bool isAdUrl(Uri url) {
  for (final label in url.host.toLowerCase().split('.')) {
    if (_adHostLabel.hasMatch(label)) return true;
  }
  final segments = url.pathSegments.map((s) => s.toLowerCase()).toList();
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    if (i < segments.length - 1 ? _adPathSegment.hasMatch(s) : _adFileName.hasMatch(s) || _adPathSegment.hasMatch(s)) {
      return true;
    }
  }
  return false;
}

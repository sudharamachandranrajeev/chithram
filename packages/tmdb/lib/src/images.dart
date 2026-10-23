/// TMDB image URLs. The API returns size-free paths (`/abc.jpg`); the width is
/// picked here, as the smallest TMDB bucket at least as wide as the pixels
/// the widget will actually show.
library;

const _base = 'https://image.tmdb.org/t/p/';

const tmdbPosterWidths = [92, 154, 185, 342, 500, 780];
const tmdbBackdropWidths = [300, 780, 1280];
const tmdbProfileWidths = [45, 185];
const tmdbStillWidths = [92, 185, 300];

/// `/<name>.<ext>` only: nothing that could change the host or path.
final _safePath = RegExp(r'^/[A-Za-z0-9_\-]+\.(jpg|jpeg|png|webp)$');

bool isTmdbImagePath(String path) => _safePath.hasMatch(path);

/// The bucket for [pxWidth] out of [widths] (ascending): the smallest that is
/// at least [pxWidth], else `original`.
String tmdbBucket(List<int> widths, int pxWidth) {
  for (final w in widths) {
    if (w >= pxWidth) return 'w$w';
  }
  return 'original';
}

String _url(List<int> widths, String path, int pxWidth) {
  if (!isTmdbImagePath(path)) {
    throw ArgumentError.value(path, 'path', 'not a TMDB image path');
  }
  return '$_base${tmdbBucket(widths, pxWidth)}$path';
}

String tmdbPoster(String path, int pxWidth) => _url(tmdbPosterWidths, path, pxWidth);

String tmdbBackdrop(String path, int pxWidth) => _url(tmdbBackdropWidths, path, pxWidth);

String tmdbProfile(String path, int pxWidth) => _url(tmdbProfileWidths, path, pxWidth);

String tmdbStill(String path, int pxWidth) => _url(tmdbStillWidths, path, pxWidth);

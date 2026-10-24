/// Plays video from web pages without their ads: finds the media on a page
/// (and in the frames it embeds) from the HTML alone, never running the
/// page, and serves HLS playlists with their ad breaks removed. Pure Dart.
library;

export 'src/ads.dart' show isAdUrl;
export 'src/hls.dart' show rewritePlaylist;
export 'src/hls_proxy.dart' show HlsAdProxy;
export 'src/resolver.dart' show FetchedPage, PageFetch, WebMediaResolver, fetchPage, isLocalHost;
export 'src/scan.dart';

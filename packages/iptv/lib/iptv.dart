/// IPTV playlist (M3U, Xtream), XMLTV EPG, catalogue, health and sports logic.
///
/// Pure Dart: no Flutter dependency, so everything runs under `dart test` and
/// the byte-stream parsers can run inside an isolate.
library;

export 'src/catalogue.dart';
export 'src/http.dart';
export 'src/health.dart';
export 'src/m3u.dart';
export 'src/sources.dart';
export 'src/sports.dart';
export 'src/store.dart';
export 'src/xmltv.dart';
export 'src/xtream.dart';
export 'src/zap.dart';

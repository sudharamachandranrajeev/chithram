import 'dart:convert';

import 'errors.dart';
import 'models.dart';
import 'net.dart';
import 'util.dart';

/// One InnerTube player client.
class PlayerClient {
  const PlayerClient({
    required this.tier,
    required this.nameId,
    required this.version,
    required this.userAgent,
    required this.context,
    this.origin = 'https://www.youtube.com',
  });

  final Tier tier;

  /// Numeric id for `X-YouTube-Client-Name`.
  final int nameId;
  final String version;
  final String userAgent;

  /// The `context.client` map (visitor data is added on send).
  final Map<String, Object?> context;
  final String origin;
}

const visionAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

/// YouTube's Vision Pro app: as of Oct 2026 the one client that returns direct
/// links without a PO token or a JS challenge (yt-dlp defaults to it too).
/// Needs visitor data; without it the answer is LOGIN_REQUIRED.
const visionosClient = PlayerClient(
  tier: Tier.visionos,
  nameId: 101,
  version: '1.02',
  userAgent: visionAgent,
  context: {
    'clientName': 'VISIONOS',
    'clientVersion': '1.02',
    'deviceMake': 'Apple',
    'deviceModel': 'RealityDevice17,1',
    'userAgent': visionAgent,
    'osName': 'visionOS',
    'osVersion': '26.5.23O471',
    'hl': 'en',
    'timeZone': 'UTC',
    'utcOffsetMinutes': 0,
  },
);

const _vrAgent =
    'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';

const androidVrClient = PlayerClient(
  tier: Tier.androidVr,
  nameId: 28,
  version: '1.56.21',
  userAgent: _vrAgent,
  context: {
    'clientName': 'ANDROID_VR',
    'clientVersion': '1.56.21',
    'deviceMake': 'Oculus',
    'deviceModel': 'Quest 3',
    'androidSdkVersion': 32,
    'userAgent': _vrAgent,
    'osName': 'Android',
    'osVersion': '12L',
    'hl': 'en',
    'timeZone': 'UTC',
    'utcOffsetMinutes': 0,
  },
);

const _tvAgent = 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version';

const tvClient = PlayerClient(
  tier: Tier.tv,
  nameId: 7,
  version: '7.20250312.16.00',
  userAgent: _tvAgent,
  context: {
    'clientName': 'TVHTML5',
    'clientVersion': '7.20250312.16.00',
    'userAgent': _tvAgent,
    'hl': 'en',
    'timeZone': 'UTC',
    'utcOffsetMinutes': 0,
  },
);

final playerApi = Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false');
final swJsData = Uri.parse('https://www.youtube.com/sw.js_data');

/// YouTube's id for this visitor, cached; [get] with `fresh: true` refetches
/// (after a LOGIN_REQUIRED bot check).
class VisitorData {
  VisitorData(this._net);
  final Net _net;
  String? _cached;

  Future<String> get({bool fresh = false}) async {
    final known = _cached;
    if (!fresh && known != null) return known;
    var text = await _net.getText(swJsData, headers: {'User-Agent': visionAgent}, timeout: const Duration(seconds: 8));
    if (text.startsWith(")]}'")) text = text.substring(4);
    Object? node = jsonDecode(text);
    for (final i in const [0, 2, 0, 0, 13]) {
      final list = asList(node);
      node = list.length > i ? list[i] : null;
    }
    final id = asString(node);
    if (id.isEmpty) throw InnertubeException("couldn't start a YouTube session (no visitor data)");
    return _cached = id;
  }
}

/// A video's raw player response from [client].
Future<Json> fetchPlayer(Net net, PlayerClient client, String videoId, String visitor,
    {Duration timeout = const Duration(seconds: 8)}) async {
  final response = await net.postJson(
    playerApi,
    {
      'context': {
        'client': {...client.context, 'visitorData': visitor},
      },
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
    },
    headers: {
      'User-Agent': client.userAgent,
      'X-YouTube-Client-Name': '${client.nameId}',
      'X-YouTube-Client-Version': client.version,
      'X-Goog-Visitor-Id': visitor,
      'Origin': client.origin,
    },
    timeout: timeout,
  );
  return asJson(response);
}

import '../core/prefs.dart';

/// Prefs key of the feature flag. Off (the default) means the Media section
/// does not exist: no navigation item, no page, no network.
const mediaEnabledPref = 'media.enabled';

/// Prefs keys of the non-secret pairing data. The device token is NOT here:
/// it lives in secure storage only (see token_store.dart).
const mediaHostPref = 'media.host';
const mediaPortPref = 'media.port';
const mediaFingerprintPref = 'media.fingerprint';

/// The gateway's default HTTPS port.
const defaultGatewayPort = 8443;

/// A gateway address that passed [parseGatewayHost].
class GatewayHost {
  const GatewayHost(this.host, this.port);

  final String host;
  final int port;

  @override
  String toString() => host.contains(':') ? '[$host]:$port' : '$host:$port';

  @override
  bool operator ==(Object other) => other is GatewayHost && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

final _hostName = RegExp(r'^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$');
final _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
final _ipv6 = RegExp(r'^[0-9A-Fa-f:.]{2,45}$');

/// Validates what the user typed as the gateway address: `host`, `host:port`
/// or `[v6]:port`. Anything else (a scheme, a path, a query, credentials,
/// spaces) is rejected, so a plain `http://` address can never be stored.
/// Returns null when invalid.
GatewayHost? parseGatewayHost(String input) {
  final s = input.trim();
  if (s.isEmpty || s.length > 260) return null;
  String host;
  String? portText;
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end < 0) return null;
    host = s.substring(1, end);
    final rest = s.substring(end + 1);
    if (rest.isNotEmpty) {
      if (!rest.startsWith(':')) return null;
      portText = rest.substring(1);
    }
    if (!host.contains(':') || !_ipv6.hasMatch(host)) return null;
    try {
      Uri.parseIPv6Address(host);
    } on FormatException {
      return null;
    }
  } else {
    final colon = s.indexOf(':');
    if (colon >= 0) {
      if (s.indexOf(':', colon + 1) >= 0) return null; // bare IPv6 needs brackets
      host = s.substring(0, colon);
      portText = s.substring(colon + 1);
    } else {
      host = s;
    }
    final v4 = _ipv4.firstMatch(host);
    if (v4 != null) {
      for (var i = 1; i <= 4; i++) {
        if (int.parse(v4.group(i)!) > 255) return null;
      }
    } else if (!_hostName.hasMatch(host)) {
      return null;
    }
  }
  var port = defaultGatewayPort;
  if (portText != null) {
    if (!RegExp(r'^[0-9]{1,5}$').hasMatch(portText)) return null;
    port = int.parse(portText);
    if (port < 1 || port > 65535) return null;
  }
  return GatewayHost(host.toLowerCase(), port);
}

/// Normalises a SHA-256 fingerprint typed or scanned in any common form
/// (`AA:BB:..`, lower case, spaces, no separators) to the gateway's
/// `AA:BB:...` upper-case form. Null unless it is exactly 32 bytes of hex.
String? normalizeFingerprint(String input) {
  final hex = input.replaceAll(RegExp(r'[\s:\-]'), '');
  if (!RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(hex)) return null;
  final up = hex.toUpperCase();
  return [for (var i = 0; i < 64; i += 2) up.substring(i, i + 2)].join(':');
}

/// The 32 bytes of a normalised fingerprint.
List<int> fingerprintBytes(String normalized) =>
    [for (final p in normalized.split(':')) int.parse(p, radix: 16)];

/// The non-secret media settings, kept in [Prefs].
class MediaConfig {
  const MediaConfig({required this.enabled, this.host, this.fingerprint});

  final bool enabled;
  final GatewayHost? host;
  final String? fingerprint;

  /// Both halves of the pin are known.
  bool get configured => host != null && fingerprint != null;

  static MediaConfig read(Prefs prefs) {
    final h = prefs.getString(mediaHostPref);
    // The host is stored bare; an IPv6 literal needs its brackets back to parse.
    final host = h == null
        ? null
        : parseGatewayHost('${h.contains(':') ? '[$h]' : h}:${prefs.getInt(mediaPortPref) ?? defaultGatewayPort}');
    final fp = prefs.getString(mediaFingerprintPref);
    return MediaConfig(
      enabled: prefs.getBool(mediaEnabledPref),
      host: host,
      fingerprint: fp == null ? null : normalizeFingerprint(fp),
    );
  }

  static Future<void> save(Prefs prefs, {required GatewayHost host, required String fingerprint}) async {
    await prefs.set(mediaHostPref, host.host);
    await prefs.set(mediaPortPref, host.port);
    await prefs.set(mediaFingerprintPref, fingerprint);
  }

  static Future<void> clear(Prefs prefs) async {
    await prefs.set(mediaHostPref, null);
    await prefs.set(mediaPortPref, null);
    await prefs.set(mediaFingerprintPref, null);
  }
}

/// True when the Media section is switched on.
bool mediaEnabled(Prefs prefs) => prefs.getBool(mediaEnabledPref);

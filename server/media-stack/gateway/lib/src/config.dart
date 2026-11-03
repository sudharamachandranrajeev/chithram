import 'dart:io';

class Config {
  Config({
    required this.jellyfinUrl,
    required this.seerrUrl,
    required this.radarrUrl,
    required this.sonarrUrl,
    required this.secretsDir,
    required this.stateDir,
    required this.port,
  });

  final String jellyfinUrl;
  final String seerrUrl;
  final String radarrUrl;
  final String sonarrUrl;
  final String secretsDir;
  final String stateDir;
  final int port;

  factory Config.fromEnv([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    return Config(
      jellyfinUrl: e['JELLYFIN_URL'] ?? 'http://jellyfin:8096',
      seerrUrl: e['SEERR_URL'] ?? 'http://seerr:5055',
      radarrUrl: e['RADARR_URL'] ?? 'http://radarr:7878',
      sonarrUrl: e['SONARR_URL'] ?? 'http://sonarr:8989',
      secretsDir: e['SECRETS_DIR'] ?? '/run/secrets',
      stateDir: e['STATE_DIR'] ?? '/state',
      port: int.tryParse(e['GATEWAY_LISTEN_PORT'] ?? '') ?? 8443,
    );
  }

  /// Reads a secret file fresh each call (picks up rotated keys without a restart where the
  /// bind mount allows it). Never logged.
  String secret(String name) =>
      File('$secretsDir/$name').readAsStringSync().trim();

  String get tlsCertPath => '$secretsDir/gateway_tls_cert';
  String get tlsKeyPath => '$secretsDir/gateway_tls_key';
}

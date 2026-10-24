import 'package:nova_host/nova_host.dart';

/// Why a plugin shows the status it shows (see [classifyHealth]).
enum PluginHealthStatus {
  /// Never run.
  untested,
  healthy,
  degraded,
  failing,

  /// `url-changed`, a changed file, or a changed repo key: needs the user.
  blocked,

  /// No runtime on this device (missing, armeabi-v7a, no Landlock).
  unavailable;

  String get label => switch (this) {
        untested => 'Not tested yet',
        healthy => 'Healthy',
        degraded => 'Degraded',
        failing => 'Failing',
        blocked => 'Blocked',
        unavailable => 'Unavailable',
      };
}

/// An update waiting for the user's approval, with what differs from the
/// installed version.
class PendingUpdate {
  const PendingUpdate({required this.version, required this.sha256, required this.differences});

  final String version;
  final String sha256;

  /// Human-readable lines, e.g. `Site changes from a.example to b.example`.
  final List<String> differences;
}

class PluginHealth {
  const PluginHealth({
    required this.status,
    this.successRate,
    this.medianMs,
    this.lastError,
    this.blockedHosts = const [],
    this.runs = 0,
  });

  static const untested = PluginHealth(status: PluginHealthStatus.untested);

  final PluginHealthStatus status;

  /// Share of the kept runs that finished ok (0 to 1); null before any run.
  final double? successRate;
  final int? medianMs;
  final String? lastError;

  /// Hosts the plugin tried that the broker refused.
  final List<String> blockedHosts;
  final int runs;
}

/// A plugin as the app and Torrent Home see it.
class InstalledPlugin {
  const InstalledPlugin({
    required this.id,
    required this.engineId,
    required this.name,
    required this.sha256,
    required this.sourceUrl,
    required this.declaredUrl,
    required this.allowedHosts,
    required this.signed,
    required this.enabled,
    required this.installedAt,
    required this.updatedAt,
    this.repoId,
    this.version,
    this.categories = const [],
    this.autoUpdatedAt,
    this.pending,
    this.canUndo = false,
    this.health = PluginHealth.untested,
  });

  /// `<repoId|single>:<engineId>`; also the provider id used for health.
  final String id;

  /// The nova3 module/class name; `PluginHit.engineId` carries this.
  final String engineId;
  final String name;
  final String? repoId, version;
  final String sha256, sourceUrl, declaredUrl;

  /// What the user approved at install: the registrable domain of [declaredUrl]
  /// plus manifest or header hosts. The broker allows exactly these.
  final List<String> allowedHosts;
  final bool signed, enabled;
  final DateTime installedAt, updatedAt;

  /// nova3 `supported_categories` keys (`all`, `movies`, `tv`, ...), from `describe`.
  final List<String> categories;

  /// When a signed repo's update was applied without asking; null if never.
  final DateTime? autoUpdatedAt;
  final PendingUpdate? pending;

  /// The previous file is still kept, so "Undo update" works once.
  final bool canUndo;
  final PluginHealth health;

  bool supportsCategory(String cat) => categories.contains(cat);

  /// The category to pass for [wanted] (`movies`, `tv`): [wanted] when the
  /// plugin lists it, otherwise `all`.
  String categoryFor(String wanted) => supportsCategory(wanted) ? wanted : 'all';

  InstalledPlugin copyWith({PluginHealth? health, bool? enabled}) => InstalledPlugin(
        id: id,
        engineId: engineId,
        name: name,
        sha256: sha256,
        sourceUrl: sourceUrl,
        declaredUrl: declaredUrl,
        allowedHosts: allowedHosts,
        signed: signed,
        enabled: enabled ?? this.enabled,
        installedAt: installedAt,
        updatedAt: updatedAt,
        repoId: repoId,
        version: version,
        categories: categories,
        autoUpdatedAt: autoUpdatedAt,
        pending: pending,
        canUndo: canUndo,
        health: health ?? this.health,
      );
}

/// One search through one plugin, as Torrent Home and Find consume it.
class PluginSearch {
  const PluginSearch({
    required this.plugin,
    required this.status,
    required this.hits,
    required this.elapsed,
    this.reason,
    this.blockedHosts = const [],
  });

  final InstalledPlugin plugin;
  final SearchStatus status;
  final List<PluginHit> hits;
  final Duration elapsed;
  final String? reason;
  final List<String> blockedHosts;

  bool get ok => status == SearchStatus.ok;
}

enum InstallErrorKind {
  /// Could not fetch a file (offline, HTTP error, too many redirects, not HTTPS).
  fetch,
  tooLarge,
  malformed,
  badSignature,
  keyChanged,
  hashMismatch,
  adult,
  privateOrIp,
  describeFailed,
  unavailable,
}

class PluginInstallError implements Exception {
  PluginInstallError(this.kind, this.message);
  final InstallErrorKind kind;
  final String message;
  @override
  String toString() => 'PluginInstallError(${kind.name}): $message';
}

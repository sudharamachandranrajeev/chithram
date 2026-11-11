// A newer Chithram, found and installed from inside the app. It reads the
// releases this project already publishes on GitHub (a tag runs the Release
// workflow, which uploads the installers with a SHA256SUMS.txt beside them),
// so there is nothing extra to publish.
//
// What is downloaded is checked against that SHA-256 before it runs:
// installing a program is the one thing here worth being careful about, so a
// release that cannot be checked is not installed at all.
//
// Ported from Paattu's update.dart (same release layout).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The list, not /releases/latest: that one passes over pre-releases, and
/// every 0.x release is published as one.
const releaseApiUrl = 'https://api.github.com/repos/sudharamachandranrajeev/chithram-video-app/releases?per_page=20';
const releasePageUrl = 'https://github.com/sudharamachandranrajeev/chithram-video-app/releases';

/// The file the releases publish their checksums in.
const checksumsName = 'SHA256SUMS.txt';

/// One file of a release.
class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, {this.size = 0, this.digest = ''});

  final String name;
  final Uri url;
  final int size;

  /// GitHub's own checksum for it ("sha256:07412d…"), when it gave one.
  final String digest;

  /// The checksum without its "sha256:" in front, or empty.
  String get sha256 => digest.startsWith('sha256:') ? digest.substring(7) : '';
}

/// A published release, as far as this device cares.
class Release {
  const Release({required this.version, required this.assets, this.notes = '', this.page = ''});

  factory Release.fromJson(Map<String, dynamic> json) => Release(
        version: '${json['tag_name'] ?? ''}'.replaceFirst(RegExp(r'^[vV]'), ''),
        notes: '${json['body'] ?? ''}',
        page: '${json['html_url'] ?? ''}',
        assets: {
          for (final raw in (json['assets'] is List ? json['assets'] as List : const []))
            if (raw is Map<String, dynamic>)
              '${raw['name']}': ReleaseAsset(
                '${raw['name']}',
                Uri.parse('${raw['browser_download_url']}'),
                size: raw['size'] is int ? raw['size'] as int : 0,
                digest: '${raw['digest'] ?? ''}',
              ),
        },
      );

  final String version;
  final String notes;
  final String page;
  final Map<String, ReleaseAsset> assets;

  /// The file to install on [os], if the release has one.
  ReleaseAsset? installerFor(String os) {
    final suffix = installerSuffix(os);
    if (suffix == null) return null;
    for (final asset in assets.values) {
      if (asset.name.endsWith(suffix)) return asset;
    }
    return null;
  }

  /// The checksums file, when the release published one.
  ReleaseAsset? get checksums => assets[checksumsName];
}

/// What the installer for [os] is called. Null where the app cannot install
/// itself (Android needs the system installer and an APK per ABI: the
/// releases page is offered there instead).
String? installerSuffix(String os) => switch (os) {
      'windows' => '-windows-x64-setup.exe',
      'linux' => '-linux-x86_64.AppImage',
      _ => null,
    };

/// The numbers of a version, "v0.7.10" to [0, 7, 10]. A part that is not a
/// number counts as 0; anything after a '-' or '+' is dropped.
List<int> versionParts(String version) {
  final plain = version.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp('[-+]')).first;
  return [for (final part in plain.split('.')) int.tryParse(part.trim()) ?? 0];
}

/// Whether [candidate] is newer than [current], part by part (0.10.0 beats 0.9.9).
bool isNewerVersion(String candidate, String current) {
  final a = versionParts(candidate), b = versionParts(current);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The newest version in GitHub's list of releases (pre-releases count;
/// drafts do not), or null when there is none.
Release? newestRelease(Object? list) {
  Release? best;
  for (final item in list is List ? list : const []) {
    if (item is! Map<String, dynamic> || item['draft'] == true) continue;
    final release = Release.fromJson(item);
    if (release.version.isEmpty) continue;
    if (best == null || isNewerVersion(release.version, best.version)) best = release;
  }
  return best;
}

/// A SHA256SUMS.txt as a map: "07412d…  Chithram-0.4.1-windows-x64-setup.exe"
/// per line, with one or two spaces before the name and an optional "*".
Map<String, String> parseChecksums(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+\*?'));
    if (parts.length < 2) continue;
    final sum = parts.first;
    final name = parts.last;
    if (sum.length != 64 || name.isEmpty) continue;
    out[name] = sum.toLowerCase();
  }
  return out;
}

/// Where the updater has got to.
enum UpdateState { idle, checking, upToDate, available, downloading, installing, ready, failed }

/// GET [url]: the status and the body. Tests pass a fake.
typedef UpdateFetch = Future<(int, List<int>)> Function(Uri url);

/// Streams [url] into [sink], reporting (received, total) bytes; returns the
/// status. Tests pass a fake.
typedef UpdateDownload = Future<int> Function(Uri url, IOSink sink, void Function(int got, int total) progress);

/// Runs the downloaded installer (Windows: the setup, then the app closes).
typedef UpdateInstall = Future<void> Function(File file, String os);

class UpdateManager extends ChangeNotifier {
  UpdateManager({
    required this.currentVersion,
    required this.dir,
    String? os,
    UpdateFetch? fetch,
    UpdateDownload? download,
    UpdateInstall? install,
  })  : os = os ?? Platform.operatingSystem,
        _fetch = fetch ?? _httpGet,
        _download = download ?? _httpDownload,
        _install = install ?? installFile;

  /// This build's version (from the platform); resolved before a check.
  final Future<String> Function() currentVersion;

  /// Where the download goes (one at a time).
  final Directory dir;

  /// The OS to pick an installer for.
  final String os;

  final UpdateFetch _fetch;
  final UpdateDownload _download;
  final UpdateInstall _install;

  UpdateState state = UpdateState.idle;

  /// The version this build is, once a check has read it.
  String version = '';

  /// The newer release found, when there is one.
  Release? available;

  /// What went wrong, or what to do next, in plain words.
  String message = '';

  /// How much of the download has arrived, 0 to 1.
  double progress = 0;

  /// Whether this device can install the update itself (else: the releases page).
  bool get canInstall => installerSuffix(os) != null;

  bool get busy =>
      state == UpdateState.checking || state == UpdateState.downloading || state == UpdateState.installing;

  void _emit(UpdateState s, {String message = ''}) {
    state = s;
    this.message = message;
    notifyListeners();
  }

  /// Look for a newer version. [quiet] (the start-up check) does not report a
  /// failure: no network at start is normal.
  Future<void> check({bool quiet = false}) async {
    if (busy) return;
    _emit(UpdateState.checking);
    try {
      version = await currentVersion();
      final (status, body) = await _fetch(Uri.parse(releaseApiUrl)).timeout(const Duration(seconds: 20));
      if (status != 200) throw HttpException('GitHub answered $status');
      final release = newestRelease(jsonDecode(utf8.decode(body)));
      if (release == null || version.isEmpty || !isNewerVersion(release.version, version)) {
        available = null;
        _emit(UpdateState.upToDate);
        return;
      }
      available = release;
      if (canInstall && release.installerFor(os) == null) {
        _emit(UpdateState.failed, message: 'Version ${release.version} has no installer for this device yet.');
        return;
      }
      _emit(UpdateState.available);
    } catch (e) {
      debugPrint('update: check failed: $e');
      if (quiet) {
        _emit(UpdateState.idle);
      } else {
        _emit(UpdateState.failed, message: "Couldn't reach GitHub. Check the connection and try again.");
      }
    }
  }

  /// Download the new version, check its SHA-256, and run its installer.
  Future<bool> downloadAndInstall() async {
    final release = available;
    final asset = release?.installerFor(os);
    if (release == null || asset == null || busy) return false;
    progress = 0;
    _emit(UpdateState.downloading);
    try {
      await dir.create(recursive: true);
      // The folder holds one download at most.
      await for (final old in dir.list()) {
        await old.delete(recursive: true).then((_) {}, onError: (Object _) {});
      }
      final target = File('${dir.path}${Platform.pathSeparator}${asset.name}');
      await _fetchTo(asset, target);
      await _verify(asset, release, target);
      _emit(UpdateState.installing);
      await _install(target, os);
      // Windows exits inside the install; Linux replaced the AppImage.
      _emit(UpdateState.ready, message: 'Open Chithram again to use version ${release.version}.');
      return true;
    } catch (e) {
      debugPrint('update: ${asset.name}: $e');
      _emit(UpdateState.failed, message: e is UpdateException ? e.message : 'The update failed: $e');
      return false;
    }
  }

  Future<void> _fetchTo(ReleaseAsset asset, File target) async {
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    var got = 0;
    try {
      final status = await _download(asset.url, sink, (received, total) {
        got = received;
        final all = total > 0 ? total : asset.size;
        if (all <= 0) return;
        final now = (received / all).clamp(0.0, 1.0);
        if (now - progress > 0.01 || now >= 1) {
          progress = now;
          notifyListeners();
        }
      });
      await sink.close();
      if (status != 200) throw UpdateException('The download answered $status.');
      if (got == 0) throw const UpdateException('The download sent nothing.');
      await part.rename(target.path);
    } catch (e) {
      await sink.close().catchError((Object _) {});
      await part.delete().then((_) {}, onError: (Object _) {});
      rethrow;
    }
  }

  /// Checks [file] against the release's SHA256SUMS.txt (or GitHub's own
  /// digest). No checksum anywhere means no install.
  Future<void> _verify(ReleaseAsset asset, Release release, File file) async {
    var expected = asset.sha256;
    final sums = release.checksums;
    if (sums != null) {
      try {
        final (status, body) = await _fetch(sums.url).timeout(const Duration(seconds: 20));
        if (status == 200) expected = parseChecksums(utf8.decode(body))[asset.name] ?? expected;
      } catch (e) {
        debugPrint('update: reading $checksumsName: $e');
      }
    }
    if (expected.isEmpty) {
      await file.delete().then((_) {}, onError: (Object _) {});
      throw const UpdateException("The release published no checksum, so Chithram won't install it.");
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual.toLowerCase() != expected.toLowerCase()) {
      await file.delete().then((_) {}, onError: (Object _) {});
      throw const UpdateException("The download didn't match its checksum, so it was deleted.");
    }
    debugPrint('update: ${asset.name} checked ($actual)');
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _agent = 'Chithram-updater';

Future<(int, List<int>)> _httpGet(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers
      ..set(HttpHeaders.userAgentHeader, _agent)
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close();
    final body = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    return (response.statusCode, body);
  } finally {
    client.close();
  }
}

Future<int> _httpDownload(Uri url, IOSink sink, void Function(int got, int total) progress) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, _agent);
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      return response.statusCode;
    }
    var got = 0;
    await for (final bytes in response.timeout(const Duration(seconds: 60))) {
      sink.add(bytes);
      got += bytes.length;
      progress(got, response.contentLength);
    }
    return 200;
  } finally {
    client.close();
  }
}

/// Windows: starts the setup (it closes the running app itself, see
/// CloseApplications in chithram.iss, and offers to open the new one), then
/// leaves. Linux: a running AppImage is replaced where it stands.
Future<void> installFile(File file, String os) async {
  switch (os) {
    case 'windows':
      // No /CURRENTUSER: chithram.iss allows the install-mode override only
      // from its dialog, and Setup reuses the previous install's mode
      // (UsePreviousPrivileges) so an all-users install is updated in place.
      await Process.start(file.path, ['/NORESTART'], mode: ProcessStartMode.detached);
      // Give prefs and the resume store a moment to finish their writes.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    case 'linux':
      final running = Platform.environment['APPIMAGE'];
      if (running == null || running.isEmpty) {
        throw UpdateException('Not running as an AppImage: get the new version from $releasePageUrl.');
      }
      // Copied beside it first: a rename only works on the same drive.
      final next = File('$running.new');
      await file.copy(next.path);
      await Process.run('chmod', ['+x', next.path]);
      await next.rename(running);
      await file.delete().then((_) {}, onError: (Object _) {});
    default:
      throw UpdateException('Chithram cannot install its own update here: get it from $releasePageUrl.');
  }
}

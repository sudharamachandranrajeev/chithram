import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A newer Chithram, found and installed from inside the app. It reads the
/// releases the Release workflow already publishes on GitHub (the ones the
/// README and install-linux.sh point at), so nothing extra is published.
///
/// The download is checked against the release's SHA256SUMS.txt before it is
/// installed. A release without a checksum for the file is not installed.
///
/// How it installs:
///  - Android: the APK for this ABI goes to the system installer (AppChannel
///    `installApk`, through a FileProvider). Android asks the person first.
///  - Windows: the setup runs and this app quits. The
///    portable zip can't replace its own running exe, so it gets the page.
///  - Linux: a running AppImage is replaced where it stands; an install from
///    install-linux.sh gets the new tarball unpacked over it. Anything else
///    (a distro package, a build) gets the page.
/// The new version starts the next time Chithram is opened.

/// GitHub's list, not /releases/latest: every 0.x release is a pre-release,
/// and /latest skips those.
final releasesApi = Uri.parse('https://api.github.com/repos/sudharamachandranrajeev/chithram/releases?per_page=20');
const releasesPage = 'https://github.com/sudharamachandranrajeev/chithram/releases';
const checksumsName = 'SHA256SUMS.txt';

/// Prefs key: when the last automatic check ran (ISO 8601).
const updateCheckedPref = 'update.checked';

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, {this.size = 0});

  final String name;
  final Uri url;
  final int size;
}

class Release {
  const Release({required this.version, required this.assets, this.notes = ''});

  /// One entry of GitHub's releases list; null for drafts and tags that are
  /// not app versions (the "tdlib-…" binaries release).
  static Release? fromGitHub(Object? json) {
    if (json is! Map || json['draft'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String || !RegExp(r'^v\d').hasMatch(tag)) return null;
    final assets = <String, ReleaseAsset>{};
    for (final a in (json['assets'] as List?) ?? const []) {
      if (a is! Map || a['name'] is! String || a['browser_download_url'] is! String) continue;
      final name = a['name'] as String;
      assets[name] = ReleaseAsset(name, Uri.parse(a['browser_download_url'] as String), size: (a['size'] as num?)?.toInt() ?? 0);
    }
    return Release(version: tag.substring(1), notes: json['body'] as String? ?? '', assets: assets);
  }

  final String version;
  final String notes;
  final Map<String, ReleaseAsset> assets;

  ReleaseAsset? withSuffix(String suffix) {
    for (final a in assets.values) {
      if (a.name.endsWith(suffix)) return a;
    }
    return null;
  }
}

/// The newest release in GitHub's list, or null.
Release? newestRelease(Object? list) {
  Release? best;
  for (final item in list is List ? list : const []) {
    final r = Release.fromGitHub(item);
    if (r != null && (best == null || isNewerVersion(r.version, best.version))) best = r;
  }
  return best;
}

/// "0.10.0-alpha.2" → [0, 10, 0]; the pre-release part is compared apart.
List<int> versionParts(String v) =>
    [for (final p in v.trim().replaceFirst(RegExp('^[vV]'), '').split('+').first.split('-').first.split('.')) int.tryParse(p) ?? 0];

/// Part by part, so 0.10.0 beats 0.9.9; a release beats its own pre-releases
/// (0.1.0 > 0.1.0-alpha.2), and pre-releases compare by their text.
bool isNewerVersion(String candidate, String current) {
  final a = versionParts(candidate), b = versionParts(current);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  String pre(String v) {
    final core = v.split('+').first;
    final i = core.indexOf('-');
    return i < 0 ? '' : core.substring(i + 1);
  }

  final pa = pre(candidate), pb = pre(current);
  if (pa == pb) return false;
  if (pa.isEmpty) return true;
  if (pb.isEmpty) return false;
  return pa.compareTo(pb) > 0;
}

/// "07412d…  Chithram-0.3.0-linux-x64.tar.gz" lines (an optional "*" marks
/// binary mode) as file name → lower-case checksum.
Map<String, String> parseChecksums(String text) {
  final out = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
    if (m != null) out[m.group(2)!.trim()] = m.group(1)!.toLowerCase();
  }
  return out;
}

/// The Android ABI this process runs as, named like the release APKs.
String? androidAbi([Abi? abi]) => switch (abi ?? Abi.current()) {
  Abi.androidArm64 => 'arm64-v8a',
  Abi.androidArm => 'armeabi-v7a',
  Abi.androidX64 => 'x86_64',
  _ => null,
};

/// How this copy of Chithram can be replaced.
sealed class InstallKind {
  const InstallKind();

  /// The file of a release this kind installs.
  String get suffix;
}

class AndroidApk extends InstallKind {
  const AndroidApk(this.abi);
  final String abi;
  @override
  String get suffix => '-android-$abi.apk';
}

class WindowsSetup extends InstallKind {
  const WindowsSetup();
  @override
  String get suffix => '-windows-x64-setup.exe';
}

class LinuxAppImage extends InstallKind {
  const LinuxAppImage(this.path);
  final String path;
  @override
  String get suffix => '-linux-x86_64.AppImage';
}

/// install-linux.sh's directory (it holds the `chithram` binary).
class LinuxTarball extends InstallKind {
  const LinuxTarball(this.dir);
  final String dir;
  @override
  String get suffix => '-linux-x64.tar.gz';
}

/// Works out the [InstallKind] of the running app; null when it can only
/// point at the releases page.
InstallKind? detectInstallKind({
  String? os,
  Map<String, String>? env,
  String? executable,
  bool Function(String path)? exists,
}) {
  os ??= Platform.operatingSystem;
  env ??= Platform.environment;
  exists ??= (p) => FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound;
  switch (os) {
    case 'android':
      final abi = androidAbi();
      return abi == null ? null : AndroidApk(abi);
    case 'windows':
      final exe = executable ?? Platform.resolvedExecutable;
      final dir = exe.substring(0, exe.lastIndexOf(RegExp(r'[\\/]')).clamp(0, exe.length));
      // Inno Setup leaves its uninstaller beside the app; the zip has none.
      return exists('$dir\\unins000.exe') ? const WindowsSetup() : null;
    case 'linux':
      final appImage = env['APPIMAGE'];
      if (appImage != null && appImage.isNotEmpty) return LinuxAppImage(appImage);
      final exe = File(executable ?? Platform.resolvedExecutable);
      final dir = exe.parent.path;
      final data = env['XDG_DATA_HOME']?.isNotEmpty == true ? env['XDG_DATA_HOME']! : '${env['HOME']}/.local/share';
      return dir == '$data/chithram' ? LinuxTarball(dir) : null;
  }
  return null;
}

enum UpdateState { idle, checking, upToDate, available, downloading, installing, restart, failed }

/// Looks for, downloads, checks and installs a newer release.
class AppUpdater extends ChangeNotifier {
  AppUpdater({
    required this.dir,
    Future<String> Function()? version,
    InstallKind? Function()? kind,
    Uri? api,
    HttpClient Function()? client,
    Future<void> Function(File file, InstallKind kind)? install,
  }) : _version = version ?? _packageVersion,
       _kind = kind ?? detectInstallKind,
       _api = api ?? releasesApi,
       _client = client ?? HttpClient.new,
       _installOverride = install;

  /// Where downloads go (the cache's `updates/`, shared by the FileProvider).
  final Directory dir;
  final Future<String> Function() _version;
  final InstallKind? Function() _kind;
  final Uri _api;
  final HttpClient Function() _client;
  final Future<void> Function(File, InstallKind)? _installOverride;

  UpdateState state = UpdateState.idle;

  /// The newer release, once found.
  Release? available;

  /// This copy's version, once read.
  String current = '';

  /// What went wrong or what to do next, in plain words.
  String message = '';

  /// Download progress, 0 to 1.
  double progress = 0;

  /// True when this copy can't install by itself: the page is the way.
  bool get manual => _kind() == null;

  bool get busy => state == UpdateState.checking || state == UpdateState.downloading || state == UpdateState.installing;

  void _set(UpdateState s, [String text = '']) {
    state = s;
    message = text;
    notifyListeners();
  }

  static Future<String> _packageVersion() async => (await PackageInfo.fromPlatform()).version;

  /// Asks GitHub for the newest release. Returns true when it is newer.
  Future<bool> check() async {
    if (busy) return false;
    _set(UpdateState.checking);
    try {
      current = await _version();
      final list = jsonDecode(utf8.decode(await _get(_api, accept: 'application/vnd.github+json')));
      final release = newestRelease(list);
      if (release == null || !isNewerVersion(release.version, current)) {
        available = null;
        _set(UpdateState.upToDate);
        return false;
      }
      available = release;
      final kind = _kind();
      if (kind != null && release.withSuffix(kind.suffix) == null) {
        _set(UpdateState.available, 'This release has no file for this device yet.');
      } else {
        _set(UpdateState.available, kind == null ? 'Get it from $releasesPage' : '');
      }
      return true;
    } catch (e) {
      _set(UpdateState.failed, 'Could not reach GitHub: ${_short(e)}');
      return false;
    }
  }

  /// The automatic check: at most once a day, quiet when nothing is found.
  /// [lastChecked] and [remember] keep the time in prefs.
  Future<bool> dailyCheck({required String? lastChecked, required Future<void> Function(String) remember, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final last = DateTime.tryParse(lastChecked ?? '');
    if (last != null && at.difference(last) < const Duration(hours: 20)) return false;
    await remember(at.toIso8601String());
    final found = await check();
    if (!found && state == UpdateState.failed) _set(UpdateState.idle);
    return found;
  }

  /// Downloads the file for this device, checks it, and installs it.
  Future<void> install() async {
    final release = available;
    final kind = _kind();
    final asset = kind == null ? null : release?.withSuffix(kind.suffix);
    if (release == null || kind == null || asset == null || busy) return;
    _set(UpdateState.downloading);
    progress = 0;
    File? file;
    try {
      final sums = release.assets[checksumsName];
      final expected = sums == null ? null : parseChecksums(utf8.decode(await _get(sums.url)))[asset.name];
      if (expected == null) throw const UpdateException('the release has no checksum for this file, so it was not installed');
      await dir.create(recursive: true);
      file = File('${dir.path}/${asset.name}');
      await _download(asset, file);
      final actual = (await sha256.bind(file.openRead()).first).toString();
      if (actual != expected) throw const UpdateException('the download did not match its checksum');
      _set(UpdateState.installing);
      await (_installOverride ?? _install)(file, kind);
      if (kind is! AndroidApk) _set(UpdateState.restart, 'Chithram ${release.version} is installed. Open Chithram again to use it.');
    } catch (e) {
      if (file != null && await file.exists()) await file.delete();
      _set(UpdateState.failed, _short(e));
    }
  }

  Future<Uint8List> _get(Uri url, {String? accept}) async {
    final client = _client();
    try {
      final req = await client.getUrl(url).timeout(const Duration(seconds: 20));
      if (accept != null) req.headers.set(HttpHeaders.acceptHeader, accept);
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateException('${url.host} answered ${res.statusCode}');
      }
      final b = BytesBuilder(copy: false);
      await res.timeout(const Duration(seconds: 30)).forEach(b.add);
      return b.takeBytes();
    } finally {
      client.close();
    }
  }

  Future<void> _download(ReleaseAsset asset, File target) async {
    final client = _client();
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    try {
      final res = await (await client.getUrl(asset.url).timeout(const Duration(seconds: 30))).close();
      if (res.statusCode != 200) throw UpdateException('the download answered ${res.statusCode}');
      final total = res.contentLength > 0 ? res.contentLength : asset.size;
      var got = 0;
      await for (final chunk in res.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0 && (got / total - progress > 0.01 || got >= total)) {
          progress = (got / total).clamp(0.0, 1.0);
          notifyListeners();
        }
      }
      await sink.close();
      await part.rename(target.path);
    } catch (_) {
      await sink.close().catchError((Object _) {});
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  static const _channel = MethodChannel('dev.chithram/app');

  Future<void> _install(File file, InstallKind kind) async {
    switch (kind) {
      case AndroidApk():
        final r = await _channel.invokeMethod<String>('installApk', {'path': file.path});
        if (r == 'permission') {
          _set(UpdateState.available, 'Allow Chithram to install apps (it opened that setting), then choose Update again.');
          return;
        }
        // The system installer is on screen now; it restarts the app.
        _set(UpdateState.available, 'Follow the installer on screen.');
      case WindowsSetup():
        // The setup's own wizard: it keeps the earlier install's folder and
        // scope, and offers to start the new version at the end.
        await Process.start(file.path, const [], mode: ProcessStartMode.detached);
        exit(0);
      case LinuxAppImage(:final path):
        await Process.run('chmod', ['+x', file.path]);
        // A rename leaves the running AppImage alone until it is opened again.
        await file.rename(path);
      case LinuxTarball(dir: final dest):
        await _unpackOver(file, dest);
    }
  }

  /// install-linux.sh's steps: unpack beside [dest], swap it in, drop the old
  /// one. The running process keeps its open files; the new one starts next time.
  static Future<void> _unpackOver(File tarball, String dest) async {
    final work = Directory('$dest.update');
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);
    try {
      final tar = await Process.run('tar', ['-xzf', tarball.path, '-C', work.path]);
      if (tar.exitCode != 0) throw UpdateException('tar failed: ${tar.stderr}'.trim());
      final top = await work.list().where((e) => e is Directory).cast<Directory>().toList();
      if (top.length != 1 || !await File('${top.single.path}/chithram').exists()) {
        throw const UpdateException('the tarball has no chithram binary');
      }
      final old = Directory('$dest.old');
      if (await old.exists()) await old.delete(recursive: true);
      await Directory(dest).rename(old.path);
      try {
        await top.single.rename(dest);
      } catch (_) {
        await old.rename(dest);
        rethrow;
      }
      await old.delete(recursive: true);
    } finally {
      if (await work.exists()) await work.delete(recursive: true);
      await tarball.delete();
    }
  }

  static String _short(Object e) => switch (e) {
    UpdateException(:final message) => message,
    SocketException() || TimeoutException() => 'no connection',
    PlatformException(:final message) => message ?? 'the installer did not start',
    _ => '$e',
  };
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

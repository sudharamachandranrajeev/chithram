import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:chithram/src/core/update/app_update.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('versions', () {
    test('compare part by part, a release beats its pre-releases', () {
      expect(isNewerVersion('0.10.0', '0.9.9'), isTrue);
      expect(isNewerVersion('0.3.0', '0.3.0'), isFalse);
      expect(isNewerVersion('v0.3.1', '0.3.0+1'), isTrue);
      expect(isNewerVersion('0.1.0', '0.1.0-alpha.2'), isTrue);
      expect(isNewerVersion('0.1.0-alpha.2', '0.1.0-alpha.1'), isTrue);
      expect(isNewerVersion('0.1.0-alpha.2', '0.1.0'), isFalse);
      expect(isNewerVersion('0.2.1', '0.3.0'), isFalse);
    });

    test('the newest app release; drafts and the tdlib binaries are skipped', () {
      final list = [
        {'tag_name': 'tdlib-1.8.69', 'assets': []},
        {'tag_name': 'v0.9.0', 'draft': true, 'assets': []},
        {'tag_name': 'v0.2.1', 'assets': []},
        {'tag_name': 'v0.3.0', 'assets': [
          {'name': 'Chithram-0.3.0-android-arm64-v8a.apk', 'browser_download_url': 'https://x/a.apk', 'size': 3},
        ]},
      ];
      final r = newestRelease(list)!;
      expect(r.version, '0.3.0');
      expect(r.withSuffix(const AndroidApk('arm64-v8a').suffix)?.name, 'Chithram-0.3.0-android-arm64-v8a.apk');
      expect(r.withSuffix(const AndroidApk('armeabi-v7a').suffix), isNull);
    });

    test('SHA256SUMS lines, with and without the binary marker', () {
      final a = 'a' * 64, b = 'B' * 64;
      expect(parseChecksums('$a  one.apk\n$b *two.tar.gz\njunk\n'), {'one.apk': a, 'two.tar.gz': 'b' * 64});
    });
  });

  group('install kind', () {
    test('Android picks the APK for its ABI', () {
      expect(androidAbi(Abi.androidArm), 'armeabi-v7a');
      expect(androidAbi(Abi.androidArm64), 'arm64-v8a');
      expect(androidAbi(Abi.linuxX64), isNull);
    });

    test('Linux: AppImage, install-linux.sh directory, or the page', () {
      expect(
        detectInstallKind(os: 'linux', env: {'APPIMAGE': '/a/Chithram.AppImage', 'HOME': '/h'}),
        isA<LinuxAppImage>().having((k) => k.path, 'path', '/a/Chithram.AppImage'),
      );
      expect(
        detectInstallKind(os: 'linux', env: {'HOME': '/h'}, executable: '/h/.local/share/chithram/chithram'),
        isA<LinuxTarball>().having((k) => k.dir, 'dir', '/h/.local/share/chithram'),
      );
      expect(detectInstallKind(os: 'linux', env: {'HOME': '/h'}, executable: '/usr/lib/chithram/chithram'), isNull);
    });

    test('Windows: the setup only for an installed copy, not the zip', () {
      bool has(String p) => p == r'C:\Apps\Chithram\unins000.exe';
      expect(detectInstallKind(os: 'windows', env: {}, executable: r'C:\Apps\Chithram\chithram.exe', exists: has),
          isA<WindowsSetup>());
      expect(detectInstallKind(os: 'windows', env: {}, executable: r'C:\Zip\chithram.exe', exists: has), isNull);
    });
  });

  group('updater', () {
    late HttpServer server;
    late Directory tmp;
    late Map<String, List<int>> files;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chithram-update-test');
      files = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final body = files[req.uri.path];
        req.response.statusCode = body == null ? 404 : 200;
        if (body != null) req.response.add(body);
        req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await tmp.delete(recursive: true);
    });

    String url(String path) => 'http://127.0.0.1:${server.port}$path';

    void publish(List<int> apk, {String? sum}) {
      const name = 'Chithram-0.4.0-android-arm64-v8a.apk';
      files['/apk'] = apk;
      files['/sums'] = utf8.encode('${sum ?? sha256.convert(apk)}  $name\n');
      files['/releases'] = utf8.encode(jsonEncode([
        {'tag_name': 'v0.4.0', 'assets': [
          {'name': name, 'browser_download_url': url('/apk'), 'size': apk.length},
          {'name': checksumsName, 'browser_download_url': url('/sums')},
        ]},
      ]));
    }

    AppUpdater updater(List<File> installed, {String version = '0.3.0'}) => AppUpdater(
      dir: Directory('${tmp.path}/updates'),
      version: () async => version,
      kind: () => const AndroidApk('arm64-v8a'),
      api: Uri.parse(url('/releases')),
      install: (f, _) async => installed.add(f),
    );

    test('finds, downloads, checks and installs a newer release', () async {
      final apk = List.generate(5000, (i) => i % 251);
      publish(apk);
      final installed = <File>[];
      final u = updater(installed);
      expect(await u.check(), isTrue);
      expect(u.state, UpdateState.available);
      expect(u.available!.version, '0.4.0');
      await u.install();
      expect(u.message, isEmpty);
      expect(installed.single.readAsBytesSync(), apk);
      expect(u.progress, 1);
    });

    test('a download that does not match its checksum is not installed', () async {
      publish([1, 2, 3], sum: 'c' * 64);
      final installed = <File>[];
      final u = updater(installed);
      await u.check();
      await u.install();
      expect(u.state, UpdateState.failed);
      expect(u.message, contains('checksum'));
      expect(installed, isEmpty);
      expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
    });

    test('up to date when this is the newest', () async {
      publish([1]);
      final u = updater([], version: '0.4.0');
      expect(await u.check(), isFalse);
      expect(u.state, UpdateState.upToDate);
    });

    test('the daily check waits a day and keeps quiet when offline', () async {
      final u = AppUpdater(dir: tmp, version: () async => '0.3.0', api: Uri.parse(url('/missing')));
      String? kept;
      final now = DateTime(2026, 10, 24, 12);
      expect(await u.dailyCheck(lastChecked: DateTime(2026, 10, 24, 1).toIso8601String(), remember: (s) async => kept = s, now: now), isFalse);
      expect(kept, isNull, reason: 'checked 11 hours ago');
      expect(await u.dailyCheck(lastChecked: null, remember: (s) async => kept = s, now: now), isFalse);
      expect(kept, now.toIso8601String());
      expect(u.state, UpdateState.idle);
    });

    test('Linux: the tarball is unpacked over the install-linux.sh directory', () async {
      // A tarball like the release's: one top directory with the binary.
      final src = Directory('${tmp.path}/build/chithram-0.4.0-linux-x64')..createSync(recursive: true);
      File('${src.path}/chithram').writeAsStringSync('new');
      final tgz = '${tmp.path}/t.tar.gz';
      expect((await Process.run('tar', ['-czf', tgz, '-C', '${tmp.path}/build', 'chithram-0.4.0-linux-x64'])).exitCode, 0);
      const name = 'Chithram-0.4.0-linux-x64.tar.gz';
      final bytes = File(tgz).readAsBytesSync();
      files['/tgz'] = bytes;
      files['/sums'] = utf8.encode('${sha256.convert(bytes)}  $name\n');
      files['/releases'] = utf8.encode(jsonEncode([
        {'tag_name': 'v0.4.0', 'assets': [
          {'name': name, 'browser_download_url': url('/tgz')},
          {'name': checksumsName, 'browser_download_url': url('/sums')},
        ]},
      ]));
      final dest = Directory('${tmp.path}/share/chithram')..createSync(recursive: true);
      File('${dest.path}/chithram').writeAsStringSync('old');
      File('${dest.path}/stale.so').writeAsStringSync('old');
      final u = AppUpdater(
        dir: Directory('${tmp.path}/updates'),
        version: () async => '0.3.0',
        kind: () => LinuxTarball(dest.path),
        api: Uri.parse(url('/releases')),
      );
      await u.check();
      await u.install();
      expect(u.state, UpdateState.restart, reason: u.message);
      expect(File('${dest.path}/chithram').readAsStringSync(), 'new');
      expect(File('${dest.path}/stale.so').existsSync(), isFalse);
      expect(Directory('${dest.path}.old').existsSync(), isFalse);
      expect(Directory('${dest.path}.update').existsSync(), isFalse);
    });
  });
}

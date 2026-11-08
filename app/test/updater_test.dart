import 'dart:convert';
import 'dart:io';

import 'package:chithram/src/core/updater.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _release(String tag, List<String> names, {bool draft = false}) => {
      'tag_name': tag,
      'draft': draft,
      'html_url': 'https://github.com/x/releases/$tag',
      'assets': [
        for (final n in names) {'name': n, 'browser_download_url': 'https://dl/$tag/$n', 'size': 5},
      ],
    };

void main() {
  group('versions', () {
    test('compare part by part', () {
      expect(isNewerVersion('0.4.1', '0.4.0'), isTrue);
      expect(isNewerVersion('0.10.0', '0.9.9'), isTrue);
      expect(isNewerVersion('v1.0', '0.99.99'), isTrue);
      expect(isNewerVersion('0.4.0', '0.4.0'), isFalse);
      expect(isNewerVersion('0.4.0', '0.4.1'), isFalse);
      expect(isNewerVersion('0.4.0+7', '0.4.0'), isFalse);
      expect(versionParts('v0.7.10-beta'), [0, 7, 10]);
    });

    test('newest release skips drafts and counts pre-releases', () {
      final best = newestRelease([
        _release('v0.3.2', []),
        _release('v0.5.0', [], draft: true),
        _release('v0.4.1', []),
        {'no': 'tag'},
      ]);
      expect(best?.version, '0.4.1');
      expect(newestRelease('not a list'), isNull);
    });
  });

  test('checksums parse with one or two spaces and a star', () {
    final a = 'a' * 64, b = 'B' * 64;
    final sums = parseChecksums('$a  Chithram-0.4.1-windows-x64-setup.exe\n$b *x.AppImage\nshort  y\n\n');
    expect(sums, {'Chithram-0.4.1-windows-x64-setup.exe': a, 'x.AppImage': 'b' * 64});
  });

  test('picks the installer for each OS', () {
    final r = Release.fromJson(_release('v0.4.1', [
      'Chithram-0.4.1-windows-x64-portable.zip',
      'Chithram-0.4.1-windows-x64-setup.exe',
      'Chithram-0.4.1-linux-x86_64.AppImage',
      'Chithram-0.4.1-android-arm64-v8a.apk',
      checksumsName,
    ]));
    expect(r.installerFor('windows')?.name, 'Chithram-0.4.1-windows-x64-setup.exe');
    expect(r.installerFor('linux')?.name, 'Chithram-0.4.1-linux-x86_64.AppImage');
    expect(r.installerFor('android'), isNull);
    expect(r.checksums, isNotNull);
  });

  group('UpdateManager', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('chithram-update-test'));
    tearDown(() => dir.delete(recursive: true));

    const setup = 'Chithram-0.4.1-windows-x64-setup.exe';
    final payload = utf8.encode('installer bytes');

    UpdateManager manager({required String sum, List<File>? installed, int listStatus = 200}) => UpdateManager(
          currentVersion: () async => '0.4.0',
          dir: dir,
          os: 'windows',
          fetch: (url) async {
            if (url.toString() == releaseApiUrl) {
              return (listStatus, utf8.encode(jsonEncode([_release('v0.4.1', [setup, checksumsName])])));
            }
            return (200, utf8.encode('$sum  $setup\n'));
          },
          download: (url, sink, progress) async {
            sink.add(payload);
            progress(payload.length, payload.length);
            return 200;
          },
          install: (file, os) async => installed?.add(file),
        );

    test('finds, downloads, checks and installs a newer version', () async {
      final installed = <File>[];
      final u = manager(sum: sha256.convert(payload).toString(), installed: installed);
      await u.check();
      expect(u.state, UpdateState.available);
      expect(u.available?.version, '0.4.1');
      expect(await u.downloadAndInstall(), isTrue);
      expect(u.state, UpdateState.ready);
      expect(installed.single.path, endsWith(setup));
      expect(await installed.single.readAsBytes(), payload);
    });

    test('a checksum mismatch deletes the file and installs nothing', () async {
      final installed = <File>[];
      final u = manager(sum: 'f' * 64, installed: installed);
      await u.check();
      expect(await u.downloadAndInstall(), isFalse);
      expect(u.state, UpdateState.failed);
      expect(installed, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('a quiet check that fails stays quiet', () async {
      final u = manager(sum: '', listStatus: 500);
      await u.check(quiet: true);
      expect(u.state, UpdateState.idle);
      await u.check();
      expect(u.state, UpdateState.failed);
    });

    test('the same version is up to date', () async {
      final u = UpdateManager(
        currentVersion: () async => '0.4.1',
        dir: dir,
        os: 'windows',
        fetch: (_) async => (200, utf8.encode(jsonEncode([_release('v0.4.1', [setup])]))),
      );
      await u.check();
      expect(u.state, UpdateState.upToDate);
    });
  });
}

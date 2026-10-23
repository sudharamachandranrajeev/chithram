import 'dart:io';

import 'package:chithram/src/core/secrets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keyring that always fails, like Linux without a secret service.
class _BrokenKeyring extends FlutterSecureStorage {
  const _BrokenKeyring();
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) =>
      throw PlatformException(code: 'Libsecret error');
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) =>
      throw PlatformException(code: 'Libsecret error');
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) =>
      throw PlatformException(code: 'Libsecret error');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('secrets'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('MemorySecretStore round-trips', () async {
    final s = MemorySecretStore();
    expect(await s.read('tmdb.key'), isNull);
    await s.write('tmdb.key', 'abc');
    expect(await s.read('tmdb.key'), 'abc');
    await s.delete('tmdb.key');
    expect(await s.read('tmdb.key'), isNull);
    expect(s.isFallback, isFalse);
  });

  Future<void> roundTrip(SecretStore s) async {
    expect(await s.read('torznab.e1'), isNull);
    await s.write('torznab.e1', 'key-1');
    await s.write('tmdb.key', 'tok');
    expect(await s.read('torznab.e1'), 'key-1');
    await s.write('torznab.e1', 'key-2');
    expect(await s.read('torznab.e1'), 'key-2');
    await s.delete('torznab.e1');
    expect(await s.read('torznab.e1'), isNull);
    expect(await s.read('tmdb.key'), 'tok');
  }

  test('Linux without a keyring: round-trips through a 0600 file', () async {
    final file = File('${dir.path}/support/secrets.json');
    final s = SystemSecretStore(fallbackFile: file, storage: const _BrokenKeyring(), linux: true);
    await roundTrip(s);
    expect(s.isFallback, isTrue);
    expect(file.existsSync(), isTrue);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    if (!Platform.isWindows) {
      final mode = file.statSync().mode & 0x1ff;
      expect(mode.toRadixString(8), '600');
    }
  });

  test('no plugin registered (flutter test) behaves as no keyring on Linux', () async {
    final file = File('${dir.path}/secrets.json');
    final s = SystemSecretStore(fallbackFile: file, linux: true);
    await roundTrip(s);
    expect(s.isFallback, isTrue);
  });

  test('off Linux a keyring failure is an error, never a plaintext file', () async {
    final file = File('${dir.path}/secrets.json');
    final s = SystemSecretStore(fallbackFile: file, storage: const _BrokenKeyring(), linux: false);
    await expectLater(s.write('k', 'v'), throwsA(isA<PlatformException>()));
    expect(file.existsSync(), isFalse);
    expect(s.isFallback, isFalse);
  });
}

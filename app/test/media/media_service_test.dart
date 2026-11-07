import 'dart:io';

import 'package:chithram/src/media/gateway_client.dart';
import 'package:chithram/src/media/media_config.dart';
import 'package:chithram/src/media/models.dart';
import 'package:chithram/src/media/token_store.dart';
import 'package:chithram/src/core/secrets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'media_support.dart';

void main() {
  test('flag off: no client is built, no call goes out, nothing is read', () async {
    final h = Harness(enabled: false);
    expect(h.service.enabled, isFalse);
    expect(h.service.paired, isFalse);
    await h.service.load();
    expect(h.service.loaded, isFalse, reason: 'the token is not even read');
    await expectLater(h.service.call((c) => c.me()), throwsA(isA<GatewayException>()));
    expect(h.made, 0);
    expect(h.gateway.calls, isEmpty);
    expect(h.service.clientForStream, isNull);
  });

  test('flag on and paired: calls reach the gateway through one client', () async {
    final h = Harness();
    await h.service.load();
    expect(h.service.paired, isTrue);
    await h.service.refreshMe();
    expect(h.service.role, MediaRole.admin);
    await h.service.call((c) => c.downloads());
    expect(h.made, 1);
    expect(h.gateway.calls, ['me', 'downloads']);
  });

  test('401 from the gateway unpairs: token and pin are forgotten', () async {
    final h = Harness();
    await h.service.load();
    h.gateway.meError = const GatewayException(GatewayErrorKind.unauthorized, 'gone');
    await expectLater(h.service.refreshMe(), throwsA(isA<GatewayException>()));
    expect(await h.tokens.read(), isNull);
    expect(h.service.paired, isFalse);
    expect(MediaConfig.read(h.prefs).configured, isFalse);
  });

  test('503 does not unpair', () async {
    final h = Harness();
    await h.service.load();
    h.gateway.meError = const GatewayException(GatewayErrorKind.unavailable, 'down');
    await expectLater(h.service.refreshMe(), throwsA(isA<GatewayException>()));
    expect(h.service.paired, isTrue);
    expect(await h.tokens.read(), testToken);
  });

  test('pairing validates input first and stores the token only on success', () async {
    final h = Harness(paired: false);
    await h.service.load();
    for (final bad in [
      (address: 'http://media.test', fp: testFingerprint, code: '123456'),
      (address: 'media.test/x', fp: testFingerprint, code: '123456'),
      (address: 'media.test', fp: 'abc', code: '123456'),
      (address: 'media.test', fp: testFingerprint, code: '12345'),
    ]) {
      await expectLater(
        h.service.pair(address: bad.address, fingerprint: bad.fp, code: bad.code),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.invalidInput)),
        reason: '$bad',
      );
    }
    expect(h.made, 0, reason: 'invalid input never reaches the network');
    expect(await h.tokens.read(), isNull);

    await h.service.pair(address: 'Media.Test:8443', fingerprint: testFingerprint.toLowerCase(), code: '123456');
    expect(h.service.paired, isTrue);
    expect(await h.tokens.read(), testToken);
    final cfg = MediaConfig.read(h.prefs);
    expect(cfg.host, const GatewayHost('media.test', 8443));
    expect(cfg.fingerprint, testFingerprint);
    expect(h.service.me?.role, MediaRole.admin);
  });

  test('a refused code stores nothing', () async {
    final h = Harness(paired: false);
    h.gateway.calls.clear();
    final failing = _RefusingGateway();
    final svc = Harness(paired: false, gateway: failing);
    await svc.service.load();
    await expectLater(
      svc.service.pair(address: 'media.test', fingerprint: testFingerprint, code: '000000'),
      throwsA(isA<GatewayException>()),
    );
    expect(await svc.tokens.read(), isNull);
    expect(MediaConfig.read(svc.prefs).configured, isFalse);
    expect(svc.service.paired, isFalse);
  });

  test('unpair clears the token store and the pin', () async {
    final h = Harness();
    await h.service.load();
    await h.service.unpair();
    expect(await h.tokens.read(), isNull);
    expect(MediaConfig.read(h.prefs).configured, isFalse);
    expect(h.service.paired, isFalse);
  });

  test('switching the flag off drops the in-memory token and role', () async {
    final h = Harness();
    await h.service.load();
    await h.service.refreshMe();
    await h.service.setEnabled(false);
    expect(h.service.me, isNull);
    expect(h.service.loaded, isFalse);
    expect(h.service.paired, isFalse);
    await expectLater(h.service.call((c) => c.me()), throwsA(isA<GatewayException>()));
  });

  group('playback proxy', () {
    Future<bool> listening(String url) async {
      try {
        (await Socket.connect('127.0.0.1', Uri.parse(url).port)).destroy();
        return true;
      } on SocketException {
        return false;
      }
    }

    // Closing is asynchronous: allow it a moment.
    Future<bool> stopsListening(String url) async {
      for (var i = 0; i < 50; i++) {
        if (!await listening(url)) return true;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return false;
    }

    test('not paired: no proxy', () async {
      final h = Harness(paired: false);
      await h.service.load();
      expect(await h.service.startStream('a' * 32), isNull);
    });

    test('unpairing closes the open proxy', () async {
      final h = Harness();
      await h.service.load();
      final url = (await h.service.startStream('a' * 32))!.url;
      expect(await listening(url), isTrue);
      await h.service.unpair();
      expect(await stopsListening(url), isTrue);
    });

    test('switching Media off closes the open proxy', () async {
      final h = Harness();
      await h.service.load();
      final url = (await h.service.startStream('a' * 32))!.url;
      expect(await listening(url), isTrue);
      await h.service.setEnabled(false);
      expect(await stopsListening(url), isTrue);
    });

    test('a 401 on the stream unpairs the device', () async {
      final h = Harness(gateway: _StreamRefusingGateway());
      await h.service.load();
      final p = (await h.service.startStream('a' * 32))!;
      final http = HttpClient();
      addTearDown(http.close);
      final res = await (await http.getUrl(Uri.parse(p.url))).close();
      expect(res.statusCode, 401);
      await res.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.service.paired, isFalse);
      expect(await h.tokens.read(), isNull);
    });
  });

  group('token store', () {
    test('the secret store keeps the token under one key and clears it', () async {
      final secrets = MemorySecretStore();
      final store = SecretTokenStore(secrets);
      expect(await store.read(), isNull);
      await store.write(testToken);
      expect(await store.read(), testToken);
      expect(await secrets.read('media.deviceToken'), testToken);
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('the token is never written to prefs', () async {
      final h = Harness(paired: false);
      await h.service.load();
      await h.service.pair(address: 'media.test', fingerprint: testFingerprint, code: '123456');
      final all = [
        h.prefs.getString(mediaHostPref),
        h.prefs.getString(mediaFingerprintPref),
        h.prefs.getInt(mediaPortPref),
      ];
      expect(all.any((v) => '$v'.contains(testToken)), isFalse);
    });
  });
}

class _RefusingGateway extends FakeGateway {
  @override
  Future<PairResult> pair(String code, String deviceName) async =>
      throw const GatewayException(GatewayErrorKind.unauthorized, 'That pairing code is wrong or has expired.');
}

class _StreamRefusingGateway extends FakeGateway {
  @override
  Future<HttpClientResponse> openStream(String itemId, {String? range}) async =>
      throw const GatewayException(GatewayErrorKind.unauthorized, 'This device is no longer paired.');
}

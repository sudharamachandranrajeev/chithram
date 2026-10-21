import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:localsend_rx/localsend_rx.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  test('fingerprint is uppercase hex SHA-256 of the DER certificate', () async {
    final id = await sharedIdentity();
    expect(id.fingerprint, matches(RegExp(r'^[0-9A-F]{64}$')));
    expect(id.fingerprint, LsIdentity.fingerprintOf(CryptoUtils.getBytesFromPEMString(id.certificatePem)));
  });

  test('certificate is CN=Chithram, valid from yesterday for ten years', () async {
    final id = await sharedIdentity();
    final data = X509Utils.x509CertificateFromPem(id.certificatePem);
    final v = data.tbsCertificate!.validity;
    final now = DateTime.now().toUtc();
    expect(v.notBefore.isBefore(now.subtract(const Duration(hours: 12))), isTrue);
    expect(v.notBefore.isAfter(now.subtract(const Duration(days: 2))), isTrue);
    final years = v.notAfter.difference(v.notBefore).inDays / 365;
    expect(years, closeTo(10, 0.1));
    expect(data.tbsCertificate!.subject['2.5.4.3'], 'Chithram');
  });

  test('the server can load the generated key and certificate', () async {
    final id = await sharedIdentity();
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, id.securityContext());
    await server.close();
  });

  group('storage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ls_id'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('is written once, reused, and the key is private to this user', () async {
      final a = await LsIdentity.loadOrCreate(dir);
      final b = await LsIdentity.loadOrCreate(dir);
      expect(b.fingerprint, a.fingerprint);
      if (!Platform.isWindows) {
        expect(File('${dir.path}/key.pem').statSync().mode & 0x1ff, 0x180); // 0600
      }
    });

    test('unparsable files are replaced', () async {
      final a = await LsIdentity.loadOrCreate(dir);
      File('${dir.path}/cert.pem').writeAsStringSync('garbage');
      final b = await LsIdentity.loadOrCreate(dir);
      expect(b.fingerprint, isNot(a.fingerprint));
      expect(LsIdentity.tryParse(b.certificatePem, b.privateKeyPem), isNotNull);
    });

    test('a certificate within 30 days of expiry or not yet valid is renewed', () async {
      final near = await LsIdentity.generate(days: 20);
      expect(LsIdentity.tryParse(near.certificatePem, near.privateKeyPem), isNull);
      final id = await sharedIdentity();
      expect(LsIdentity.tryParse(id.certificatePem, id.privateKeyPem), isNotNull);
      expect(LsIdentity.tryParse(id.certificatePem, id.privateKeyPem, now: DateTime.now().add(const Duration(days: 3640))), isNull);
      expect(LsIdentity.tryParse(id.certificatePem, id.privateKeyPem, now: DateTime.now().subtract(const Duration(days: 30))), isNull);
      expect(LsIdentity.tryParse(id.certificatePem, 'nope'), isNull);
      expect(utf8.encode(id.privateKeyPem), isNotEmpty);
    });
  });
}

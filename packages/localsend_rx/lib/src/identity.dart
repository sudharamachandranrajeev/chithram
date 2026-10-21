import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// This device's identity: a self-signed certificate whose SHA-256 is the
/// fingerprint peers pin.
class LsIdentity {
  const LsIdentity({required this.fingerprint, required this.certificatePem, required this.privateKeyPem});

  /// Uppercase hex SHA-256 of the DER certificate.
  final String fingerprint;
  final String certificatePem;
  final String privateKeyPem;

  static const _validFor = 3650;
  static const _renewWithin = Duration(days: 30);

  /// Uppercase hex SHA-256 of the certificate's DER bytes.
  static String fingerprintOf(Uint8List der) => sha256.convert(der).toString().toUpperCase();

  /// A fresh RSA-2048 key and a certificate for CN=Chithram, valid from one
  /// day ago (clock skew between devices) for [days] days. Runs in an isolate:
  /// key generation takes seconds on a slow device.
  static Future<LsIdentity> generate({int days = _validFor, DateTime? notBefore}) {
    final from = notBefore ?? DateTime.now().toUtc().subtract(const Duration(days: 1));
    return Isolate.run(() => _generate(days, from));
  }

  static LsIdentity _generate(int days, DateTime notBefore) {
    final pair = CryptoUtils.generateRSAKeyPair();
    final priv = pair.privateKey as RSAPrivateKey;
    final pub = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem({'CN': 'Chithram'}, priv, pub);
    final serial = BigInt.from(Random.secure().nextInt(1 << 31) + 1).toString();
    final cert = X509Utils.generateSelfSignedCertificate(
      priv,
      csr,
      days,
      serialNumber: serial,
      notBefore: notBefore,
    );
    return LsIdentity(
      fingerprint: fingerprintOf(CryptoUtils.getBytesFromPEMString(cert)),
      certificatePem: cert,
      privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(priv),
    );
  }

  /// Parses stored PEM. Null when it is unreadable, not yet valid, expired or
  /// within 30 days of expiry (time to make a new one).
  static LsIdentity? tryParse(String certPem, String keyPem, {DateTime? now}) {
    try {
      final der = CryptoUtils.getBytesFromPEMString(certPem);
      final data = X509Utils.x509CertificateFromPem(certPem);
      final validity = data.tbsCertificate?.validity;
      if (validity == null) return null;
      final t = (now ?? DateTime.now()).toUtc();
      if (validity.notBefore.isAfter(t) || validity.notAfter.isBefore(t.add(_renewWithin))) return null;
      CryptoUtils.rsaPrivateKeyFromPem(keyPem);
      // The server must be able to load them too.
      SecurityContext()
        ..useCertificateChainBytes(utf8.encode(certPem))
        ..usePrivateKeyBytes(utf8.encode(keyPem));
      return LsIdentity(fingerprint: fingerprintOf(der), certificatePem: certPem, privateKeyPem: keyPem);
    } catch (_) {
      return null;
    }
  }

  /// Reads `cert.pem` and `key.pem` from [dir], or makes and stores new ones
  /// (the key file readable by this user only).
  static Future<LsIdentity> loadOrCreate(Directory dir) async {
    final certFile = File('${dir.path}/cert.pem');
    final keyFile = File('${dir.path}/key.pem');
    try {
      if (await certFile.exists() && await keyFile.exists()) {
        final id = tryParse(await certFile.readAsString(), await keyFile.readAsString());
        if (id != null) return id;
      }
    } on FileSystemException {
      // Unreadable: replace it.
    }
    final id = await generate();
    await dir.create(recursive: true);
    await _writePrivate(keyFile, id.privateKeyPem);
    await _writePrivate(certFile, id.certificatePem);
    return id;
  }

  static Future<void> _writePrivate(File f, String text) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString('');
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', tmp.path]);
      } catch (_) {
        // Best effort: the directory is app-private anyway.
      }
    }
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
  }

  /// The TLS context the server presents.
  SecurityContext securityContext() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
}

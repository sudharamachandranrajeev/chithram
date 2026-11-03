import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// SHA-256 fingerprint of the first certificate in a PEM file, as AA:BB:... (uppercase).
/// This is the value the app pins at pairing time.
String certFingerprint(String pem) {
  final m = RegExp(
    r'-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----',
  ).firstMatch(pem);
  if (m == null) throw const FormatException('no certificate in PEM');
  final der = base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
  final bytes = sha256.convert(der).bytes;
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}

SecurityContext serverContext(String certPath, String keyPath) {
  return SecurityContext()
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);
}

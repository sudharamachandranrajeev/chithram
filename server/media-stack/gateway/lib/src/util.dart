import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Random _rng = Random.secure();

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

String toHex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

String sha256Hex(String s) => toHex(sha256.convert(utf8.encode(s)).bytes);

/// 256-bit random token, URL-safe, no padding.
String newToken() => base64Url.encode(randomBytes(32)).replaceAll('=', '');

/// Constant-time string equality (length leak only).
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

/// Random 6-digit code, zero padded.
String newCode() => _rng.nextInt(1000000).toString().padLeft(6, '0');

String newId() => toHex(randomBytes(4));

int nowMs() => DateTime.now().millisecondsSinceEpoch;

import 'dart:convert';
import 'dart:typed_data';

import 'blake2b.dart';
import 'ed25519.dart';

class MinisignException implements Exception {
  MinisignException(this.message);
  final String message;
  @override
  String toString() => 'MinisignException: $message';
}

/// A parsed minisign public key (`Ed` + 8-byte key id + 32-byte key).
class MinisignPublicKey {
  MinisignPublicKey(this.keyId, this.key);
  final Uint8List keyId;
  final Uint8List key;

  /// Parses the two-line `.pub` file, or the bare base64 line.
  factory MinisignPublicKey.parse(String text) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    final b64 = lines.firstWhere((l) => !l.startsWith('untrusted comment:'), orElse: () => '');
    final raw = _b64(b64.trim());
    if (raw.length != 42 || raw[0] != 0x45 || raw[1] != 0x64) {
      throw MinisignException('not a minisign public key');
    }
    return MinisignPublicKey(Uint8List.fromList(raw.sublist(2, 10)), Uint8List.fromList(raw.sublist(10)));
  }

  String get id => keyId.reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  String get fingerprint => [...keyId, ...key].map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class MinisignSignature {
  MinisignSignature(this.prehashed, this.keyId, this.signature, this.trustedComment, this.globalSignature);
  final bool prehashed;
  final Uint8List keyId;
  final Uint8List signature;
  final String trustedComment;
  final Uint8List globalSignature;

  factory MinisignSignature.parse(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.length < 4 || !lines[0].startsWith('untrusted comment:')) {
      throw MinisignException('malformed signature file');
    }
    final raw = _b64(lines[1].trim());
    if (raw.length != 74) throw MinisignException('bad signature length');
    final algo = String.fromCharCodes(raw.sublist(0, 2));
    if (algo != 'ED' && algo != 'Ed') throw MinisignException('unknown signature algorithm');
    const tc = 'trusted comment: ';
    if (!lines[2].startsWith(tc)) throw MinisignException('missing trusted comment');
    final g = _b64(lines[3].trim());
    if (g.length != 64) throw MinisignException('bad global signature');
    return MinisignSignature(algo == 'ED', Uint8List.fromList(raw.sublist(2, 10)),
        Uint8List.fromList(raw.sublist(10)), lines[2].substring(tc.length), Uint8List.fromList(g));
  }
}

List<int> _b64(String s) {
  try {
    return base64.decode(s);
  } on FormatException {
    throw MinisignException('bad base64');
  }
}

/// Verifies [sigText] over [message] with [pub]. Checks the key id, the file
/// signature and the global (trusted comment) signature. Throws on any failure.
void minisignVerify(MinisignPublicKey pub, List<int> message, String sigText) {
  final sig = MinisignSignature.parse(sigText);
  if (!_eq(sig.keyId, pub.keyId)) throw MinisignException('signature key id does not match the public key');
  final signed = sig.prehashed ? blake2b512(message) : Uint8List.fromList(message);
  if (!ed25519Verify(pub.key, signed, sig.signature)) throw MinisignException('bad signature');
  final global = [...sig.signature, ...utf8.encode(sig.trustedComment)];
  if (!ed25519Verify(pub.key, global, sig.globalSignature)) throw MinisignException('bad trusted-comment signature');
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

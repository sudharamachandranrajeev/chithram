import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha512;

/// Ed25519 signature verification (RFC 8032), pure Dart on BigInt.
/// Verify only: Chithram never holds a signing key.
final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _l = (BigInt.one << 252) + BigInt.parse('27742317777372353535851937790883648493');
final BigInt _d = (-BigInt.from(121665) * BigInt.from(121666).modInverse(_p)) % _p;
final BigInt _i = BigInt.two.modPow((_p - BigInt.one) ~/ BigInt.from(4), _p);

typedef _Pt = List<BigInt>; // extended coordinates X, Y, Z, T

_Pt _add(_Pt a, _Pt b) {
  final aa = (a[1] - a[0]) * (b[1] - b[0]) % _p;
  final bb = (a[1] + a[0]) * (b[1] + b[0]) % _p;
  final cc = a[3] * BigInt.two * _d * b[3] % _p;
  final dd = a[2] * BigInt.two * b[2] % _p;
  final e = bb - aa, f = dd - cc, g = dd + cc, h = bb + aa;
  return [e * f % _p, g * h % _p, f * g % _p, e * h % _p];
}

_Pt _mul(BigInt s, _Pt pt) {
  _Pt r = [BigInt.zero, BigInt.one, BigInt.one, BigInt.zero];
  var q = pt;
  while (s > BigInt.zero) {
    if (s.isOdd) r = _add(r, q);
    q = _add(q, q);
    s >>= 1;
  }
  return r;
}

BigInt _le(List<int> b) {
  var r = BigInt.zero;
  for (var k = b.length - 1; k >= 0; k--) {
    r = (r << 8) | BigInt.from(b[k]);
  }
  return r;
}

_Pt? _decode(List<int> s) {
  if (s.length != 32) return null;
  final raw = _le(s);
  final sign = (raw >> 255).toInt();
  final y = raw & ((BigInt.one << 255) - BigInt.one);
  if (y >= _p) return null;
  final x2 = (y * y - BigInt.one) * (_d * y * y + BigInt.one).modInverse(_p) % _p;
  var x = x2.modPow((_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
  if ((x * x - x2) % _p != BigInt.zero) x = x * _i % _p;
  if ((x * x - x2) % _p != BigInt.zero) return null;
  if (x == BigInt.zero && sign == 1) return null;
  if (x.isOdd != (sign == 1)) x = _p - x;
  return [x, y, BigInt.one, x * y % _p];
}

final _Pt _base = () {
  final y = BigInt.from(4) * BigInt.from(5).modInverse(_p) % _p;
  final x2 = (y * y - BigInt.one) * (_d * y * y + BigInt.one).modInverse(_p) % _p;
  var x = x2.modPow((_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
  if ((x * x - x2) % _p != BigInt.zero) x = x * _i % _p;
  if (x.isOdd) x = _p - x;
  return [x, y, BigInt.one, x * y % _p];
}();

bool _equal(_Pt a, _Pt b) =>
    (a[0] * b[2] - b[0] * a[2]) % _p == BigInt.zero && (a[1] * b[2] - b[1] * a[2]) % _p == BigInt.zero;

/// True when [sig] (64 bytes) is a valid Ed25519 signature of [msg] under [publicKey] (32 bytes).
bool ed25519Verify(List<int> publicKey, List<int> msg, List<int> sig) {
  if (publicKey.length != 32 || sig.length != 64) return false;
  final a = _decode(publicKey);
  final r = _decode(sig.sublist(0, 32));
  if (a == null || r == null) return false;
  final s = _le(sig.sublist(32));
  if (s >= _l) return false;
  final digest = sha512.convert(Uint8List.fromList([...sig.sublist(0, 32), ...publicKey, ...msg])).bytes;
  final k = _le(digest) % _l;
  return _equal(_mul(s, _base), _add(r, _mul(k, a)));
}

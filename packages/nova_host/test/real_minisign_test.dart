// Cross-check against the real `minisign` tool (CI Linux job generates the files).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

void main() {
  final dir = Platform.environment['NOVA_REAL_MINISIGN_DIR'];
  test('signature made by the real minisign binary verifies', () {
    final pub = MinisignPublicKey.parse(File('$dir/k.pub').readAsStringSync());
    final msg = File('$dir/f').readAsBytesSync();
    minisignVerify(pub, msg, File('$dir/f.minisig').readAsStringSync());
    expect(() => minisignVerify(pub, [...msg, 1], File('$dir/f.minisig').readAsStringSync()),
        throwsA(isA<MinisignException>()));
  }, skip: dir == null ? 'NOVA_REAL_MINISIGN_DIR not set' : false);
}

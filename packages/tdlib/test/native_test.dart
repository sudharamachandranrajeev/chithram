// Needs the real library: set CHITHRAM_TDLIB_LIB (tdlib.yml does, against the
// library it just built). Skipped otherwise.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tdlib/tdlib.dart';

void main() {
  final lib = Platform.environment['CHITHRAM_TDLIB_LIB'];
  final skip = lib == null || lib.isEmpty ? 'CHITHRAM_TDLIB_LIB is not set' : null;

  test('the native transport answers requests and reports the first state', () async {
    final t = await NativeTdTransport.open();
    addTearDown(t.close);
    final v = await t.request({'@type': 'getOption', 'name': 'version'}).timeout(const Duration(seconds: 20));
    expect(v['value'], matches(RegExp(r'^\d+\.\d+\.\d+$')));
    final s = await t.request({'@type': 'getAuthorizationState'}).timeout(const Duration(seconds: 20));
    expect(s['@type'], 'authorizationStateWaitTdlibParameters');
  }, skip: skip);

  test('TdClient starts, opens a database and asks for the phone', () async {
    final dir = Directory.systemTemp.createTempSync('tdlib-native');
    addTearDown(() => dir.deleteSync(recursive: true));
    final client = await TdClient.openNative();
    addTearDown(client.close);
    final states = <TgAuthState>[];
    client.authStates.listen(states.add);
    await client.start(
      apiId: 1,
      apiHash: '00000000000000000000000000000000',
      databaseDirectory: '${dir.path}/db',
      filesDirectory: '${dir.path}/files',
      encryptionKey: Uint8List(32),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (states.whereType<TgAuthWaitPhone>().isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(states.whereType<TgAuthWaitPhone>(), isNotEmpty, reason: 'states: $states');
  }, skip: skip);
}

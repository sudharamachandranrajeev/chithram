import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/features/torrents/network_dialog.dart';
import 'package:chithram/src/features/torrents/torrent_logic.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NetworkGuard guard;
  late bool? result;
  late List<Socks5Address> probed;

  Future<void> open(WidgetTester t, {required bool reachable}) async {
    guard = NetworkGuard(Prefs.memory());
    result = null;
    probed = [];
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await chooseNetwork(context, guard, probe: (a) async {
            probed.add(a);
            return reachable;
          }),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
  }

  testWidgets('direct warns about the IP and stores the choice', (t) async {
    await open(t, reachable: true);
    expect(find.textContaining('see your IP address'), findsOneWidget);
    expect(find.textContaining('DHT'), findsOneWidget);
    await t.tap(find.byKey(NetworkDialogKeys.direct));
    await t.pumpAndSettle();
    expect(result, isTrue);
    expect(guard.choice.mode, NetworkMode.direct);
  });

  testWidgets('cancel leaves it unset', (t) async {
    await open(t, reachable: true);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(result, isFalse);
    expect(guard.needsChoice, isTrue);
  });

  testWidgets('socks5: an unreachable proxy is refused, a reachable one stored', (t) async {
    await open(t, reachable: false);
    await t.tap(find.byKey(NetworkDialogKeys.socks5));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(Keys.textEntryField), 'socks5://10.0.0.9:1080');
    await t.tap(find.byKey(Keys.textEntryOk));
    await t.pumpAndSettle();
    expect(probed.single.port, 1080);
    expect(find.textContaining('Nothing answered at 10.0.0.9:1080'), findsOneWidget);
    expect(guard.needsChoice, isTrue);

    await t.tap(find.byKey(NetworkDialogKeys.socks5));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(Keys.textEntryField), 'not an address');
    await t.tap(find.byKey(Keys.textEntryOk));
    await t.pumpAndSettle();
    expect(probed, hasLength(1), reason: 'an invalid address is not probed');
    expect(find.textContaining('not a SOCKS5 address'), findsOneWidget);
  });

  testWidgets('socks5: reachable proxy is stored', (t) async {
    await open(t, reachable: true);
    await t.tap(find.byKey(NetworkDialogKeys.socks5));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(Keys.textEntryField), 'socks5://10.0.0.9:1080');
    await t.tap(find.byKey(Keys.textEntryOk));
    await t.pumpAndSettle();
    expect(result, isTrue);
    expect(guard.choice.socks5!.url, 'socks5://10.0.0.9:1080');
  });
}

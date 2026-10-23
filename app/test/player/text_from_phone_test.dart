import 'package:chithram/src/core/paths.dart';
import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/receive/receive_service.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram/src/ui/common/text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_rx/localsend_rx.dart';

class _Receive extends ReceiveService {
  _Receive()
      : super(
          navigatorKey: GlobalKey<NavigatorState>(),
          paths: AppPaths.under('/nonexistent/chithram-test'),
          prefs: Prefs.memory(),
        );
  int starts = 0, stops = 0;

  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async => stops++;
}

Future<_Receive> _open(WidgetTester t, {required bool acceptFromPhone, Size size = const Size(1920, 1080)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final receive = _Receive();
  await t.pumpWidget(AppServicesScope(
    services: AppServices.memory(receive: receive),
    child: MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => askText(c, title: 'Key', kind: TextEntryKind.pin, acceptFromPhone: acceptFromPhone),
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
  return receive;
}

String _field(WidgetTester t) => t.widget<TextField>(find.byKey(Keys.textEntryField)).controller!.text;

void main() {
  testWidgets('text accepted from the phone fills the open field', (t) async {
    final r = await _open(t, acceptFromPhone: true);
    expect(r.starts, 1);
    r.debugIncoming(const TextIncoming('  eyJabc.def  ', 'Phone', '10.0.0.2'));
    await t.pump();
    expect(_field(t), 'eyJabc.def');
    expect(find.byKey(Keys.textEntrySend), findsNothing);
    await t.tap(find.byKey(Keys.textEntryOk));
    await t.pumpAndSettle();
    expect(r.stops, 1);
    // Closed: the sink is gone, so text takes the normal intake path again.
    r.debugIncoming(const TextIncoming('later', 'Phone', '10.0.0.2'));
  });

  testWidgets('without acceptFromPhone nothing is routed or started', (t) async {
    final r = await _open(t, acceptFromPhone: false);
    expect(r.starts, 0);
    expect(_field(t), '');
  });

  testWidgets('on a phone the receiver is not started', (t) async {
    final r = await _open(t, acceptFromPhone: true, size: const Size(400, 800));
    expect(r.starts, 0);
  });
}

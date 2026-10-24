import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/plugins/plugin_registry.dart';
import 'package:chithram/src/plugins/ui/plugin_keys.dart';
import 'package:chithram/src/plugins/ui/plugins_settings.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_support.dart';

void main() {
  late FakeUiRegistry reg;
  setUp(() => reg = FakeUiRegistry());

  Future<void> open(WidgetTester t, {FormFactor form = FormFactor.tv, Size size = const Size(1920, 1080)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppServicesScope(
      services: AppServices.memory(plugins: reg),
      child: FormScope(
        form: form,
        child: MaterialApp(theme: buildChithramTheme(form: form), home: const PluginsPage()),
      ),
    ));
    await t.pumpAndSettle();
  }

  Future<void> ask(WidgetTester t, String text) async {
    await t.enterText(find.byKey(Keys.textEntryField), text);
    await t.tap(find.byKey(Keys.textEntryOk));
    await t.pumpAndSettle();
  }

  bool cancelHasFocus() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && find.descendant(of: find.byKey(PluginKeys.cancel), matching: find.byWidgetPredicate((w) => true)).evaluate().any((e) => e == ctx || _within(ctx, e));
  }

  testWidgets('empty page: nothing installed, both ways to add', (t) async {
    await open(t);
    expect(find.text('Nothing installed yet.'), findsOneWidget);
    expect(find.byKey(PluginKeys.addRepo), findsOneWidget);
    expect(find.byKey(PluginKeys.addSingle), findsOneWidget);
    expect(find.byKey(PluginKeys.unavailableBanner), findsNothing);
  });

  testWidgets('repo flow: the key is shown first, Cancel has focus, adult entries stay hidden, domains are listed', (t) async {
    await open(t);
    await t.tap(find.byKey(PluginKeys.addRepo));
    await t.pumpAndSettle();
    await ask(t, 'https://repo.example/plugins/plugins.json');

    expect(find.text('Trust this repository?'), findsOneWidget);
    expect(find.text('0102030405060708'), findsOneWidget);
    expect(find.text('Test repo'), findsOneWidget);
    expect(cancelHasFocus(), isTrue);
    expect(reg.installed.value, isEmpty);
    await t.tap(find.byKey(PluginKeys.trustContinue));
    await t.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.textContaining('Adulty'), findsNothing);
    expect(find.textContaining('1 more not shown: adult plugins are not supported'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(PluginKeys.pickNext)).onPressed, isNull); // pick something first
    await t.tap(find.byKey(PluginKeys.pick('alpha')));
    await t.pump();
    await t.tap(find.byKey(PluginKeys.pickNext));
    await t.pumpAndSettle();

    expect(find.text('Allow these sites?'), findsOneWidget);
    expect(find.textContaining('Alpha talks to alpha.example, cdn.alpha.example'), findsOneWidget);
    expect(cancelHasFocus(), isTrue);
    await t.tap(find.byKey(PluginKeys.installConfirm));
    await t.pumpAndSettle();
    expect(reg.log.last, 'install alpha firstUse=true');
    expect(find.byKey(PluginKeys.plugin('alpha')), findsOneWidget);
    expect(find.text('Not tested yet'), findsOneWidget);
  });

  testWidgets('cancelling the trust screen installs nothing', (t) async {
    await open(t);
    await t.tap(find.byKey(PluginKeys.addRepo));
    await t.pumpAndSettle();
    await ask(t, 'https://repo.example/plugins/');
    await t.tap(find.byKey(PluginKeys.cancel));
    await t.pumpAndSettle();
    expect(reg.log.where((l) => l.startsWith('install')), isEmpty);
  });

  testWidgets('a repo error is shown in words', (t) async {
    reg.previewError = PluginInstallError(InstallErrorKind.badSignature, 'The signature does not match this repository. It was not added.');
    await open(t);
    await t.tap(find.byKey(PluginKeys.addRepo));
    await t.pumpAndSettle();
    await ask(t, 'https://repo.example/plugins/');
    expect(find.text('Could not add the repository'), findsOneWidget);
    expect(find.textContaining('signature does not match'), findsOneWidget);
  });

  testWidgets('single .py: unsigned warning, domains, http warning, Cancel focused, then Install anyway', (t) async {
    await open(t);
    await t.tap(find.byKey(PluginKeys.addSingle));
    await t.pumpAndSettle();
    await ask(t, 'https://files.example/solo.py');
    expect(find.text('Install Solo?'), findsOneWidget);
    expect(find.text('Unsigned'), findsOneWidget);
    expect(find.textContaining('plain http'), findsOneWidget);
    final domains = t.widget<SelectableText>(find.byKey(const ValueKey('plugins-warning-domains'))).data!;
    expect(domains.split('\n'), ['img.solo.example', 'solo.example']);
    expect(cancelHasFocus(), isTrue);
    await t.tap(find.byKey(PluginKeys.installAnyway));
    await t.pumpAndSettle();
    expect(reg.installed.value.single.signed, isFalse);
    expect(find.textContaining('Unsigned'), findsOneWidget);
  });

  testWidgets('private plugin addresses: the refusal is shown', (t) async {
    reg.singleError = PluginInstallError(InstallErrorKind.privateOrIp,
        'The plugin names 192.168.1.5, a private or numeric address. Chithram only allows public sites.');
    await open(t);
    await t.tap(find.byKey(PluginKeys.addSingle));
    await t.pumpAndSettle();
    await ask(t, 'https://files.example/solo.py');
    expect(find.textContaining('private or numeric address'), findsOneWidget);
  });

  testWidgets('list shows status, the automatic update date and the approval badge; review shows the differences', (t) async {
    reg.installed.value = [
      reg.make('alpha', auto: DateTime.utc(2026, 10, 24, 12), canUndo: true, health: const PluginHealth(status: PluginHealthStatus.healthy)),
      reg.make('beta', pending: const PendingUpdate(version: '1.1', sha256: 'x', differences: ['Version: 1.0 to 1.1', 'Site changes from beta.example to beta-new.example'])),
    ];
    await open(t);
    expect(find.textContaining('Updated automatically 2026-10-24'), findsOneWidget);
    expect(find.textContaining('Update needs approval'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);

    await t.tap(find.byKey(PluginKeys.plugin('beta')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(PluginKeys.approveUpdate));
    await t.pumpAndSettle();
    expect(find.text('Update needs approval: Beta'), findsOneWidget);
    expect(find.text('Site changes from beta.example to beta-new.example'), findsOneWidget);
    expect(cancelHasFocus(), isTrue);
    await t.tap(find.byKey(PluginKeys.cancel));
    await t.pumpAndSettle();
    expect(reg.log.where((l) => l.startsWith('approve')), isEmpty);

    await t.tap(find.byKey(PluginKeys.plugin('beta')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(PluginKeys.approveUpdate));
    await t.pumpAndSettle();
    await t.tap(find.byKey(PluginKeys.approveUpdate)); // "Approve update" in the review dialog
    await t.pumpAndSettle();
    expect(reg.log.last, 'approve beta');
    expect(find.textContaining('Update needs approval'), findsNothing);

    // Undo is offered where the previous file is kept.
    await t.tap(find.byKey(PluginKeys.plugin('alpha')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(PluginKeys.undoUpdate));
    await t.pumpAndSettle();
    expect(reg.log.last, 'undo alpha');
  });

  testWidgets('test, disable and remove from the plugin dialog', (t) async {
    reg.installed.value = [reg.make('alpha'), reg.make('solo', signed: false)];
    await open(t);
    await t.tap(find.byKey(PluginKeys.plugin('alpha')));
    await t.pumpAndSettle();
    expect(find.byKey(PluginKeys.checkUpdate), findsNothing); // signed plugins update by themselves
    await t.tap(find.byKey(PluginKeys.testRun));
    await t.pumpAndSettle();
    await ask(t, 'Fixture Film 1');
    expect(find.text('1 result'), findsOneWidget);
    expect(find.textContaining('Fixture Film 1'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Healthy'), findsOneWidget);

    await t.tap(find.byKey(PluginKeys.plugin('alpha')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(PluginKeys.toggleEnabled));
    await t.pumpAndSettle();
    expect(reg.installed.value.first.enabled, isFalse);
    await t.tap(find.byKey(PluginKeys.remove));
    await t.pumpAndSettle();
    await t.tap(find.byKey(PluginKeys.removeConfirm));
    await t.pumpAndSettle();
    expect(reg.installed.value.map((p) => p.engineId), ['solo']);

    // Unsigned plugins have "Check for update".
    await t.tap(find.byKey(PluginKeys.plugin('solo')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(PluginKeys.checkUpdate));
    await t.pumpAndSettle();
    expect(reg.log.last, 'check solo');
    expect(find.text('Solo is up to date'), findsOneWidget);
  });

  testWidgets('removing a repository asks first and says what goes with it', (t) async {
    reg.installed.value = [reg.make('alpha'), reg.make('beta')];
    reg.repoViews.add(PluginRepoView(
        id: 'r1', url: 'https://repo.example/plugins/plugins.json', name: 'Test repo', keyId: '0102030405060708', lastCheckedAt: null, keyChanged: false, offers: const [], initialIds: const []));
    await open(t);
    expect(find.textContaining('not checked yet'), findsOneWidget);
    await t.tap(find.byTooltip('Remove repository'));
    await t.pumpAndSettle();
    expect(find.textContaining('also removes its 2 installed plugins and forgets its signing key'), findsOneWidget);
    expect(cancelHasFocus(), isTrue);
    await t.tap(find.byKey(PluginKeys.removeConfirm));
    await t.pumpAndSettle();
    expect(reg.installed.value, isEmpty);
    expect(find.text('Nothing installed yet.'), findsOneWidget);
  });

  testWidgets('a repository signed by another key says so; New plugins are offered', (t) async {
    reg.installed.value = [reg.make('alpha')];
    reg.repoViews.add(PluginRepoView(
      id: 'r1',
      url: 'https://repo.example/plugins/plugins.json',
      name: 'Test repo',
      keyId: '0102030405060708',
      lastCheckedAt: DateTime.utc(2026, 10, 24),
      keyChanged: true,
      offers: [RepoOffer(id: 'gamma', name: 'Gamma', version: '1.0', file: 'gamma.py', sha256: 'c' * 64, hosts: const [])],
      initialIds: const ['alpha'],
    ));
    await open(t);
    expect(find.textContaining('SIGNED BY A DIFFERENT KEY'), findsOneWidget);
    expect(find.text('New (1)'), findsOneWidget);
  });

  testWidgets('unavailable runtime: the banner says why', (t) async {
    reg.unavailable = 'This Linux kernel has no Landlock, so plugins cannot run safely here';
    await open(t);
    expect(find.byKey(PluginKeys.unavailableBanner), findsOneWidget);
    expect(find.textContaining('no Landlock'), findsOneWidget);
  });

  testWidgets('phone layout lays out without overflow', (t) async {
    reg.installed.value = [reg.make('alpha', auto: DateTime.utc(2026, 10, 24)), reg.make('solo', signed: false, health: const PluginHealth(status: PluginHealthStatus.failing))];
    await open(t, form: FormFactor.phone, size: const Size(421, 927));
    expect(t.takeException(), isNull);
    expect(find.byKey(PluginKeys.plugin('alpha')), findsOneWidget);
    await t.tap(find.byKey(PluginKeys.plugin('solo')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}

bool _within(BuildContext focus, Element e) {
  var found = false;
  focus.visitAncestorElements((a) {
    if (a == e) {
      found = true;
      return false;
    }
    return true;
  });
  return found || focus == e;
}

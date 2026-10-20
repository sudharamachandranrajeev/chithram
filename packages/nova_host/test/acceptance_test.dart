// Desktop acceptance: runs the fixture engines inside the real sandbox.
// Needs NOVA_PYTHON, NOVA_SANDBOX, NOVA_RUNNER_DIR (CI sets them); skipped otherwise.
@Timeout(Duration(minutes: 8))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

void main() {
  final env = Platform.environment;
  final python = env['NOVA_PYTHON'];
  final sandbox = env['NOVA_SANDBOX'];
  final runner = env['NOVA_RUNNER_DIR'];
  final enabled = python != null && sandbox != null && runner != null;
  final audit = env['NOVA_AUDIT'] != '0';
  final tag = 'audit=${audit ? 'on' : 'off'}';

  late final Map<String, CheckResult> results;
  setUpAll(() async {
    if (!enabled) return;
    final home = env['HOME'] ?? env['USERPROFILE']!;
    final cfg = LaunchConfig(
      python: python,
      runnerDir: runner,
      sandboxExe: sandbox,
      readOnlyPaths: [if (env['NOVA_PY_PREFIX'] != null) env['NOVA_PY_PREFIX']!],
      auditHook: audit,
      allowNoLandlock: env['NOVA_ALLOW_NO_LANDLOCK'] == '1',
    );
    final suite = AcceptanceSuite(
      start: () => ProcessSession.start(cfg),
      homeDir: home,
      tmpDir: Directory.systemTemp.path,
      log: (s) => stdout.writeln('NOVA $s'),
    );
    results = {for (final r in await suite.run()) r.name: r};
    final summary = StringBuffer('### nova acceptance ($tag, ${Platform.operatingSystem}, $python)\n\n| check | result | detail |\n|---|---|---|\n');
    for (final r in results.values) {
      summary.writeln('| ${r.name} | ${r.ok ? 'PASS' : 'FAIL'} | ${r.detail.replaceAll('|', '/').replaceAll('\n', ' ').replaceAll('\r', ' ')} |');
    }
    final f = env['NOVA_SUMMARY_FILE'];
    if (f != null) File(f).writeAsStringSync(summary.toString(), mode: FileMode.append);
  });

  for (final name in AcceptanceSuite.checkNames) {
    test('$name [$tag]', () {
      final r = results[name];
      expect(r, isNotNull);
      expect(r!.ok, isTrue, reason: r.detail);
    }, skip: enabled ? false : 'NOVA_PYTHON / NOVA_SANDBOX / NOVA_RUNNER_DIR not set');
  }
}

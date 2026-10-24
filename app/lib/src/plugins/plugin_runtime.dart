import 'dart:io';
import 'dart:typed_data';

import 'package:nova_host/nova_host.dart';

/// Runs plugins: `describe`, `search` and `downloadTorrent`, in the sandbox.
/// The registry talks to this; tests pass a fake.
abstract interface class PluginRunner {
  /// Why plugins cannot run on this device, once known (null: they can, or we
  /// have not tried yet).
  String? get unavailableReason;

  /// All three throw [PluginsUnavailable] when there is no runtime.
  Future<DescribeOutcome> describe(NovaEngine engine);
  Future<SearchOutcome> search(NovaEngine engine, String what, {String cat});
  Future<Uint8List> downloadTorrent(NovaEngine engine, String url);
}

/// The real thing: a [NovaHost] over a platform session (Android isolated
/// service, desktop sandbox launcher).
class NovaPluginRunner implements PluginRunner {
  NovaPluginRunner({required SessionStarter start, BrokerPolicy policy = const BrokerPolicy(), String? Function()? unavailable})
      : _host = NovaHost(start: start, policy: policy),
        _unavailable = unavailable;

  final NovaHost _host;
  final String? Function()? _unavailable;
  String? _reason;

  /// The stock runner for this platform; [broker] overrides the broker policy
  /// (the end-to-end builds use a test policy with fake DNS).
  factory NovaPluginRunner.forPlatform({BrokerPolicy broker = const BrokerPolicy(), Map<String, String>? env}) {
    if (Platform.isAndroid) {
      return NovaPluginRunner(
        start: () => AndroidNovaSession.start(),
        policy: broker,
        unavailable: () => AndroidNovaSession.disabledReason,
      );
    }
    final rt = DesktopNovaRuntime.locate(env: env);
    return NovaPluginRunner(start: rt.start, policy: broker, unavailable: () => rt.reason);
  }

  @override
  String? get unavailableReason => _reason ?? _unavailable?.call();

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PluginsUnavailable catch (e) {
      _reason = e.reason;
      rethrow;
    }
  }

  /// A sandbox launcher that cannot start says so on stderr; no Landlock is
  /// the one worth a clear message.
  T _noLandlock<T>(T outcome, String stderr, bool failed) {
    if (failed && stderr.contains('Landlock unavailable')) {
      _reason = 'This Linux kernel has no Landlock, so plugins cannot run safely here';
      throw PluginsUnavailable(_reason!);
    }
    return outcome;
  }

  @override
  Future<DescribeOutcome> describe(NovaEngine engine) => _guard(() async {
        final o = await _host.describe(engine);
        return _noLandlock(o, o.stderrHead, !o.ok);
      });

  @override
  Future<SearchOutcome> search(NovaEngine engine, String what, {String cat = 'all'}) => _guard(() async {
        final o = await _host.search(engine, what, cat: cat);
        return _noLandlock(o, o.stderrHead, o.status != SearchStatus.ok);
      });

  @override
  Future<Uint8List> downloadTorrent(NovaEngine engine, String url) =>
      _guard(() => _host.downloadTorrent(engine, url));
}

/// The plugin runtime next to the desktop app: `nova/python`, `nova/runtime`
/// and `nova/nova-sandbox`, placed there by the release builds. For development
/// and the end-to-end runs, `NOVA_PYTHON`, `NOVA_RUNNER_DIR`, `NOVA_SANDBOX` and
/// `NOVA_PY_PREFIX` point at them instead.
class DesktopNovaRuntime {
  DesktopNovaRuntime._({this.config, this.reason});

  final LaunchConfig? config;

  /// Why plugins are unavailable on this build; null when they are not.
  final String? reason;

  bool get available => config != null;

  Future<NovaSession> start() {
    final c = config;
    if (c == null) throw PluginsUnavailable(reason ?? 'The plugin runtime is not available');
    return ProcessSession.start(c);
  }

  static DesktopNovaRuntime locate({Map<String, String>? env, String? appDir}) {
    final e = env ?? Platform.environment;
    final win = Platform.isWindows;
    final python = e['NOVA_PYTHON'];
    if (python != null && e['NOVA_RUNNER_DIR'] != null) {
      return _make(python, e['NOVA_RUNNER_DIR']!, e['NOVA_SANDBOX'], e['NOVA_PY_PREFIX'], e);
    }
    final dir = appDir ?? File(Platform.resolvedExecutable).parent.path;
    final root = '$dir${Platform.pathSeparator}nova';
    String p(String rel) => '$root${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}';
    if (!Directory(root).existsSync()) {
      return DesktopNovaRuntime._(reason: 'This build does not include the plugin runtime');
    }
    return _make(p(win ? 'python/python.exe' : 'python/bin/python3'), p('runtime'), p(win ? 'nova-sandbox.exe' : 'nova-sandbox'),
        p('python'), e);
  }

  static DesktopNovaRuntime _make(String python, String runner, String? sandbox, String? prefix, Map<String, String> e) {
    if (!File(python).existsSync()) return DesktopNovaRuntime._(reason: 'The plugin runtime has no Python');
    if (!File('$runner${Platform.pathSeparator}runner.py').existsSync()) {
      return DesktopNovaRuntime._(reason: 'The plugin runtime has no runner');
    }
    if (sandbox == null || !File(sandbox).existsSync()) {
      return DesktopNovaRuntime._(reason: 'The plugin sandbox launcher is missing');
    }
    return DesktopNovaRuntime._(
      config: LaunchConfig(
        python: python,
        runnerDir: runner,
        sandboxExe: sandbox,
        readOnlyPaths: [if (prefix != null) prefix],
        allowNoLandlock: e['NOVA_ALLOW_NO_LANDLOCK'] == '1',
      ),
    );
  }
}

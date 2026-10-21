import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Hard limits enforced by the host on every runner, whatever the platform.
class NovaLimits {
  const NovaLimits({
    this.wall = const Duration(seconds: 30),
    this.maxLineBytes = 64 * 1024,
    this.maxStdoutBytes = 4 * 1024 * 1024,
    this.maxStderrBytes = 4 * 1024 * 1024,
    this.maxResults = 500,
    this.cpuSeconds = 20,
    this.memMiB = 512,
  });

  final Duration wall;
  final int maxLineBytes;
  final int maxStdoutBytes;
  final int maxStderrBytes;
  final int maxResults;
  final int cpuSeconds;
  final int memMiB;
}

/// A running plugin runner: NDJSON in both directions.
abstract class NovaSession {
  /// Runner -> host messages. Closed when the runner ends.
  Stream<Map<String, Object?>> get messages;

  void send(Map<String, Object?> message);

  /// Kills the runner. [reason] is kept in [killedReason].
  Future<void> kill(String reason);

  String? get killedReason;

  /// Captured stderr head plus anything the sandbox launcher said.
  String get stderrHead;

  /// Completes with the exit code (null when the platform has none).
  Future<int?> get exitCode;
}

class LaunchConfig {
  LaunchConfig({
    required this.python,
    required this.runnerDir,
    this.sandboxExe,
    this.readOnlyPaths = const [],
    this.auditHook = true,
    this.limits = const NovaLimits(),
    this.allowNoLandlock = false,
    this.insecureNoSandbox = false,
  }) {
    if (sandboxExe == null && !insecureNoSandbox) {
      throw ArgumentError('sandboxExe is required unless insecureNoSandbox is set (tests only)');
    }
  }

  final String python;
  final String runnerDir;
  final String? sandboxExe;

  /// Directories the interpreter must read: its prefix (stdlib) and anything else.
  /// [runnerDir] is added automatically.
  final List<String> readOnlyPaths;

  /// `false` runs the kernel/job layer without the Python audit hook (CI proves both).
  final bool auditHook;
  final NovaLimits limits;
  final bool allowNoLandlock;
  final bool insecureNoSandbox;

  String get runnerScript => '$runnerDir${Platform.pathSeparator}runner.py';

  (String, List<String>) command() {
    final py = [python, '-I', runnerScript];
    final exe = sandboxExe;
    if (exe == null) return (py.first, py.sublist(1));
    final args = <String>[
      for (final p in [runnerDir, ...readOnlyPaths]) ...['--ro', p],
      '--cwd', runnerDir,
      '--timeout', '${limits.wall.inSeconds}',
      '--mem', '${limits.memMiB}',
      '--cpu', '${limits.cpuSeconds}',
      if (allowNoLandlock) '--allow-no-landlock',
      '--',
      ...py,
    ];
    return (exe, args);
  }
}

class ProcessSession implements NovaSession {
  ProcessSession._(this._p, this.limits) {
    _timer = Timer(limits.wall + const Duration(seconds: 3), () => kill('wall-timeout'));
    _p.stdout.listen(_onStdout, onDone: _closeOut, onError: (_) => _closeOut());
    _p.stderr.listen(_onStderr, onError: (_) {});
    _p.exitCode.then((c) {
      _timer.cancel();
      _exit.complete(c);
      _closeOut();
    });
  }

  static Future<ProcessSession> start(LaunchConfig c) async {
    final (exe, args) = c.command();
    final p = await Process.start(exe, args,
        environment: {'NOVA_AUDIT': c.auditHook ? '1' : '0', 'PYTHONDONTWRITEBYTECODE': '1'},
        includeParentEnvironment: true);
    return ProcessSession._(p, c.limits);
  }

  final Process _p;
  final NovaLimits limits;
  late final Timer _timer;
  final _out = StreamController<Map<String, Object?>>();
  final _exit = Completer<int?>();
  final _lineBuf = <int>[];
  int _stdoutBytes = 0;
  int _stderrBytes = 0;
  final _stderrHead = StringBuffer();
  String? _killed;
  bool _outClosed = false;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  String? get killedReason => _killed;

  @override
  String get stderrHead => _stderrHead.toString();

  @override
  Future<int?> get exitCode => _exit.future;

  void _closeOut() {
    if (_outClosed) return;
    _outClosed = true;
    _out.close();
  }

  void _onStdout(List<int> data) {
    _stdoutBytes += data.length;
    if (_stdoutBytes > limits.maxStdoutBytes) {
      kill('stdout-limit');
      return;
    }
    for (final b in data) {
      if (b == 10) {
        _line();
      } else {
        _lineBuf.add(b);
        if (_lineBuf.length > limits.maxLineBytes) {
          kill('line-limit');
          return;
        }
      }
    }
  }

  void _line() {
    if (_lineBuf.isEmpty) return;
    try {
      final m = jsonDecode(utf8.decode(_lineBuf, allowMalformed: true));
      if (m is Map<String, Object?> && !_outClosed) _out.add(m);
    } on FormatException {
      kill('protocol-violation');
    } finally {
      _lineBuf.clear();
    }
  }

  void _onStderr(List<int> data) {
    _stderrBytes += data.length;
    if (_stderrHead.length < 4096) {
      _stderrHead.write(utf8.decode(data, allowMalformed: true).replaceAll('\u0000', ''));
    }
    if (_stderrBytes > limits.maxStderrBytes) kill('stderr-limit');
  }

  @override
  void send(Map<String, Object?> message) {
    if (_killed != null) return;
    try {
      _p.stdin.add(utf8.encode('${jsonEncode(message)}\n'));
    } catch (_) {}
  }

  @override
  Future<void> kill(String reason) async {
    _killed ??= reason;
    _p.kill(ProcessSignal.sigkill);
  }
}

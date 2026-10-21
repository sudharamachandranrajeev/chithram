import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:torrent/torrent.dart';

/// CI emulator job: build with these defines and the page streams file 0 by itself.
const String _autoMagnet = String.fromEnvironment('TORRENT_AUTOTEST_MAGNET');
const String _autoPeer = String.fromEnvironment('TORRENT_AUTOTEST_PEER');

bool get _desktop => Platform.isLinux || Platform.isWindows;

/// Torrent spike: paste a magnet, list files, stream one through the loopback URL.
/// Desktop plays it with media_kit; Android shows the URL and live stats (the
/// player spike is separate).
class TorrentSpikePage extends StatefulWidget {
  const TorrentSpikePage({super.key});

  @override
  State<TorrentSpikePage> createState() => _TorrentSpikePageState();
}

class _TorrentSpikePageState extends State<TorrentSpikePage> {
  final _magnet = TextEditingController();
  TorrentEngine? _engine;
  TorrentInfo? _info;
  TorrentStats? _stats;
  String _status = 'idle';
  String? _url;
  Timer? _poll;
  Player? _player;
  VideoController? _video;

  @override
  void initState() {
    super.initState();
    if (_autoMagnet.isNotEmpty) unawaited(_autotest());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _player?.dispose();
    _magnet.dispose();
    super.dispose();
  }

  Future<TorrentEngine> _ensureEngine() async {
    final e = _engine;
    if (e != null) return e;
    final dir = await Directory.systemTemp.createTemp('chithram_torrent');
    final started = await TorrentEngine.start(dir: dir.path, quotaBytes: 2 << 30);
    _engine = started;
    return started;
  }

  Future<void> _add() async {
    final m = _magnet.text.trim();
    if (m.isEmpty) return;
    setState(() => _status = 'starting engine and resolving metadata...');
    try {
      final e = await _ensureEngine();
      final info = await e.add(magnet: m);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
        try {
          final s = await e.stats(info.id);
          if (mounted) setState(() => _stats = s);
        } catch (_) {}
      });
      setState(() {
        _info = info;
        _status = 'ready: ${info.files.length} file(s)';
      });
    } catch (err) {
      setState(() => _status = 'error: $err');
    }
  }

  Future<void> _play(TorrentFile f) async {
    final e = _engine!;
    final url = e.streamUrl(_info!.id, f.index);
    setState(() => _url = url);
    if (!_desktop) return;
    try {
      MediaKit.ensureInitialized();
      _player ??= Player();
      _video ??= VideoController(_player!);
      await _player!.open(Media(url));
      setState(() {});
    } catch (err) {
      setState(() => _status = 'player error: $err');
    }
  }

  /// Unattended run for the emulator job: stream file 0 to the end, print markers for logcat.
  Future<void> _autotest() async {
    void log(String m) => debugPrint('TORRENT_AUTOTEST $m');
    try {
      final e = await _ensureEngine();
      log('engine port=${e.port}');
      final sw = Stopwatch()..start();
      final info = await e.add(
        magnet: _autoMagnet,
        peers: [if (_autoPeer.isNotEmpty) _autoPeer],
      );
      final f = info.files.first;
      log('added id=${info.id} files=${info.files.length} len=${f.length} t=${sw.elapsedMilliseconds}ms');
      final c = HttpClient();
      // Seek test first: last 1 MiB.
      final from = f.length - (1 << 20);
      var req = await c.getUrl(Uri.parse(e.streamUrl(info.id, f.index)));
      req.headers.set('Range', 'bytes=$from-${f.length - 1}');
      var res = await req.close();
      var n = 0;
      await for (final chunk in res) {
        n += chunk.length;
      }
      log('range status=${res.statusCode} bytes=$n t=${sw.elapsedMilliseconds}ms');
      // Full pass.
      req = await c.getUrl(Uri.parse(e.streamUrl(info.id, f.index)));
      res = await req.close();
      n = 0;
      await for (final chunk in res) {
        n += chunk.length;
      }
      log('full status=${res.statusCode} bytes=$n expected=${f.length} t=${sw.elapsedMilliseconds}ms');
      // Bad token must be refused.
      req = await c.getUrl(Uri.parse('http://127.0.0.1:${e.port}/deadbeef/health'));
      res = await req.close();
      await res.drain<void>();
      log('badtoken status=${res.statusCode}');
      c.close();
      log(n == f.length ? 'RESULT PASS' : 'RESULT FAIL size mismatch');
    } catch (err, st) {
      log('RESULT FAIL $err\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final s = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('Spike: torrent')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _magnet,
                  decoration: const InputDecoration(labelText: 'magnet:?xt=urn:btih:...'),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: _add, child: const Text('Add')),
            ]),
            const SizedBox(height: 8),
            Text(_status),
            if (s != null)
              Text(
                '${s.state}  ${s.progressBytes ~/ (1 << 20)} / ${s.totalBytes ~/ (1 << 20)} MiB'
                '  ${s.downloadMibPerSec?.toStringAsFixed(2) ?? '-'} MiB/s'
                '${s.error == null ? '' : '  error: ${s.error}'}',
              ),
            if (_url != null) SelectableText(_url!),
            const SizedBox(height: 8),
            if (_video != null)
              AspectRatio(aspectRatio: 16 / 9, child: Video(controller: _video!)),
            if (info != null)
              Expanded(
                child: ListView(
                  children: [
                    for (final f in info.files)
                      ListTile(
                        dense: true,
                        title: Text(f.path),
                        subtitle: Text('${f.length ~/ (1 << 20)} MiB'),
                        enabled: f.streamable,
                        onTap: f.streamable ? () => _play(f) : null,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';

import '../core/item_id.dart';
import '../core/redact.dart';
import '../core/services.dart';
import '../features/youtube/youtube_service.dart';
import '../player/play_request.dart';

/// Something a user handed us: typed or pasted text, a LocalSend message, a
/// `.torrent` file. Later also Android intents and desktop arguments.
sealed class IntakePayload {}

final class TextPayload extends IntakePayload {
  TextPayload(this.text, {this.from});

  final String text;

  /// Who sent it, for the confirmation ("Phone").
  final String? from;
}

final class TorrentFilePayload extends IntakePayload {
  TorrentFilePayload(this.bytes, this.name, {this.from});

  final Uint8List bytes;
  final String name;
  final String? from;
}

enum IntakeKind { youtube, magnet, torrentUrl, playlistUrl, mediaUrl, ambiguousM3u8, text }

final _btih = RegExp(r'xt=urn:btih:([0-9a-fA-F]{40}|[A-Za-z2-7]{32})(&|$)');
const _mediaExtensions = {
  'mp4', 'mkv', 'webm', 'avi', 'mov', 'ts', 'mpd', 'mp3', 'm4a', 'flac', 'ogg', 'opus', //
};

/// Decides what a piece of text is. Pure; never touches the network. Schemes
/// that could run code or read local files (`javascript:`, `file:`,
/// `content:`, `intent:`) are plain text.
IntakeKind classify(String text) {
  final t = text.trim();
  if (t.isEmpty || t.contains(RegExp(r'\s'))) return IntakeKind.text;
  if (t.toLowerCase().startsWith('magnet:?')) {
    return _btih.hasMatch(t) ? IntakeKind.magnet : IntakeKind.text;
  }
  final uri = Uri.tryParse(t);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    return IntakeKind.text;
  }
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (host == 'youtu.be') return uri.pathSegments.isEmpty ? IntakeKind.text : IntakeKind.youtube;
  if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
    final video = path == '/watch' && (uri.queryParameters['v'] ?? '').isNotEmpty;
    return video || path.startsWith('/shorts/') || path.startsWith('/live/')
        ? IntakeKind.youtube
        : IntakeKind.text;
  }
  if (path.endsWith('.torrent')) return IntakeKind.torrentUrl;
  if (path.endsWith('.m3u')) return IntakeKind.playlistUrl;
  if (path.endsWith('get.php') && (uri.queryParameters['type'] ?? '').startsWith('m3u')) {
    return IntakeKind.playlistUrl;
  }
  if (path.endsWith('.m3u8')) return IntakeKind.ambiguousM3u8;
  final dot = path.lastIndexOf('.');
  if (dot >= 0 && _mediaExtensions.contains(path.substring(dot + 1))) return IntakeKind.mediaUrl;
  return IntakeKind.text;
}

String _actionLabel(IntakeKind kind) => switch (kind) {
      IntakeKind.youtube => 'Play YouTube video',
      IntakeKind.magnet || IntakeKind.torrentUrl => 'Open torrent',
      IntakeKind.playlistUrl => 'Add playlist',
      IntakeKind.mediaUrl || IntakeKind.ambiguousM3u8 => 'Play link',
      IntakeKind.text => 'Close',
    };

/// Shows what arrived (credentials masked) and what Chithram would do with it,
/// then routes to the matching screen. Nothing starts without that
/// confirmation. Stub: the routes to the torrent file list and to the
/// receive-side handlers are filled in by the feature work packages.
Future<void> handleIntake(BuildContext context, IntakePayload p) async {
  final String shown;
  final IntakeKind kind;
  switch (p) {
    case TextPayload(:final text):
      kind = classify(text);
      shown = maskUrlCredentials(text.trim());
    case TorrentFilePayload(:final name):
      kind = IntakeKind.magnet;
      shown = name;
  }
  final from = switch (p) {
    TextPayload(:final from) => from,
    TorrentFilePayload(:final from) => from,
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(from == null ? 'Received a link' : 'From $from'),
      content: Text(shown.length > 200 ? '${shown.substring(0, 200)}...' : shown),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        if (kind != IntakeKind.text)
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(_actionLabel(kind))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final services = AppServices.of(context);
  try {
    await _route(context, services, kind, p);
  } on UnimplementedError {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not available yet')));
    }
  }
}

Future<void> _route(BuildContext context, AppServices services, IntakeKind kind, IntakePayload p) async {
  switch (kind) {
    case IntakeKind.playlistUrl:
      await services.iptv.openAddPlaylist(context, url: (p as TextPayload).text.trim());
    case IntakeKind.mediaUrl || IntakeKind.ambiguousM3u8:
      final url = (p as TextPayload).text.trim();
      await openPlayer(
        context,
        PlayRequest(
          itemId: ItemId.url(url),
          title: Uri.parse(url).host,
          resolve: () async => MediaSpec(videoUrl: url),
        ),
      );
    case IntakeKind.youtube:
      final videoId = YouTubeService.videoIdFromUrl((p as TextPayload).text.trim());
      if (videoId == null) return;
      final request = await services.youtube.playRequestForId(videoId);
      if (context.mounted) await openPlayer(context, request);
    case IntakeKind.torrentUrl:
      // Fetching the .torrent (2 MiB cap) arrives with the receive work package.
      throw UnimplementedError('torrent URL');
    case IntakeKind.magnet:
      // Network choice, the file list and playback: the torrents work package.
      if (!await services.torrents.ensureNetworkChoice(context) || !context.mounted) return;
      final info = p is TextPayload
          ? await services.torrents.addMagnet(p.text.trim())
          : await services.torrents.addTorrentBytes((p as TorrentFilePayload).bytes);
      if (context.mounted) await services.torrents.openFiles(context, info);
    case IntakeKind.text:
      break;
  }
}


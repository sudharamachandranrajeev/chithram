import 'dart:convert';
import 'dart:typed_data';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';
import 'package:localsend_rx/localsend_rx.dart' show looksLikeTorrent, maxTorrentBytes;

import '../core/item_id.dart';
import '../core/services.dart';
import '../features/youtube/youtube_service.dart';
import '../player/play_request.dart';
import 'fetch.dart';
import 'summary.dart';

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

/// Features that live outside this package plug in here.
abstract final class IntakeHooks {
  /// Opens search for a piece of text. Unset until the search page provides
  /// it; while it is unset, plain text offers no action.
  static Future<void> Function(BuildContext context, String text)? search;
}

/// The button text for [kind], or null when Chithram would do nothing with it.
String? intakeActionLabel(IntakeKind kind) => switch (kind) {
      IntakeKind.youtube => 'Play YouTube video',
      IntakeKind.magnet || IntakeKind.torrentUrl => 'Open torrent',
      IntakeKind.playlistUrl => 'Add playlist',
      IntakeKind.mediaUrl || IntakeKind.ambiguousM3u8 => 'Play link',
      IntakeKind.text => IntakeHooks.search == null ? null : 'Search for this text',
    };

/// What kind of thing [p] is.
IntakeKind intakeKind(IntakePayload p) => switch (p) {
      TextPayload(:final text) => classify(text),
      TorrentFilePayload() => IntakeKind.magnet,
    };

/// Shows what arrived (credentials masked) and what Chithram would do with it,
/// then routes to the matching screen. Nothing starts without that
/// confirmation, and nothing plays: the handler's own screen needs one more
/// press. [confirmed] skips the dialog when the user already chose the action
/// in the receive prompt.
Future<void> handleIntake(BuildContext context, IntakePayload p, {bool confirmed = false}) async {
  final kind = intakeKind(p);
  final action = intakeActionLabel(kind);
  final from = switch (p) {
    TextPayload(:final from) => from,
    TorrentFilePayload(:final from) => from,
  };
  if (!confirmed) {
    final shown = switch (p) {
      TextPayload(:final text) => text,
      TorrentFilePayload(:final name) => name,
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(from == null ? 'Received a link' : 'From $from'),
        content: IntakeSummary(shown),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          if (action != null) FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(action)),
        ],
      ),
    );
    if (ok != true) return;
  } else if (action == null) {
    return;
  }
  if (!context.mounted) return;
  final services = AppServices.of(context);
  try {
    await _route(context, services, kind, p);
  } on UnimplementedError {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not available yet')));
    }
  }
}

void _say(BuildContext context, String message) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _playLink(BuildContext context, String url) {
  return openPlayer(
    context,
    PlayRequest(
      itemId: ItemId.url(url),
      title: Uri.parse(url).host,
      resolve: () async => MediaSpec(videoUrl: url),
    ),
  );
}

Future<void> _openTorrent(BuildContext context, AppServices services, IntakePayload p) async {
  // Network choice, the file list and playback belong to the torrents screens.
  if (!await services.torrents.ensureNetworkChoice(context) || !context.mounted) return;
  final info = p is TextPayload
      ? await services.torrents.addMagnet(p.text.trim())
      : await services.torrents.addTorrentBytes((p as TorrentFilePayload).bytes);
  if (context.mounted) await services.torrents.openFiles(context, info);
}

/// Two or more `#EXTINF` entries each followed by a URL line: a playlist.
bool _looksLikePlaylist(String head) {
  final lines = const LineSplitter().convert(head);
  var entries = 0;
  for (var i = 0; i + 1 < lines.length; i++) {
    if (lines[i].startsWith('#EXTINF') && !lines[i + 1].startsWith('#') && lines[i + 1].trim().isNotEmpty) {
      entries++;
    }
  }
  return entries >= 2;
}

Future<void> _route(BuildContext context, AppServices services, IntakeKind kind, IntakePayload p) async {
  switch (kind) {
    case IntakeKind.playlistUrl:
      await services.iptv.openAddPlaylist(context, url: (p as TextPayload).text.trim());
    case IntakeKind.mediaUrl:
      await _playLink(context, (p as TextPayload).text.trim());
    case IntakeKind.ambiguousM3u8:
      // A stream (#EXT-X-) plays; a list of channels is added as a playlist.
      // If it cannot be read, the player reports that with a Retry.
      final url = (p as TextPayload).text.trim();
      final head = await intakeFetch(Uri.parse(url), maxBytes: 64 * 1024, timeout: const Duration(seconds: 5), truncate: true);
      final text = head == null ? '' : utf8.decode(head, allowMalformed: true);
      if (!context.mounted) return;
      if (!text.contains('#EXT-X-') && _looksLikePlaylist(text)) {
        await services.iptv.openAddPlaylist(context, url: url);
      } else {
        await _playLink(context, url);
      }
    case IntakeKind.youtube:
      final videoId = YouTubeService.videoIdFromUrl((p as TextPayload).text.trim());
      if (videoId == null) return;
      final request = await services.youtube.playRequestForId(videoId);
      if (context.mounted) await openPlayer(context, request);
    case IntakeKind.torrentUrl:
      final url = (p as TextPayload).text.trim();
      final bytes = await intakeFetch(Uri.parse(url), maxBytes: maxTorrentBytes, timeout: const Duration(seconds: 15));
      if (!context.mounted) return;
      if (bytes == null || !looksLikeTorrent(bytes)) {
        _say(context, 'That link is not a torrent file');
        return;
      }
      await _openTorrent(context, services, TorrentFilePayload(bytes, Uri.parse(url).pathSegments.last));
    case IntakeKind.magnet:
      await _openTorrent(context, services, p);
    case IntakeKind.text:
      final search = IntakeHooks.search;
      if (search != null) await search(context, (p as TextPayload).text.trim());
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/foundation.dart';
import 'package:web_media/web_media.dart';

import '../../core/item_id.dart';
import '../../player/play_request.dart';

/// A site the user added to Websites.
class SavedWebsite {
  const SavedWebsite({required this.url, required this.name});

  factory SavedWebsite.fromJson(Map<String, dynamic> j) =>
      SavedWebsite(url: Uri.parse(j['url'] as String), name: j['name'] as String? ?? '');

  final Uri url;
  final String name;

  Map<String, dynamic> toJson() => {'url': url.toString(), 'name': name};
}

/// Why [text] cannot be added as a website, or null.
String? websiteUrlProblem(String text) {
  final u = Uri.tryParse(text.trim());
  if (u == null || !u.hasScheme || u.host.isEmpty) return 'That is not a web address.';
  if (u.scheme != 'http' && u.scheme != 'https') return 'Only http and https sites can be added.';
  return null;
}

/// Websites: the sites the user added (`websites.json`), reading their pages
/// for video, and playing it in Chithram's own player. Pages are read as
/// text and never run, so the sites' ads, pop-ups and scripts never load;
/// HLS streams go through [HlsAdProxy] so ad breaks inside them are cut.
class WebsitesService extends ChangeNotifier {
  WebsitesService({File? file, WebMediaResolver? resolver, HlsAdProxy? proxy})
      : _file = file,
        resolver = resolver ?? WebMediaResolver(),
        _proxy = proxy ?? HlsAdProxy();

  /// Null keeps the list in memory only (tests).
  final File? _file;
  final WebMediaResolver resolver;
  final HlsAdProxy _proxy;
  List<SavedWebsite>? _sites;

  /// Loads on first use.
  Future<List<SavedWebsite>> sites() async => List.unmodifiable(_sites ??= await _load());

  Future<List<SavedWebsite>> _load() async {
    final file = _file;
    if (file == null) return [];
    try {
      if (!await file.exists()) return [];
      final j = jsonDecode(await file.readAsString());
      return [for (final e in (j as List).whereType<Map>()) SavedWebsite.fromJson(e.cast<String, dynamic>())];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final s in _sites!) s.toJson()]));
    await tmp.rename(file.path);
  }

  /// Adds (or renames) the site at [url].
  Future<void> add(Uri url, String name) async {
    final list = (_sites ??= await _load())..removeWhere((s) => s.url == url);
    list.add(SavedWebsite(url: url, name: name.trim().isEmpty ? url.host : name.trim()));
    await _save();
    notifyListeners();
  }

  Future<void> remove(Uri url) async {
    (_sites ??= await _load()).removeWhere((s) => s.url == url);
    await _save();
    notifyListeners();
  }

  /// Plays [media] found on a page titled [title].
  PlayRequest playRequest(MediaCandidate media, {required String title}) => PlayRequest(
        itemId: ItemId.url(media.url.toString()),
        title: title,
        subtitle: media.referer.host,
        resolve: () async {
          final url = media.kind == MediaKind.hls ? await _proxy.wrap(media.url, media.headers) : media.url;
          return MediaSpec(videoUrl: url.toString(), headers: media.headers);
        },
      );
}

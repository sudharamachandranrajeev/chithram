import 'dart:convert';
import 'dart:typed_data';

/// Limits from the receive policy.
const maxMessageBytes = 64 * 1024;
const maxTorrentBytes = 2 * 1024 * 1024;
const maxPrepareBodyBytes = 256 * 1024;
const maxRegisterBodyBytes = 16 * 1024;
const maxFiles = 16;

/// The protocol version we announce.
const protocolVersion = '2.1';
const apiBase = '/api/localsend/v2';

/// What an accepted file is for.
enum FileKind {
  /// Text sent inline in `preview`; nothing is uploaded.
  message,

  /// A `.txt` upload of at most 64 KiB.
  textFile,

  /// A `.torrent` upload of at most 2 MiB.
  torrent,
}

/// Strips control characters and caps the length, so a sender cannot fake a
/// prompt with newlines or flood it.
String cleanLabel(Object? v, {int max = 64}) {
  if (v is! String) return '';
  final out = StringBuffer();
  for (final c in v.runes) {
    final control = c < 0x20 || (c >= 0x7f && c <= 0x9f);
    // Line and paragraph separators and the bidirectional overrides.
    final spoof = c == 0x2028 || c == 0x2029 || (c >= 0x202a && c <= 0x202e) || (c >= 0x2066 && c <= 0x2069);
    out.writeCharCode(control || spoof ? 0x20 : c);
  }
  final s = out.toString().trim();
  return s.length > max ? s.substring(0, max) : s;
}

/// The sender's own description in `prepare-upload` and `register`.
class PeerInfo {
  const PeerInfo({required this.alias, required this.fingerprint, this.model});

  final String alias;
  final String fingerprint;
  final String? model;

  /// Null when the map is not a usable peer description.
  static PeerInfo? parse(Object? j) {
    if (j is! Map) return null;
    final alias = cleanLabel(j['alias']);
    final version = j['version'];
    if (alias.isEmpty || version is! String || !version.startsWith('2.')) return null;
    final fp = j['fingerprint'];
    if (fp is! String || fp.isEmpty || fp.length > 128) return null;
    final model = cleanLabel(j['deviceModel']);
    return PeerInfo(alias: alias, fingerprint: fp, model: model.isEmpty ? null : model);
  }
}

/// One file in an offer that passed the policy.
class AcceptedFile {
  AcceptedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.type,
    required this.kind,
    this.preview,
    this.sha256,
  });

  final String id;
  final String name;
  final int size;
  final String type;
  final FileKind kind;
  final String? preview;
  final String? sha256;

  /// Set by the receiver when the offer is accepted.
  String token = '';
  bool uploaded = false;
}

final _fileId = RegExp(r'^[A-Za-z0-9_.:-]{1,128}$');
final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

/// Decides whether one offered file is something Chithram takes. Null means
/// no: anything but text, `.txt` and `.torrent`, or over the size caps.
AcceptedFile? acceptFile(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final name = cleanLabel(j['fileName'], max: 200);
  final size = j['size'];
  final type = (j['fileType'] is String ? j['fileType'] as String : '').toLowerCase();
  if (id is! String || !_fileId.hasMatch(id) || name.isEmpty || size is! int || size < 0) return null;
  final preview = j['preview'];
  final sha = j['sha256'];
  final shaOk = sha is String && _hex64.hasMatch(sha) ? sha.toLowerCase() : null;
  final lower = name.toLowerCase();
  AcceptedFile make(FileKind kind, {String? preview}) => AcceptedFile(
        id: id,
        name: name,
        size: size,
        type: type,
        kind: kind,
        preview: preview,
        sha256: shaOk,
      );

  if (lower.endsWith('.torrent')) {
    return size >= 1 && size <= maxTorrentBytes ? make(FileKind.torrent) : null;
  }
  final plain = type.split(';').first.trim() == 'text/plain';
  if (preview is String) {
    if (!plain || preview.isEmpty || utf8.encode(preview).length > maxMessageBytes) return null;
    return make(FileKind.message, preview: preview);
  }
  if (lower.endsWith('.txt') && size >= 1 && size <= maxMessageBytes) return make(FileKind.textFile);
  return null;
}

/// A `.torrent` is a bencoded dictionary with an `info` key.
bool looksLikeTorrent(Uint8List b) {
  if (b.isEmpty || b[0] != 0x64) return false;
  const needle = [0x34, 0x3a, 0x69, 0x6e, 0x66, 0x6f]; // 4:info
  outer:
  for (var i = 1; i + needle.length <= b.length; i++) {
    for (var k = 0; k < needle.length; k++) {
      if (b[i + k] != needle[k]) continue outer;
    }
    return true;
  }
  return false;
}

/// The few TDLib objects Chithram reads, as typed Dart. Everything else in
/// TDLib's JSON is ignored.
library;

/// An `error` object from TDLib.
class TdError implements Exception {
  const TdError(this.code, this.message);

  factory TdError.fromJson(Map<String, dynamic> j) =>
      TdError((j['code'] as num?)?.toInt() ?? 0, '${j['message'] ?? 'unknown error'}');

  final int code;
  final String message;

  @override
  String toString() => 'TdError($code): $message';
}

/// Where sign-in stands (`AuthorizationState*`).
sealed class TgAuthState {
  const TgAuthState();

  /// The state for a TDLib `authorizationState*` object.
  factory TgAuthState.fromJson(Map<String, dynamic> j) {
    switch (j['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        return const TgAuthWaitParameters();
      case 'authorizationStateWaitPhoneNumber':
        return const TgAuthWaitPhone();
      case 'authorizationStateWaitOtherDeviceConfirmation':
        return TgAuthWaitQr('${j['link'] ?? ''}');
      case 'authorizationStateWaitCode':
        final info = j['code_info'];
        return TgAuthWaitCode(info is Map ? '${info['phone_number'] ?? ''}' : '');
      case 'authorizationStateWaitPassword':
        return TgAuthWaitPassword('${j['password_hint'] ?? ''}');
      case 'authorizationStateReady':
        return const TgAuthReady();
      case 'authorizationStateLoggingOut':
        return const TgAuthLoggingOut();
      case 'authorizationStateClosing':
        return const TgAuthClosing();
      case 'authorizationStateClosed':
        return const TgAuthClosed();
      default:
        // Registration, e-mail and premium-purchase steps: not supported.
        return TgAuthUnsupported('${j['@type']}');
    }
  }
}

class TgAuthWaitParameters extends TgAuthState {
  const TgAuthWaitParameters();
}

class TgAuthWaitPhone extends TgAuthState {
  const TgAuthWaitPhone();
}

/// Show [link] (`tg://login?token=...`) as a QR code; the phone's Telegram app
/// scans it.
class TgAuthWaitQr extends TgAuthState {
  const TgAuthWaitQr(this.link);
  final String link;
}

class TgAuthWaitCode extends TgAuthState {
  const TgAuthWaitCode(this.phoneNumber);
  final String phoneNumber;
}

class TgAuthWaitPassword extends TgAuthState {
  const TgAuthWaitPassword(this.hint);
  final String hint;
}

class TgAuthReady extends TgAuthState {
  const TgAuthReady();
}

class TgAuthLoggingOut extends TgAuthState {
  const TgAuthLoggingOut();
}

class TgAuthClosing extends TgAuthState {
  const TgAuthClosing();
}

class TgAuthClosed extends TgAuthState {
  const TgAuthClosed();
}

class TgAuthUnsupported extends TgAuthState {
  const TgAuthUnsupported(this.type);
  final String type;
}

/// A TDLib `file` as the downloader sees it.
class TgFile {
  const TgFile({
    required this.id,
    required this.size,
    this.path = '',
    this.canDownload = true,
    this.isDownloading = false,
    this.isComplete = false,
    this.downloadOffset = 0,
    this.prefixSize = 0,
    this.downloadedSize = 0,
  });

  factory TgFile.fromJson(Map<String, dynamic> j) {
    final local = (j['local'] as Map?)?.cast<String, dynamic>() ?? const {};
    final size = (j['size'] as num?)?.toInt() ?? 0;
    final expected = (j['expected_size'] as num?)?.toInt() ?? 0;
    return TgFile(
      id: (j['id'] as num).toInt(),
      size: size > 0 ? size : expected,
      path: '${local['path'] ?? ''}',
      canDownload: local['can_be_downloaded'] != false,
      isDownloading: local['is_downloading_active'] == true,
      isComplete: local['is_downloading_completed'] == true,
      downloadOffset: (local['download_offset'] as num?)?.toInt() ?? 0,
      prefixSize: (local['downloaded_prefix_size'] as num?)?.toInt() ?? 0,
      downloadedSize: (local['downloaded_size'] as num?)?.toInt() ?? 0,
    );
  }

  final int id;

  /// Bytes in the whole file (the expected size while it is unknown).
  final int size;
  final String path;
  final bool canDownload;
  final bool isDownloading;
  final bool isComplete;

  /// Where the active download started, and how many contiguous bytes from
  /// there are on disk.
  final int downloadOffset;
  final int prefixSize;

  /// All bytes on disk, contiguous or not.
  final int downloadedSize;

  /// True when bytes `[offset, offset + length)` can be read now.
  bool covers(int offset, int length) {
    if (isComplete) return true;
    return offset >= downloadOffset && offset + length <= downloadOffset + prefixSize;
  }

  TgFile copyWith({int? size, bool? isComplete, int? downloadOffset, int? prefixSize, bool? isDownloading, int? downloadedSize}) =>
      TgFile(
        id: id,
        size: size ?? this.size,
        path: path,
        canDownload: canDownload,
        isDownloading: isDownloading ?? this.isDownloading,
        isComplete: isComplete ?? this.isComplete,
        downloadOffset: downloadOffset ?? this.downloadOffset,
        prefixSize: prefixSize ?? this.prefixSize,
        downloadedSize: downloadedSize ?? this.downloadedSize,
      );
}

enum TgMediaKind { video, audio, document }

/// A message in Saved Messages that carries a playable file.
class TgMedia {
  const TgMedia({
    required this.chatId,
    required this.messageId,
    required this.date,
    required this.kind,
    required this.name,
    required this.mime,
    required this.file,
    this.duration = 0,
  });

  final int chatId;
  final int messageId;

  /// When the message was sent.
  final DateTime date;
  final TgMediaKind kind;
  final String name;
  final String mime;
  final TgFile file;
  final int duration;

  int get fileId => file.id;

  /// Reads a `message` and returns its media, or null when it is not a video,
  /// an audio file, or a document that is video or audio (by mime type, else
  /// by file extension).
  static TgMedia? fromMessage(Map<String, dynamic> m) {
    final content = (m['content'] as Map?)?.cast<String, dynamic>();
    if (content == null) return null;
    final chatId = (m['chat_id'] as num?)?.toInt() ?? 0;
    final id = (m['id'] as num?)?.toInt() ?? 0;
    final date = DateTime.fromMillisecondsSinceEpoch(((m['date'] as num?)?.toInt() ?? 0) * 1000, isUtc: true);
    TgMedia? build(TgMediaKind kind, Map? obj, Map? file) {
      if (obj == null || file == null) return null;
      final name = '${obj['file_name'] ?? ''}';
      final mime = '${obj['mime_type'] ?? ''}';
      final f = TgFile.fromJson(file.cast<String, dynamic>());
      final label = name.isNotEmpty ? name : _fallbackName(kind, obj, f.id, mime);
      return TgMedia(
        chatId: chatId,
        messageId: id,
        date: date,
        kind: kind,
        name: label,
        mime: mime,
        file: f,
        duration: (obj['duration'] as num?)?.toInt() ?? 0,
      );
    }

    switch (content['@type']) {
      case 'messageVideo':
        final v = (content['video'] as Map?);
        return build(TgMediaKind.video, v, v?['video'] as Map?);
      case 'messageAudio':
        final a = (content['audio'] as Map?);
        final media = build(TgMediaKind.audio, a, a?['audio'] as Map?);
        if (media == null || a == null) return media;
        // Music is often sent without a file name: use the tags.
        final title = '${a['title'] ?? ''}';
        final artist = '${a['performer'] ?? ''}';
        if ('${a['file_name'] ?? ''}'.isEmpty && title.isNotEmpty) {
          return media._named(artist.isEmpty ? title : '$artist - $title');
        }
        return media;
      case 'messageDocument':
        final d = (content['document'] as Map?);
        final media = build(TgMediaKind.document, d, d?['document'] as Map?);
        if (media == null) return null;
        return isMediaDocument(media.mime, media.name) ? media : null;
      default:
        return null;
    }
  }

  TgMedia _named(String name) => TgMedia(
        chatId: chatId,
        messageId: messageId,
        date: date,
        kind: kind,
        name: name,
        mime: mime,
        file: file,
        duration: duration,
      );

  static String _fallbackName(TgMediaKind kind, Map obj, int id, String mime) {
    final ext = switch (mime) {
      'video/mp4' => 'mp4',
      'video/x-matroska' => 'mkv',
      'video/webm' => 'webm',
      'audio/mpeg' => 'mp3',
      'audio/mp4' || 'audio/x-m4a' => 'm4a',
      'audio/ogg' => 'ogg',
      'audio/flac' => 'flac',
      _ => kind == TgMediaKind.audio ? 'mp3' : 'mp4',
    };
    return '${kind == TgMediaKind.audio ? 'audio' : 'video'}-$id.$ext';
  }

  /// A document counts when its mime type is video/* or audio/*, or its
  /// extension is a known media one (Telegram often labels files
  /// `application/octet-stream`).
  static bool isMediaDocument(String mime, String name) {
    final m = mime.toLowerCase();
    if (m.startsWith('video/') || m.startsWith('audio/')) return true;
    final dot = name.lastIndexOf('.');
    return dot >= 0 && mediaExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  static const mediaExtensions = {
    'mkv', 'mp4', 'm4v', 'mov', 'avi', 'webm', 'ts', 'm2ts', 'mpg', 'mpeg', 'wmv', 'flv', '3gp', 'ogv',
    'mp3', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'opus', 'wav', 'wma',
  };
}

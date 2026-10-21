/// LocalSend v2 receiver, implemented from the public protocol description.
///
/// HTTPS server and multicast discovery bound to private networks only; takes
/// text, `.txt` and `.torrent` after the user agrees to each transfer. Nothing
/// is written to disk.
library;

export 'src/identity.dart';
export 'src/models.dart';
export 'src/net.dart' show isPrivateV4;
export 'src/protocol.dart' show maxMessageBytes, maxTorrentBytes, maxFiles, protocolVersion, looksLikeTorrent;
export 'src/receiver.dart';

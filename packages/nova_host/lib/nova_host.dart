/// Chithram nova host: sandboxed qBittorrent-style (nova3) search plugins.
///
/// The Python runner has no network. This package brokers its HTTP with a
/// per-engine allowlist, verifies signed plugin repos (minisign, TOFU pin) and
/// launches the runner inside the platform sandbox.
library;

export 'src/blake2b.dart' show blake2b512;
export 'src/broker.dart';
export 'src/domains.dart';
export 'src/ed25519.dart' show ed25519Verify;
export 'src/host.dart';
export 'src/minisign.dart';
export 'src/repo.dart';
export 'src/session.dart';
export 'src/suite.dart';
export 'src/fixtures.g.dart' show novaFixtures;
export 'src/android_session.dart';

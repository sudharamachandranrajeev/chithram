import '../core/secrets.dart';

/// Where the device token lives. Only secure storage: never prefs, files,
/// logs or URLs.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

const _tokenKey = 'media.deviceToken';

/// The real store: the app's [SecretStore] (flutter_secure_storage).
class SecretTokenStore implements TokenStore {
  SecretTokenStore(this._secrets);

  final SecretStore _secrets;

  @override
  Future<String?> read() => _secrets.read(_tokenKey);

  @override
  Future<void> write(String token) => _secrets.write(_tokenKey, token);

  @override
  Future<void> clear() => _secrets.delete(_tokenKey);
}

/// Nothing persists. For tests and previews.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

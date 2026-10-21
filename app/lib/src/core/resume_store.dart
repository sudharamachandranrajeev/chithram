/// Remembers where each item stopped. The JSON implementation lands with the
/// player work package; the database replaces it in 0.3.0.
abstract interface class ResumeStore {
  Future<Duration?> get(String itemId);
  Future<void> put(String itemId, Duration pos, Duration dur);
  Future<void> clear(String itemId);
}

/// Keeps positions for the life of the process. For tests, and the default
/// until the JSON store is wired.
class MemoryResumeStore implements ResumeStore {
  final _positions = <String, Duration>{};

  @override
  Future<Duration?> get(String itemId) async => _positions[itemId];

  @override
  Future<void> put(String itemId, Duration pos, Duration dur) async => _positions[itemId] = pos;

  @override
  Future<void> clear(String itemId) async => _positions.remove(itemId);
}

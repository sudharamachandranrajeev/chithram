enum Role {
  admin,
  requester,
  viewer;

  /// Seerr permission bitmask for this role (see README): ADMIN=2, REQUEST=32.
  int get seerrPermissions => switch (this) {
    Role.admin => 2,
    Role.requester => 32,
    Role.viewer => 0,
  };

  bool get canRequest => this == Role.admin || this == Role.requester;
  bool get isAdmin => this == Role.admin;

  static Role? parse(Object? s) {
    if (s is! String) return null;
    for (final r in Role.values) {
      if (r.name == s) return r;
    }
    return null;
  }
}

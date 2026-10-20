/// Host allowlisting for the HTTP broker.
///
/// There is no Public Suffix List dependency: [registrableDomain] uses the last
/// two labels, or three when the second-to-last is a well-known second-level
/// label under a two-letter country code (co.uk, com.au, co.in, ...). Unlisted
/// multi-part suffixes therefore widen the allowlist to the whole suffix; that is
/// a known limit (see the spike report), not a silent one.
const _secondLevel = {'co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'or', 'ne', 'go', 'gob', 'nom'};

bool isIpLiteral(String host) =>
    RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');

String registrableDomain(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  if (isIpLiteral(h)) return h;
  final labels = h.split('.');
  if (labels.length <= 2) return h;
  final last = labels.last;
  final take = (last.length == 2 && _secondLevel.contains(labels[labels.length - 2])) ? 3 : 2;
  return labels.sublist(labels.length - take).join('.');
}

class HostAllowlist {
  HostAllowlist(Iterable<String> entries) : entries = entries.map((e) => e.toLowerCase()).toSet();

  /// Engine: registrable domain of its `url` plus the manifest's `hosts`.
  factory HostAllowlist.forEngine(String engineUrl, [Iterable<String> manifestHosts = const []]) {
    final uri = Uri.tryParse(engineUrl);
    final set = <String>{};
    if (uri != null && uri.host.isNotEmpty) set.add(registrableDomain(uri.host));
    set.addAll(manifestHosts);
    return HostAllowlist(set);
  }

  final Set<String> entries;

  bool allows(String host) {
    final h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    if (h.isEmpty) return false;
    for (final e in entries) {
      if (h == e || h.endsWith('.$e')) return true;
    }
    return false;
  }
}

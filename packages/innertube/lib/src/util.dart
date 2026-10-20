typedef Json = Map<String, dynamic>;

Json asJson(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<Object?> asList(Object? v) => v is List ? v.cast<Object?>() : const <Object?>[];

String asString(Object? v) => v == null ? '' : v.toString();

int? toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Every object under [key], anywhere in [node], in document order. Does not
/// descend into a match.
List<Json> findAll(Object? node, String key, [List<Json>? out]) {
  out ??= [];
  if (node is Map) {
    node.forEach((k, value) {
      if (k == key && value is Map) {
        out!.add(asJson(value));
      } else {
        findAll(value, key, out);
      }
    });
  } else if (node is List) {
    for (final value in node) {
      findAll(value, key, out);
    }
  }
  return out;
}

/// Text of an InnerTube text object: `{simpleText}` or `{runs: [{text}]}`.
String textOf(Object? node) {
  final j = asJson(node);
  if (j['simpleText'] != null) return asString(j['simpleText']);
  return asList(j['runs']).map((r) => asString(asJson(r)['text'])).join();
}

import 'dart:convert';
import 'dart:io';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

Object? fixtureAny(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

String fixtureText(String name) => File('test/fixtures/$name').readAsStringSync();

/// A fake sw.js_data body carrying [visitor].
String swBody(String visitor) {
  final d = List<Object?>.filled(14, null);
  d[13] = visitor;
  return ")]}'\n${jsonEncode([
    [
      null,
      null,
      [
        [d]
      ]
    ]
  ])}";
}

import 'package:chithram/src/core/redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redactUrl keeps scheme and host only', () {
    expect(redactUrl('https://user:pw@cdn.example.com:8443/live/a.m3u8?token=abc'), 'https://cdn.example.com');
    expect(redactUrl('not a url'), '<invalid url>');
  });

  test('redactText replaces every URL', () {
    final out = redactText('see http://a.example/x?k=v and magnet:?xt=urn:btih:abc&dn=n now');
    expect(out, 'see http://a.example and magnet: now');
  });

  test('maskUrlCredentials hides user info', () {
    expect(maskUrlCredentials('http://u:p@h.example/x'), 'http://***@h.example/x');
    expect(maskUrlCredentials('http://h.example/x'), 'http://h.example/x');
  });
}

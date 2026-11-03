import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/media/media_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseGatewayHost', () {
    test('accepts host, host:port, IPv4 and bracketed IPv6', () {
      expect(parseGatewayHost('media.local'), const GatewayHost('media.local', 8443));
      expect(parseGatewayHost(' Media.Local:9000 '), const GatewayHost('media.local', 9000));
      expect(parseGatewayHost('192.168.1.20'), const GatewayHost('192.168.1.20', 8443));
      expect(parseGatewayHost('192.168.1.20:8443'), const GatewayHost('192.168.1.20', 8443));
      expect(parseGatewayHost('[fe80::1]:8443'), const GatewayHost('fe80::1', 8443));
      expect(parseGatewayHost('[::1]'), const GatewayHost('::1', 8443));
    });

    test('rejects schemes, paths, queries, credentials, spaces and bad ports', () {
      for (final bad in [
        '',
        'http://media.local',
        'https://media.local',
        'media.local/path',
        'media.local?x=1',
        'user@media.local',
        'media local',
        'media.local:0',
        'media.local:70000',
        'media.local:abc',
        '999.1.1.1',
        'fe80::1',
        '-bad.example',
        'a' * 300,
        'media.local#frag',
        'media.local:8443:1',
      ]) {
        expect(parseGatewayHost(bad), isNull, reason: bad);
      }
    });
  });

  group('normalizeFingerprint', () {
    final hex = List.generate(32, (i) => i.toRadixString(16).padLeft(2, '0')).join();
    final colon = List.generate(32, (i) => i.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

    test('accepts the usual spellings', () {
      expect(normalizeFingerprint(colon), colon);
      expect(normalizeFingerprint(hex), colon);
      expect(normalizeFingerprint(colon.toLowerCase().replaceAll(':', ' ')), colon);
      expect(normalizeFingerprint('  $colon\n'), colon);
    });

    test('rejects wrong length and non-hex', () {
      expect(normalizeFingerprint(''), isNull);
      expect(normalizeFingerprint(colon.substring(3)), isNull);
      expect(normalizeFingerprint('${colon}00'), isNull);
      expect(normalizeFingerprint('zz' * 32), isNull);
    });
  });

  test('MediaConfig keeps only non-secret values in prefs', () async {
    final prefs = Prefs.memory();
    expect(MediaConfig.read(prefs).enabled, isFalse, reason: 'off by default');
    final fp = normalizeFingerprint('ab' * 32)!;
    await MediaConfig.save(prefs, host: const GatewayHost('media.local', 8443), fingerprint: fp);
    final c = MediaConfig.read(prefs);
    expect(c.configured, isTrue);
    expect(c.host, const GatewayHost('media.local', 8443));
    expect(c.fingerprint, fp);
    await MediaConfig.clear(prefs);
    expect(MediaConfig.read(prefs).configured, isFalse);
  });

  test('an IPv6 host and its port survive save and read', () async {
    final prefs = Prefs.memory();
    final fp = normalizeFingerprint('cd' * 32)!;
    final host = parseGatewayHost('[fe80::1]:8443')!;
    await MediaConfig.save(prefs, host: host, fingerprint: fp);
    final c = MediaConfig.read(prefs);
    expect(c.configured, isTrue);
    expect(c.host, const GatewayHost('fe80::1', 8443));
    expect('${c.host}', '[fe80::1]:8443');
  });
}

import 'package:chithram_gateway/src/pairing.dart';
import 'package:chithram_gateway/src/roles.dart';
import 'package:chithram_gateway/src/state.dart';
import 'package:test/test.dart';

GatewayState _state() =>
    GatewayState()..users['u1'] = UserRec('alice', Role.requester);

void main() {
  group('pairing', () {
    test('code works once, token stored only as hash', () {
      final s = _state();
      final code = issueCode(s, 'u1', 1000);
      expect(code, matches(RegExp(r'^[0-9]{6}$')));
      expect(s.codes.single.hash, isNot(contains(code)));
      final r = redeemCode(s, code, 'Pixel', 2000);
      expect(r, isNotNull);
      expect(s.devices.single.tokenHash, isNot(r!.token));
      expect(s.devices.single.tokenHash.length, 64);
      expect(redeemCode(s, code, 'Pixel', 3000), isNull, reason: 'single use');
    });

    test('code expires after 10 minutes', () {
      final s = _state();
      final code = issueCode(s, 'u1', 0);
      expect(redeemCode(s, code, 'x', codeTtlMs), isNull);
    });

    test('5 wrong attempts invalidate the code even for the right guess', () {
      final s = _state();
      final code = issueCode(s, 'u1', 0);
      final wrong = code == '000000' ? '111111' : '000000';
      for (var i = 0; i < 4; i++) {
        expect(redeemCode(s, wrong, 'x', 10), isNull);
        expect(s.codes, hasLength(1));
      }
      expect(redeemCode(s, wrong, 'x', 10), isNull);
      expect(s.codes, isEmpty, reason: 'locked after the 5th failure');
      expect(redeemCode(s, code, 'x', 10), isNull);
      expect(s.devices, isEmpty);
    });

    test('a new code for the same user replaces the old one', () {
      final s = _state();
      issueCode(s, 'u1', 0);
      issueCode(s, 'u1', 0);
      expect(s.codes, hasLength(1));
    });

    test('code of a removed user creates no device and is consumed', () {
      final s = _state();
      final code = issueCode(s, 'u1', 0);
      s.users.clear();
      expect(redeemCode(s, code, 'Pixel', 1), isNull);
      expect(s.devices, isEmpty);
      expect(s.codes, isEmpty);
    });

    test('global throttle', () {
      final t = Throttle(3, 1000);
      expect(
        [t.allow(0), t.allow(1), t.allow(2), t.allow(3)],
        [true, true, true, false],
      );
      expect(t.allow(1001), isTrue);
    });
  });

  group('device auth', () {
    test('right token authenticates, wrong or empty does not', () {
      final s = _state();
      final code = issueCode(s, 'u1', 0);
      final r = redeemCode(s, code, 'Pixel', 1)!;
      expect(authenticate(s, r.token)?.id, r.device.id);
      expect(authenticate(s, '${r.token}x'), isNull);
      expect(authenticate(s, ''), isNull);
    });

    test('revoked device no longer authenticates', () {
      final s = _state();
      final r = redeemCode(s, issueCode(s, 'u1', 0), 'Pixel', 1)!;
      s.devices.removeWhere((d) => d.id == r.device.id);
      expect(authenticate(s, r.token), isNull);
    });

    test('state JSON round trip keeps hashes only', () {
      final s = _state();
      final r = redeemCode(s, issueCode(s, 'u1', 0), 'Pixel', 1)!;
      final back = GatewayState.fromJson(s.toJson());
      expect(authenticate(back, r.token)?.userId, 'u1');
      expect(back.toJson().toString(), isNot(contains(r.token)));
    });
  });
}

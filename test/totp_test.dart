import 'package:flutter_test/flutter_test.dart';
import 'package:secret_core/core/totp/base32.dart';
import 'package:secret_core/core/totp/totp_engine.dart';

void main() {
  test('Base32 encode & decode', () {
    final original = 'Hello SecretCore 2026!';
    final bytes = original.codeUnits;
    final encoded = Base32.encode(bytes);
    final decoded = String.fromCharCodes(Base32.decode(encoded));
    expect(decoded, equals(original));
  });

  test('RFC 6238 Standard Test Vectors', () {
    // Secret "12345678901234567890" in Base32:
    final secretBase32 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

    // Time: 59 seconds -> counter = 1
    final time59 = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
    final code6 = TOTPEngine.generateCode(
      secret: secretBase32,
      time: time59,
      digits: 6,
      period: 30,
      algorithm: TOTPAlgorithm.sha1,
    );
    expect(code6, equals('287082'));

    final code8 = TOTPEngine.generateCode(
      secret: secretBase32,
      time: time59,
      digits: 8,
      period: 30,
      algorithm: TOTPAlgorithm.sha1,
    );
    expect(code8, equals('94287082'));
  });

  test('OTPAuth URI parser', () {
    final uri = 'otpauth://totp/GitHub:ximsecret?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30';
    final parsed = TOTPEngine.parseOTPAuthURI(uri);
    expect(parsed, isNotNull);
    expect(parsed!.issuer, equals('GitHub'));
    expect(parsed.account, equals('ximsecret'));
    expect(parsed.secret, equals('JBSWY3DPEHPK3PXP'));
    expect(parsed.digits, equals(6));
    expect(parsed.period, equals(30));
  });
}

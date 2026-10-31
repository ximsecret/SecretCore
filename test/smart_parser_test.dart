import 'package:flutter_test/flutter_test.dart';
import 'package:secret_core/core/parser/smart_credential_parser.dart';

void main() {
  test('Space delimited tokens with bracket 2fa', () {
    final input = 'binance.com   trader_vip   superPass999!    2fa（JBSWY3DPEHPK3PXP）';
    final parsed = SmartCredentialParser.parse(input);

    expect(parsed.url, equals('binance.com'));
    expect(parsed.username, equals('trader_vip'));
    expect(parsed.password, equals('superPass999!'));
    expect(parsed.totpSecret, equals('JBSWY3DPEHPK3PXP'));
  });

  test('Custom labels: 用途, 资金密码, 备注1', () {
    final input = '域名: api.example.com  用途: 海外接码  密码: login123  资金密码: fund987  备注1: 注意绑定+86  2fa: JBSWY3DPEHPK3PXP';
    final parsed = SmartCredentialParser.parse(input);

    expect(parsed.url, equals('api.example.com'));
    expect(parsed.accountLabel, equals('用途'));
    expect(parsed.username, equals('海外接码'));
    expect(parsed.password, equals('login123'));
    expect(parsed.extraPasswords.length, equals(1));
    expect(parsed.extraPasswords.first.label, equals('资金密码'));
    expect(parsed.extraPasswords.first.value, equals('fund987'));
    expect(parsed.noteEntries.length, equals(1));
    expect(parsed.noteEntries.first.label, equals('备注1'));
    expect(parsed.noteEntries.first.content, equals('注意绑定+86'));
    expect(parsed.totpSecret, equals('JBSWY3DPEHPK3PXP'));
  });
}

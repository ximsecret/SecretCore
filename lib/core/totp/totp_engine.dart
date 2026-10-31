import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'base32.dart';

enum TOTPAlgorithm {
  sha1,
  sha256,
  sha512;

  String get displayName {
    switch (this) {
      case TOTPAlgorithm.sha1:
        return 'SHA-1';
      case TOTPAlgorithm.sha256:
        return 'SHA-256';
      case TOTPAlgorithm.sha512:
        return 'SHA-512';
    }
  }

  static TOTPAlgorithm fromString(String str) {
    switch (str.trim().toLowerCase()) {
      case 'sha256':
        return TOTPAlgorithm.sha256;
      case 'sha512':
        return TOTPAlgorithm.sha512;
      default:
        return TOTPAlgorithm.sha1;
    }
  }
}

class ParsedOTPAuth {
  final String secret;
  final String issuer;
  final String account;
  final int digits;
  final int period;
  final TOTPAlgorithm algorithm;

  ParsedOTPAuth({
    required this.secret,
    this.issuer = '',
    this.account = '',
    this.digits = 6,
    this.period = 30,
    this.algorithm = TOTPAlgorithm.sha1,
  });
}

class TOTPEngine {
  /// 计算 RFC 6238 标准动态码
  static String generateCode({
    required String secret,
    DateTime? time,
    int digits = 6,
    int period = 30,
    TOTPAlgorithm algorithm = TOTPAlgorithm.sha1,
  }) {
    final cleanSecret = secret.trim();
    if (cleanSecret.isEmpty) return '------';

    try {
      final key = Base32.decode(cleanSecret);
      if (key.isEmpty) return '------';

      final now = time ?? DateTime.now();
      final currentSeconds = now.millisecondsSinceEpoch ~/ 1000;
      final counter = currentSeconds ~/ period;

      // 8-byte big-endian counter
      final counterBytes = Uint8List(8);
      var temp = counter;
      for (int i = 7; i >= 0; i--) {
        counterBytes[i] = temp & 0xff;
        temp >>= 8;
      }

      Hash hashAlgorithm;
      switch (algorithm) {
        case TOTPAlgorithm.sha1:
          hashAlgorithm = sha1;
          break;
        case TOTPAlgorithm.sha256:
          hashAlgorithm = sha256;
          break;
        case TOTPAlgorithm.sha512:
          hashAlgorithm = sha512;
          break;
      }

      final hmac = Hmac(hashAlgorithm, key);
      final digest = hmac.convert(counterBytes).bytes;

      // 动态截断 (Dynamic Truncation)
      final offset = digest[digest.length - 1] & 0x0f;
      final binary = ((digest[offset] & 0x7f) << 24) |
          ((digest[offset + 1] & 0xff) << 16) |
          ((digest[offset + 2] & 0xff) << 8) |
          (digest[offset + 3] & 0xff);

      final modulus = pow(10, digits).toInt();
      final code = (binary % modulus).toString().padLeft(digits, '0');
      return code;
    } catch (_) {
      return '------';
    }
  }

  /// 获取当前剩余有效秒数
  static int getRemainingSeconds({int period = 30, DateTime? time}) {
    final now = time ?? DateTime.now();
    final currentSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final remaining = period - (currentSeconds % period);
    return remaining == 0 ? period : remaining;
  }

  /// 获取进度比例 (1.0 满格倒数到 0.0)
  static double getProgressRatio({int period = 30, DateTime? time}) {
    final remaining = getRemainingSeconds(period: period, time: time);
    return remaining / period;
  }

  /// 解析 otpauth://totp/... 标准协议链接
  static ParsedOTPAuth? parseOTPAuthURI(String uriString) {
    try {
      final uri = Uri.parse(uriString.trim());
      if (uri.scheme.toLowerCase() != 'otpauth') return null;

      final secret = uri.queryParameters['secret'] ?? '';
      if (secret.isEmpty) return null;

      var issuer = uri.queryParameters['issuer'] ?? '';
      var account = '';

      final path = Uri.decodeComponent(uri.path).replaceFirst('/', '');
      if (path.contains(':')) {
        final parts = path.split(':');
        if (issuer.isEmpty) issuer = parts[0].trim();
        account = parts.sublist(1).join(':').trim();
      } else if (account.isEmpty) {
        account = path.trim();
      }

      final digits = int.tryParse(uri.queryParameters['digits'] ?? '6') ?? 6;
      final period = int.tryParse(uri.queryParameters['period'] ?? '30') ?? 30;
      final algorithmStr = uri.queryParameters['algorithm'] ?? 'SHA1';
      final algorithm = TOTPAlgorithm.fromString(algorithmStr);

      return ParsedOTPAuth(
        secret: secret,
        issuer: issuer,
        account: account,
        digits: digits,
        period: period,
        algorithm: algorithm,
      );
    } catch (_) {
      return null;
    }
  }
}

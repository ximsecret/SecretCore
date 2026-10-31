import 'dart:math';

enum PasswordStrength {
  weak,
  medium,
  strong,
  veryStrong,
}

class PasswordGenerator {
  static const String uppercaseChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String uppercaseAmbiguous = 'IO';
  static const String lowercaseChars = 'abcdefghijkmnpqrstuvwxyz';
  static const String lowercaseAmbiguous = 'l';
  static const String digitChars = '23456789';
  static const String digitAmbiguous = '01';
  static const String symbolChars = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

  static String generate({
    int length = 20,
    bool includeUppercase = true,
    bool includeLowercase = true,
    bool includeDigits = true,
    bool includeSymbols = true,
    bool avoidAmbiguous = true,
  }) {
    String pool = '';

    if (includeUppercase) {
      pool += uppercaseChars;
      if (!avoidAmbiguous) pool += uppercaseAmbiguous;
    }
    if (includeLowercase) {
      pool += lowercaseChars;
      if (!avoidAmbiguous) pool += lowercaseAmbiguous;
    }
    if (includeDigits) {
      pool += digitChars;
      if (!avoidAmbiguous) pool += digitAmbiguous;
    }
    if (includeSymbols) {
      pool += symbolChars;
    }

    if (pool.isEmpty) {
      pool = lowercaseChars + digitChars;
    }

    final rng = Random.secure();
    final chars = List<String>.generate(length, (_) => pool[rng.nextInt(pool.length)]);
    return chars.join();
  }

  /// 计算密码的信息熵 (bits)
  static double calculateEntropy(String password) {
    if (password.isEmpty) return 0.0;

    int poolSize = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) poolSize += 26;
    if (RegExp(r'[A-Z]').hasMatch(password)) poolSize += 26;
    if (RegExp(r'[0-9]').hasMatch(password)) poolSize += 10;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) poolSize += 32;

    if (poolSize == 0) poolSize = 26;
    final entropy = password.length * (log(poolSize) / ln2);
    return entropy;
  }

  static PasswordStrength evaluateStrength(String password) {
    final entropy = calculateEntropy(password);
    if (entropy < 40) return PasswordStrength.weak;
    if (entropy < 65) return PasswordStrength.medium;
    if (entropy < 90) return PasswordStrength.strong;
    return PasswordStrength.veryStrong;
  }
}

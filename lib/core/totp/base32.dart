import 'dart:typed_data';

class Base32 {
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static Uint8List decode(String input) {
    final cleaned = input
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('=', '');

    if (cleaned.isEmpty) return Uint8List(0);

    final output = <int>[];
    int buffer = 0;
    int bitsLeft = 0;

    for (int i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      final val = _alphabet.indexOf(char);
      if (val == -1) {
        throw FormatException('非法的 Base32 字符: $char');
      }

      buffer = (buffer << 5) | val;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        output.add((buffer >> bitsLeft) & 0xff);
      }
    }

    return Uint8List.fromList(output);
  }

  static String encode(List<int> bytes) {
    if (bytes.isEmpty) return '';

    final buffer = StringBuffer();
    int current = 0;
    int bitsLeft = 0;

    for (final byte in bytes) {
      current = (current << 8) | (byte & 0xff);
      bitsLeft += 8;

      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        final index = (current >> bitsLeft) & 0x1f;
        buffer.write(_alphabet[index]);
      }
    }

    if (bitsLeft > 0) {
      final index = (current << (5 - bitsLeft)) & 0x1f;
      buffer.write(_alphabet[index]);
    }

    return buffer.toString();
  }
}

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class InvalidVaultFormatException implements Exception {
  final String message;
  InvalidVaultFormatException([this.message = '无效的保险箱文件格式']);
  @override
  String toString() => message;
}

class InvalidMasterPasswordException implements Exception {
  final String message;
  InvalidMasterPasswordException([this.message = '主密码错误或保险箱数据已被篡改']);
  @override
  String toString() => message;
}

class CryptoEngine {
  // Magic 标识 'SCVAULT1' (SecretCore Vault Format v1)
  static const List<int> magicHeader = [0x53, 0x43, 0x56, 0x41, 0x55, 0x4c, 0x54, 0x31];
  static const int saltLength = 32;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int pbkdf2Iterations = 150000;

  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: pbkdf2Iterations,
    bits: 256,
  );

  /// 生成指定长度的高强度加密安全随机字节
  static Uint8List secureRandomBytes(int length) {
    final rng = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  /// 使用主密码对 JSON 明文字符串进行 AES-256-GCM 强加密
  /// 输出标准的 .scvault 二进制信封格式
  static Future<Uint8List> encryptVault(String plaintextJson, String masterPassword) async {
    final salt = secureRandomBytes(saltLength);
    final nonce = secureRandomBytes(nonceLength);

    final secretKey = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: salt,
    );

    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintextJson),
      secretKey: secretKey,
      nonce: nonce,
    );

    final ciphertext = secretBox.cipherText;
    final macTag = secretBox.mac.bytes;

    final totalLength = magicHeader.length + saltLength + nonceLength + tagLength + ciphertext.length;
    final buffer = Uint8List(totalLength);
    int offset = 0;

    // 1. Magic
    buffer.setRange(offset, offset + magicHeader.length, magicHeader);
    offset += magicHeader.length;

    // 2. Salt
    buffer.setRange(offset, offset + saltLength, salt);
    offset += saltLength;

    // 3. Nonce
    buffer.setRange(offset, offset + nonceLength, nonce);
    offset += nonceLength;

    // 4. Mac Tag
    buffer.setRange(offset, offset + tagLength, macTag);
    offset += tagLength;

    // 5. Ciphertext
    buffer.setRange(offset, offset + ciphertext.length, ciphertext);

    return buffer;
  }

  /// 解密 .scvault 二进制信封
  static Future<String> decryptVault(Uint8List encryptedData, String masterPassword) async {
    final minLength = magicHeader.length + saltLength + nonceLength + tagLength;
    if (encryptedData.length < minLength) {
      throw InvalidVaultFormatException('保险箱数据文件过短或损坏');
    }

    // 验证 Magic
    for (int i = 0; i < magicHeader.length; i++) {
      if (encryptedData[i] != magicHeader[i]) {
        throw InvalidVaultFormatException('非法的保险箱文件格式头');
      }
    }

    int offset = magicHeader.length;

    final salt = encryptedData.sublist(offset, offset + saltLength);
    offset += saltLength;

    final nonce = encryptedData.sublist(offset, offset + nonceLength);
    offset += nonceLength;

    final macTag = encryptedData.sublist(offset, offset + tagLength);
    offset += tagLength;

    final ciphertext = encryptedData.sublist(offset);

    final secretKey = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: salt,
    );

    try {
      final secretBox = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(macTag),
      );

      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw InvalidMasterPasswordException('主密码错误或保险箱数据被篡改');
    }
  }
}

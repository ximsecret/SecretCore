import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

void main() {
  test('AES-GCM PBKDF2 roundtrip', () async {
    final password = "MyMasterPassword123!";
    final plaintext = "{\"test\": \"SecretCore vault content\", \"timestamp\": 123456789}";
    
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 10000, // quick test
      bits: 256,
    );
    final salt = List<int>.generate(32, (i) => i * 7 % 256);
    final secretKey = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    final aesGcm = AesGcm.with256bits();
    final nonce = aesGcm.newNonce();
    final secretBox = await aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    // Decrypt
    final decryptedBytes = await aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    final decryptedText = utf8.decode(decryptedBytes);
    expect(decryptedText, equals(plaintext));
  });
}

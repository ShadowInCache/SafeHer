import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;

import 'secure_store.dart';

class EncryptedBlob {
  final String cipherTextBase64;
  final String ivBase64;

  const EncryptedBlob({required this.cipherTextBase64, required this.ivBase64});

  Map<String, dynamic> toJson() {
    return {'cipher_text': cipherTextBase64, 'iv': ivBase64};
  }

  factory EncryptedBlob.fromJson(Map<String, dynamic> json) {
    return EncryptedBlob(
      cipherTextBase64: (json['cipher_text'] ?? '').toString(),
      ivBase64: (json['iv'] ?? '').toString(),
    );
  }
}

class EncryptionService {
  final SecureStore _secureStore;

  EncryptionService(this._secureStore);

  Future<encrypt.Key> _loadOrCreateKey() async {
    final existing = await _secureStore.read(SecureStore.encryptionKey);
    if (existing != null && existing.isNotEmpty) {
      return encrypt.Key(base64Decode(existing));
    }

    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await _secureStore.write(SecureStore.encryptionKey, base64Encode(bytes));
    return encrypt.Key(bytes);
  }

  Future<EncryptedBlob> encryptBytes(Uint8List plainBytes) async {
    final key = await _loadOrCreateKey();
    final iv = encrypt.IV.fromSecureRandom(16);
    final aes = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final cipher = aes.encryptBytes(plainBytes, iv: iv);

    return EncryptedBlob(cipherTextBase64: cipher.base64, ivBase64: iv.base64);
  }

  Future<Uint8List> decryptBytes(EncryptedBlob blob) async {
    final key = await _loadOrCreateKey();
    final iv = encrypt.IV(base64Decode(blob.ivBase64));
    final aes = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypt.Encrypted(base64Decode(blob.cipherTextBase64));
    final decrypted = aes.decryptBytes(encrypted, iv: iv);
    return Uint8List.fromList(decrypted);
  }
}

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// 一个封装类，用于处理基于 ECDH + XChaCha20-Poly1305 的加密通信
/// 以便在流量分析中模拟标准 AES 特征，同时利用 XChaCha20 的安全性
class SecurePacketFormatter {
  static final _keyExchangeAlgorithm = X25519();
  static final _cipherAlgorithm = Xchacha20.poly1305Aead();

  // ==========================================
  // Here is ECDH
  // ==========================================

  // Ephemeral Key Pair
  static Future<SimpleKeyPair> generateEphemeralKeyPair() async {
    return await _keyExchangeAlgorithm.newKeyPair();
  }

  // Session Key
  static Future<SecretKey> deriveSessionKey(
      SimpleKeyPair localKeyPair, List<int> remotePublicKeyBytes) async {
    final remotePublicKey = SimplePublicKey(
      remotePublicKeyBytes,
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _keyExchangeAlgorithm.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );

    // 直接提取 32 字节作为加密密钥
    // 建议在此处增加一步 HKDF 派生，但直接使用也是安全的（笑
    return SecretKey(await sharedSecret.extractBytes());
  }

  // ==========================================
  // 2. 加密并格式化 (模拟 AES-GCM 结构)
  // ==========================================

  /// 加密数据，并返回伪装成 AES-GCM 格式的数据包。
  /// 
  /// 输出格式: [Pseudo IV (12B)] + [Hidden Nonce Part (12B)] + [Ciphertext] + [Tag (16B)]

  static Future<Uint8List> encryptPacket(
      SecretKey sessionKey, List<int> plaintext) async {
  
    final nonce = _cipherAlgorithm.newNonce(); 

    final secretBox = await _cipherAlgorithm.encrypt(
      plaintext,
      secretKey: sessionKey,
      nonce: nonce,
    );

    // XChaCha20 Nonce (24B) = [Part A (12B)] + [Part B (12B)]
    final noncePartA = nonce.sublist(0, 12);
    final noncePartB = nonce.sublist(12, 24);

    // 注意：secretBox.cipherText 是加密后的数据（不包括认证标签）
    // secretBox.mac.bytes 是认证标签（16字节）
    final builder = BytesBuilder();
    builder.add(noncePartA);
    builder.add(noncePartB);
    builder.add(secretBox.cipherText);
    builder.add(secretBox.mac.bytes);
    return builder.toBytes();
  }
  static Future<List<int>> decryptPacket(
      SecretKey sessionKey, Uint8List encryptedPacket) async {
    const int aesIvLength = 12;
    const int aesTagLength = 16;
    const int hiddenNonceLength = 12;

    if (encryptedPacket.length < aesIvLength + aesTagLength + hiddenNonceLength) {
      throw Exception("Packet length too short: invalid format.");
    }
    final noncePartA = encryptedPacket.sublist(0, aesIvLength);
    final tagBytes = encryptedPacket.sublist(encryptedPacket.length - aesTagLength);
    final bodySection = encryptedPacket.sublist(
        aesIvLength, encryptedPacket.length - aesTagLength);
    final noncePartB = bodySection.sublist(0, hiddenNonceLength);
    final actualCiphertext = bodySection.sublist(hiddenNonceLength);
    final fullNonce = Uint8List.fromList([...noncePartA, ...noncePartB]);
    final secretBox = SecretBox(
      actualCiphertext,
      nonce: fullNonce,
      mac: Mac(tagBytes),
    );

    return await _cipherAlgorithm.decrypt(
      secretBox,
      secretKey: sessionKey,
    );
  }
}
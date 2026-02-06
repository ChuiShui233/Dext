import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:fast_rsa/fast_rsa.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:dext/services/core/XChaCha.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  // 硬编码公钥
  static const String _publicKeyPem = '''
-----BEGIN RSA PUBLIC KEY-----
MIIBCgKCAQEAoRpRN82/1/63Oj01imEljjotBFjly246c84IkawDs6Z9qXlaFt8U
Z8zB0HkR+Cz5F2uwSK4haue2BrxZ3CV4krH7RIET1qaW4g66hIqNGkYM144k2X4m
+Jn1D83MbthT+6NYpZHOX3KGAO4x4CZyWyaWw8bUbwzzvhIV2m+I5u+ufI8J9OLx
Bky7hzk7PO2CvcAqLJt58zbIt6+AZMcYkWR62QH3RVsxzkytyfDce7xC+aS2GDwc
7E8uX1rk1haFpSjbCsKvxftYGmjJMsSuhthcE7b/RCr4Bi4RWzdl6ikzVsxJY/T5
O5BNvaOmpC2jMYWf0NfHRX9RIobjMknwGwIDAQAB
-----END RSA PUBLIC KEY-----
''';

  // 当前会话密钥
  SessionKey? _currentSessionKey;

  Future<void> initialize() async {
  }

  // 生成AES会话密钥
  SessionKey generateSessionKey() {
    final random = Random.secure();
    
    // 生成32字节的AES-256密钥
    final key = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      key[i] = random.nextInt(256);
    }
    
    // 生成16字节的IV
    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      iv[i] = random.nextInt(256);
    }
    
    _currentSessionKey = SessionKey(key: key, iv: iv);
    return _currentSessionKey!;
  }

  // 使用RSA加密会话密钥
  Future<String> encryptSessionKey(SessionKey sessionKey) async {
    final sessionKeyData = sessionKey.toBase64();
    final encrypted = await RSA.encryptPKCS1v15(sessionKeyData, _publicKeyPem);
    return encrypted; // RSA.encryptPKCS1v15已经返回base64编码的字符串
  }

  // 使用AES-GCM加密数据
  Uint8List encryptWithAES(Uint8List data, SessionKey sessionKey) {
    final cipher = GCMBlockCipher(AESEngine());
    
    // 生成随机nonce (12字节用于GCM)
    final nonce = Uint8List(12);
    final random = Random.secure();
    for (int i = 0; i < nonce.length; i++) {
      nonce[i] = random.nextInt(256);
    }
    
    final params = AEADParameters(
      KeyParameter(sessionKey.key),
      128, // 128-bit authentication tag
      nonce,
      Uint8List(0), // no additional authenticated data
    );
    
    cipher.init(true, params);
    final encrypted = cipher.process(data);
    
    // 将nonce和加密数据组合
    final result = Uint8List(nonce.length + encrypted.length);
    result.setRange(0, nonce.length, nonce);
    result.setRange(nonce.length, result.length, encrypted);
    
    return result;
  }

  // 使用AES-GCM解密数据
  Uint8List decryptWithAES(Uint8List encryptedData, SessionKey sessionKey) {
    if (encryptedData.length < 12) {
      throw Exception('加密数据长度不足');
    }
    
    // 提取nonce和密文
    final nonce = encryptedData.sublist(0, 12);
    final ciphertext = encryptedData.sublist(12);
    
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(sessionKey.key),
      128,
      nonce,
      Uint8List(0),
    );
    
    cipher.init(false, params);
    return cipher.process(ciphertext);
  }

  // 传统RSA加密（向后兼容）
  Future<String> encrypt(String data) async {
    final encrypted = await RSA.encryptPKCS1v15(data, _publicKeyPem);
    final List<int> encryptedBytes = utf8.encode(encrypted);
    return base64Encode(encryptedBytes);
  }

  Future<String> encryptBody(Map<String, dynamic> data) async {
    final jsonStr = json.encode(data);
    return await encrypt(jsonStr);
  }

  // 新的混合加密方法：RSA加密会话密钥 + AES加密数据
  Future<EncryptedPayload> encryptWithSessionKey(Map<String, dynamic> data) async {
    // 生成会话密钥
    final sessionKey = generateSessionKey();
    
    // 使用RSA加密会话密钥
    final encryptedSessionKey = await encryptSessionKey(sessionKey);
    
    // 将数据序列化为JSON
    final jsonData = json.encode(data);
    final dataBytes = utf8.encode(jsonData);
    
    // 使用AES加密数据
    final encryptedData = encryptWithAES(Uint8List.fromList(dataBytes), sessionKey);
    
    return EncryptedPayload(
      sessionKey: encryptedSessionKey,
      data: base64Encode(encryptedData),
    );
  }

  /// 使用 ECDH + XChaCha20-Poly1305 的新型封装加密方式
  ///
  /// [remotePublicKeyBase64] 为后端提供的 X25519 公钥（Base64 编码）
  Future<XChaChaEncryptedPayload> encryptWithXChaCha(
    Map<String, dynamic> data,
    String remotePublicKeyBase64,
  ) async {
    final remotePublicKey = base64Decode(remotePublicKeyBase64);
    final localEphemeralKeyPair =
        await SecurePacketFormatter.generateEphemeralKeyPair();
    final sessionKey = await SecurePacketFormatter.deriveSessionKey(
      localEphemeralKeyPair,
      remotePublicKey,
    );

    final jsonBytes = utf8.encode(json.encode(data));
    final encryptedPacket = await SecurePacketFormatter.encryptPacket(
      sessionKey,
      jsonBytes,
    );

    final localPublicKey = await localEphemeralKeyPair.extractPublicKey();

    return XChaChaEncryptedPayload(
      ephemeralPublicKey: base64Encode(localPublicKey.bytes),
      packet: base64Encode(encryptedPacket),
    );
  }

  // 获取当前会话密钥
  SessionKey? get currentSessionKey => _currentSessionKey;
  
  // 清除当前会话密钥
  void clearSessionKey() {
    _currentSessionKey = null;
  }
}

// 会话密钥类
class SessionKey {
  final Uint8List key;
  final Uint8List iv;

  SessionKey({required this.key, required this.iv});

  get length => null;

  String toBase64() {
    final combined = Uint8List(key.length + iv.length);
    combined.setRange(0, key.length, key);
    combined.setRange(key.length, combined.length, iv);
    return base64Encode(combined);
  }

  static SessionKey fromBase64(String encoded) {
    final data = base64Decode(encoded);
    if (data.length != 48) { // 32 + 16
      throw ArgumentError('Invalid session key length');
    }
    
    return SessionKey(
      key: Uint8List.fromList(data.sublist(0, 32)),
      iv: Uint8List.fromList(data.sublist(32, 48)),
    );
  }
}

// 加密载荷类
class EncryptedPayload {
  final String sessionKey; // RSA加密的会话密钥
  final String data; // AES加密的数据

  EncryptedPayload({required this.sessionKey, required this.data});

  Map<String, dynamic> toJson() => {
    'sessionKey': sessionKey,
    'data': data,
  };
}

class XChaChaEncryptedPayload {
  final String ephemeralPublicKey;
  final String packet;

  const XChaChaEncryptedPayload({
    required this.ephemeralPublicKey,
    required this.packet,
  });

  Map<String, dynamic> toJson() => {
        'ephemeralPublicKey': ephemeralPublicKey,
        'packet': packet,
      };
}

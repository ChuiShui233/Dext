import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:dext/services/core/XChaCha.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

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

  SessionKey? _currentSessionKey;

  Future<void> initialize() async {
  }

  SessionKey generateSessionKey() {
    final random = Random.secure();
    
    final key = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      key[i] = random.nextInt(256);
    }
    
    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      iv[i] = random.nextInt(256);
    }
    
    _currentSessionKey = SessionKey(key: key, iv: iv);
    return _currentSessionKey!;
  }

  String _rsaEncryptPKCS1v15(String plaintext) {
    final key = _parseRsaPublicKey(_publicKeyPem);
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = _processInBlocks(cipher, plainBytes);
    return base64Encode(encrypted);
  }

  Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List data) {
    final inputBlockSize = engine.inputBlockSize;
    final outputBlockSize = engine.outputBlockSize;
    final numBlocks = (data.length + inputBlockSize - 1) ~/ inputBlockSize;
    final output = Uint8List(numBlocks * outputBlockSize);
    var inputOffset = 0;
    var outputOffset = 0;
    while (inputOffset < data.length) {
      final chunkSize =
          (inputOffset + inputBlockSize <= data.length) ? inputBlockSize : data.length - inputOffset;
      final chunk = engine.process(data.sublist(inputOffset, inputOffset + chunkSize));
      output.setRange(outputOffset, outputOffset + chunk.length, chunk);
      outputOffset += chunk.length;
      inputOffset += chunkSize;
    }
    return output.sublist(0, outputOffset);
  }

  RSAPublicKey _parseRsaPublicKey(String pem) {
    return CryptoUtils.rsaPublicKeyFromPem(pem);
  }

  Future<String> encryptSessionKey(SessionKey sessionKey) async {
    final sessionKeyData = sessionKey.toBase64();
    return _rsaEncryptPKCS1v15(sessionKeyData);
  }

  Uint8List encryptWithAES(Uint8List data, SessionKey sessionKey) {
    final cipher = GCMBlockCipher(AESEngine());
    
    final nonce = Uint8List(12);
    final random = Random.secure();
    for (int i = 0; i < nonce.length; i++) {
      nonce[i] = random.nextInt(256);
    }
    
    final params = AEADParameters(
      KeyParameter(sessionKey.key),
      128,
      nonce,
      Uint8List(0),
    );
    
    cipher.init(true, params);
    final encrypted = cipher.process(data);
    
    final result = Uint8List(nonce.length + encrypted.length);
    result.setRange(0, nonce.length, nonce);
    result.setRange(nonce.length, result.length, encrypted);
    
    return result;
  }

  Uint8List decryptWithAES(Uint8List encryptedData, SessionKey sessionKey) {
    if (encryptedData.length < 12) {
      throw Exception('加密数据长度不足');
    }
    
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

  Future<String> encrypt(String data) async {
    final encrypted = _rsaEncryptPKCS1v15(data);
    final List<int> encryptedBytes = utf8.encode(encrypted);
    return base64Encode(encryptedBytes);
  }

  Future<String> encryptBody(Map<String, dynamic> data) async {
    final jsonStr = json.encode(data);
    return await encrypt(jsonStr);
  }

  Future<EncryptedPayload> encryptWithSessionKey(Map<String, dynamic> data) async {
    final sessionKey = generateSessionKey();
    final encryptedSessionKey = await encryptSessionKey(sessionKey);
    final jsonData = json.encode(data);
    final dataBytes = utf8.encode(jsonData);
    final encryptedData = encryptWithAES(Uint8List.fromList(dataBytes), sessionKey);
    return EncryptedPayload(
      sessionKey: encryptedSessionKey,
      data: base64Encode(encryptedData),
    );
  }

  /// [remotePublicKeyBase64]
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

  SessionKey? get currentSessionKey => _currentSessionKey;
  void clearSessionKey() {
    _currentSessionKey = null;
  }
}
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
    if (data.length != 48) {
      throw ArgumentError('Invalid session key length');
    }
    
    return SessionKey(
      key: Uint8List.fromList(data.sublist(0, 32)),
      iv: Uint8List.fromList(data.sublist(32, 48)),
    );
  }
}

class EncryptedPayload {
  final String sessionKey;
  final String data;

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

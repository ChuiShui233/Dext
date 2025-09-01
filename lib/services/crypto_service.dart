import 'dart:convert';
import 'package:fast_rsa/fast_rsa.dart';

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

  Future<void> initialize() async {
  }

  Future<String> encrypt(String data) async {
    final encrypted = await RSA.encryptPKCS1v15(data, _publicKeyPem);
    final List<int> encryptedBytes = utf8.encode(encrypted);
    return base64Encode(encryptedBytes);
  }

  Future<String> encryptBody(Map<String, dynamic> data) async {
    final jsonStr = json.encode(data);
    return await encrypt(jsonStr);
  }
}

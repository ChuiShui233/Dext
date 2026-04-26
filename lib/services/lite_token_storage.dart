import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LiteTokenStorage {
  LiteTokenStorage._();
  static final LiteTokenStorage instance = LiteTokenStorage._();

  static const _kToken = 'auth_token';
  static const _kExpiry = 'token_expiry';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> save({
    required String token,
    required DateTime expires,
  }) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kExpiry, value: expires.toIso8601String());
  }

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<DateTime?> readExpiry() async {
    final raw = await _storage.read(key: _kExpiry);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<bool> isValid() async {
    final token = await readToken();
    final expiry = await readExpiry();
    if (token == null || token.isEmpty || expiry == null) return false;
    return expiry.isAfter(DateTime.now());
  }

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kExpiry);
  }
}

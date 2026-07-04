import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _kTokenKey = 'auth_token';
  static const _kExpiryKey = 'token_expiry';

  final FlutterSecureStorage _storage;
  final ApiService Function(String token) _apiServiceBuilder;

  String? _token;
  DateTime? _expiry;
  bool _isRefreshing = false;
  bool _hasInitialized = false;

  AuthProvider({
    FlutterSecureStorage? storage,
    ApiService Function(String token)? apiServiceBuilder,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _apiServiceBuilder = apiServiceBuilder ?? ((t) => ApiService(authToken: t));

  String? get token => _token;
  DateTime? get expiry => _expiry;
  bool get isLoggedIn => _token != null && _expiry != null && !_isExpired;
  bool get isRefreshing => _isRefreshing;
  bool get hasInitialized => _hasInitialized;

  bool get _isExpired {
    final exp = _expiry;
    if (exp == null) return true;
    return !exp.isAfter(DateTime.now());
  }

  ApiService buildApiService() {
    return _apiServiceBuilder(_token ?? '');
  }

  Future<void> initialize() async {
    if (_hasInitialized) return;
    _hasInitialized = true;
    final token = await _storage.read(key: _kTokenKey);
    final expiryRaw = await _storage.read(key: _kExpiryKey);
    DateTime? expiry;
    if (expiryRaw != null) {
      try {
        expiry = DateTime.parse(expiryRaw);
      } catch (_) {
        expiry = null;
      }
    }
    if (token != null && expiry != null && expiry.isAfter(DateTime.now())) {
      _token = token;
      _expiry = expiry;
    } else if (token != null && expiry != null) {
      // 过期：尝试用旧 token 续期
      final refreshed = await _tryRefresh(token);
      if (!refreshed) {
        await _clearStorage();
      }
    } else {
      await _clearStorage();
    }
    notifyListeners();
  }

  Future<bool> login(String token, DateTime expires) async {
    _token = token;
    _expiry = expires;
    await _storage.write(key: _kTokenKey, value: token);
    await _storage.write(key: _kExpiryKey, value: expires.toIso8601String());
    notifyListeners();
    return true;
  }

  Future<bool> refreshToken() async {
    final current = _token;
    if (current == null) return false;
    return _tryRefresh(current);
  }

  Future<bool> _tryRefresh(String currentToken) async {
    if (_isRefreshing) return false;
    _isRefreshing = true;
    notifyListeners();
    try {
      final newToken = await _apiServiceBuilder(currentToken).refreshToken();
      final newExpiry = _expiry ?? DateTime.now().add(const Duration(minutes: 30));
      final refreshed = newExpiry.isAfter(DateTime.now())
          ? newExpiry
          : DateTime.now().add(const Duration(minutes: 30));
      _token = newToken;
      _expiry = refreshed;
      await _storage.write(key: _kTokenKey, value: newToken);
      await _storage.write(key: _kExpiryKey, value: refreshed.toIso8601String());
      return true;
    } catch (_) {
      return false;
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _token = null;
    _expiry = null;
    await _clearStorage();
    notifyListeners();
  }

  Future<void> _clearStorage() async {
    try {
      await _storage.delete(key: _kTokenKey);
      await _storage.delete(key: _kExpiryKey);
    } catch (_) {}
  }
}

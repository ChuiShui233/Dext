import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto_service.dart';
import 'api_core.dart';

class TokenService {
  final String baseUrl;
  final CryptoService cryptoService;
  String? authToken;
  DateTime? _tokenExpires;
  
  // 刷新锁，防止并发刷新
  bool _isRefreshing = false;
  final List<Function(String?)> _refreshCallbacks = [];
  
  // 预刷新定时器
  Timer? _preRefreshTimer;
  
  // 刷新重试配置
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  
  // 提前刷新时间（令牌过期前5分钟）
  static const Duration _preRefreshDuration = Duration(minutes: 5);
  
  TokenService({required this.baseUrl, required this.cryptoService, this.authToken});

  Future<void> ensureAuthTokenLoaded() async {
    if (authToken == null || authToken!.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        authToken = prefs.getString('auth_token');
        
        // 加载令牌过期时间
        final expiresStr = prefs.getString('auth_token_expires');
        if (expiresStr != null) {
          _tokenExpires = DateTime.tryParse(expiresStr);
          _schedulePreRefresh();
        }
      } catch (_) {}
    }
  }

  /// 检查令牌是否即将过期
  bool _isTokenExpiringSoon() {
    if (_tokenExpires == null) return false;
    final now = DateTime.now();
    final timeUntilExpiry = _tokenExpires!.difference(now);
    return timeUntilExpiry <= _preRefreshDuration;
  }

  /// 检查令牌是否已过期
  bool _isTokenExpired() {
    if (_tokenExpires == null) return false;
    return DateTime.now().isAfter(_tokenExpires!);
  }

  /// 安排预刷新定时器
  void _schedulePreRefresh() {
    _preRefreshTimer?.cancel();
    
    if (_tokenExpires == null) return;
    
    final now = DateTime.now();
    final timeUntilPreRefresh = _tokenExpires!.subtract(_preRefreshDuration).difference(now);
    
    if (timeUntilPreRefresh.isNegative) {
      // 已经需要刷新了
      if (!_isRefreshing) {
        _performPreRefresh();
      }
      return;
    }
    
    _preRefreshTimer = Timer(timeUntilPreRefresh, _performPreRefresh);
  }

  /// 执行预刷新
  void _performPreRefresh() async {
    try {
      await refreshToken();
    } catch (e) {
      // 预刷新失败，等待下次API调用时再刷新
      if (kDebugMode) {
        print('[TokenService] 预刷新失败: $e');
      }
    }
  }

  Future<String?> refreshToken({StatusCallback? onStatus, int retryCount = 0}) async {
    await ensureAuthTokenLoaded();
    
    if (authToken == null || authToken!.isEmpty) {
      throw '无法刷新令牌：当前没有有效的认证令牌';
    }

    // 如果正在刷新，等待当前刷新完成
    if (_isRefreshing) {
      final completer = Completer<String?>();
      _refreshCallbacks.add(completer.complete);
      return completer.future;
    }

    _isRefreshing = true;

    try {
      // 读取 refresh_token，支持从安全存储读取
      final prefs = await SharedPreferences.getInstance();
      String? refreshToken = prefs.getString('refresh_token');
      
      if (refreshToken == null || refreshToken.isEmpty) {
        try {
          const storage = FlutterSecureStorage();
          refreshToken = await storage.read(key: 'refresh_token');
        } catch (_) {}
      }
      
      if (refreshToken == null || refreshToken.isEmpty) {
        throw '无法刷新令牌：未找到刷新令牌';
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: json.encode({
          'refresh_token': refreshToken,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newToken = data['token'];
        final newRefreshToken = data['refresh_token'];
        final expiresStr = data['expires'];
        
        // 更新存储的令牌和过期时间
        authToken = newToken;
        await prefs.setString('auth_token', newToken);
        
        if (expiresStr != null) {
          final expires = DateTime.tryParse(expiresStr);
          if (expires != null) {
            _tokenExpires = expires;
            await prefs.setString('auth_token_expires', expires.toIso8601String());
            _schedulePreRefresh();
          }
        }
        
        if (newRefreshToken != null) {
          await prefs.setString('refresh_token', newRefreshToken);
          try {
            const storage = FlutterSecureStorage();
            await storage.write(key: 'refresh_token', value: newRefreshToken);
          } catch (_) {}
        }
        
        // 通知所有等待的请求
        for (var callback in _refreshCallbacks) {
          callback(newToken);
        }
        _refreshCallbacks.clear();
        
        return newToken;
      } else if (response.statusCode == 401) {
        // 认证失败，清除所有令牌
        await _clearAllTokens();
        
        // 通知所有等待的请求失败
        for (var callback in _refreshCallbacks) {
          callback(null);
        }
        _refreshCallbacks.clear();
        
        throw '刷新令牌失败：认证已过期';
      } else {
        throw '刷新令牌失败: HTTP ${response.statusCode}';
      }
    } catch (e) {
      // 如果是网络错误且还有重试次数，进行重试
      if (retryCount < _maxRetries && _isNetworkError(e)) {
        if (kDebugMode) {
          print('[TokenService] 刷新失败，${_retryDelay.inSeconds}秒后重试 (${retryCount + 1}/$_maxRetries): $e');
        }
        
        await Future.delayed(_retryDelay);
        return refreshToken(onStatus: onStatus, retryCount: retryCount + 1);
      }
      
      // 通知所有等待的请求失败
      for (var callback in _refreshCallbacks) {
        callback(null);
      }
      _refreshCallbacks.clear();
      
      throw '刷新令牌失败: $e';
    } finally {
      _isRefreshing = false;
    }
  }

  /// 判断是否为网络错误
  bool _isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('timeout') ||
           errorStr.contains('connection') ||
           errorStr.contains('network') ||
           errorStr.contains('socket');
  }

  /// 清除所有令牌和相关数据
  Future<void> _clearAllTokens() async {
    authToken = null;
    _tokenExpires = null;
    _preRefreshTimer?.cancel();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_expires');
      await prefs.remove('refresh_token');
      await prefs.remove('refresh_token_expires');
      
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'auth_token');
      await storage.delete(key: 'refresh_token');
      await storage.delete(key: 'session_key');
      
      cryptoService.clearSessionKey();
    } catch (_) {}
  }

  void updateAuthToken(String token) {
    authToken = token;
  }

  /// 检查是否需要刷新令牌（公共方法）
  bool shouldRefreshToken() {
    return _isTokenExpiringSoon() || _isTokenExpired();
  }

  /// 获取令牌剩余有效时间
  Duration? getTokenRemainingTime() {
    if (_tokenExpires == null) return null;
    final remaining = _tokenExpires!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// 设置令牌过期时间并安排预刷新
  void setTokenExpires(DateTime expires) {
    _tokenExpires = expires;
    _schedulePreRefresh();
  }

  /// 清理资源
  void dispose() {
    _preRefreshTimer?.cancel();
    _refreshCallbacks.clear();
  }
}

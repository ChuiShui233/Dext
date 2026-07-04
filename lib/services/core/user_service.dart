import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto_service.dart';
import 'api_core.dart';

class UserService {
  final String baseUrl;
  final CryptoService cryptoService;
  final Future<http.Response> Function(String, String, {StatusCallback? onStatus}) httpRequest;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) encryptedRequest;
  
  UserService({
    required this.baseUrl,
    required this.cryptoService,
    required this.httpRequest,
    required this.encryptedRequest,
  });

  Future<Map<String, dynamic>> getUserInfo({StatusCallback? onStatus}) async {
    final response = await httpRequest('GET', '$baseUrl/api/user/info', onStatus: onStatus);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      throw '未登录或登录已过期';
    }
    throw '获取用户信息失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> updateUsername({
    required String newUsername,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'PUT',
      '$baseUrl/api/user/username',
      {'newUsername': newUsername},
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      
      if (responseData['token'] != null) {
        final newToken = responseData['token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', newToken);
        cryptoService.clearSessionKey();
      }
      
      return responseData;
    } else if (response.statusCode == 400) {
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? '用户名格式错误';
    } else if (response.statusCode == 401) {
      throw '未登录或登录已过期';
    }
    throw '更新用户名失败: ${response.statusCode}';
  }

  Future<void> logout({StatusCallback? onStatus}) async {
    try {
      await httpRequest('POST', '$baseUrl/api/auth/logout', onStatus: onStatus);
    } catch (_) {
      // 忽略登出请求失败，继续清理本地数据
    }
    
    await clearAllLocalData();
  }

  Future<void> clearAllLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    // 需要保留的设置键名（这些是用户偏好，通常在登出后也应保留）
    final preservedKeys = {
      'window_close_dont_ask',
      'window_close_default_action',
      'theme_mode',
      'glass_card_enabled',
      'edge_drag_width',
      'dpi_scale',
      'settings_panel_width',
      'sidebar_collapsed',
    };
    
    // 清理除保留设置外的所有本地数据
    for (final key in keys) {
      if (!preservedKeys.contains(key)) {
        await prefs.remove(key);
      }
    }
    
    cryptoService.clearSessionKey();
  }
}

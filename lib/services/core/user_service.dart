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
    final response = await httpRequest('POST', '$baseUrl/api/auth/logout', onStatus: onStatus);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_token_expires');
    await prefs.remove('refresh_token');
    
    cryptoService.clearSessionKey();
    
    if (response.statusCode != 200 && response.statusCode != 401) {
      throw '退出登录失败: ${response.statusCode}';
    }
  }

  Future<void> clearAllLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_token_expires');
    await prefs.remove('refresh_token');
    await prefs.remove('projects_cache');
    await prefs.remove('surveys_cache');
    await prefs.remove('survey_stats_cache');
    await prefs.remove('recent_submissions');
    await prefs.remove('analytics_overview');
    
    cryptoService.clearSessionKey();
  }
}

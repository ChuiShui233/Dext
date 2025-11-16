import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto_service.dart';
import 'api_core.dart';

class AuthService {
  final String baseUrl;
  final CryptoService cryptoService;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) encryptedRequest;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) hybridRequest;
  
  AuthService({
    required this.baseUrl,
    required this.cryptoService,
    required this.encryptedRequest,
    required this.hybridRequest,
  });

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    final response = await hybridRequest(
      'POST',
      '$baseUrl/api/auth/login',
      {
        'username': username,
        'password': password,
        'captchaId': captchaId,
        'captchaValue': captchaValue,
      },
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final token = data['token'];
      // Session key is managed by the hybrid encryption flow
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      
      return data;
    } else if (response.statusCode == 401) {
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? '用户名或密码错误';
    } else if (response.statusCode == 400) {
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? '验证码错误';
    }
    throw '登录失败: ${response.statusCode}';
  }

  Future<void> register({
    required String username,
    required String password,
    required String captchaId,
    required String captchaValue,
    String? email,
    String? emailCode,
    StatusCallback? onStatus,
  }) async {
    final response = await hybridRequest(
      'POST',
      '$baseUrl/api/auth/register',
      {
        'username': username,
        'password': password,
        'captchaId': captchaId,
        'captchaValue': captchaValue,
        if (email != null) 'email': email,
        if (emailCode != null) 'emailCode': emailCode,
      },
      onStatus: onStatus,
    );

    if (response.statusCode != 201) {
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '注册失败';
      }
      throw '注册失败: ${response.statusCode}';
    }
  }

  Future<Map<String, dynamic>> bindOAuth({
    required String provider,
    required String accessToken,
  }) async {
    final response = await encryptedRequest(
      'POST',
      '$baseUrl/api/oauth/$provider/bind',
      {'accessToken': accessToken},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 400) {
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? 'OAuth绑定失败';
    }
    throw 'OAuth绑定失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> unbindOAuth({required String provider}) async {
    final response = await encryptedRequest(
      'DELETE',
      '$baseUrl/api/oauth/$provider/unbind',
      null,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 400) {
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? 'OAuth解绑失败';
    }
    throw 'OAuth解绑失败: ${response.statusCode}';
  }
}

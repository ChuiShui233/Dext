import 'dart:convert';
import 'package:http/http.dart' as http;

import 'core/api_core.dart';

class TokenExpired {
  final String message;
  TokenExpired(this.message);
  @override
  String toString() => message;
}

/// 认证相关服务（登录/注册/刷新令牌/校验/注销）
class AuthService {
  final ApiCore core;
  AuthService(this.core);

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    final http.Response resp = await core.encryptedRequest(
      'POST',
      '${ApiCore.baseUrl}/api/auth/login',
      {
        'username': username,
        'password': password,
        'captchaId': captchaId,
        'captchaValue': captchaValue,
      },
      onStatus: onStatus,
    );

    if (resp.statusCode == 200) {
      final data = json.decode(resp.body);
      return {
        'token': data['token'],
        'expires': DateTime.parse(data['expires']),
      };
    }
    final data = json.decode(resp.body);
    throw data['message'] ?? data['error'] ?? '登录失败';
  }

  Future<void> register({
    required String username,
    required String password,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    final http.Response resp = await core.encryptedRequest(
      'POST',
      '${ApiCore.baseUrl}/api/auth/register',
      {
        'username': username,
        'password': password,
        'captchaId': captchaId,
        'captchaValue': captchaValue,
      },
      onStatus: onStatus,
    );

    if (resp.statusCode != 201) {
      final data = json.decode(resp.body);
      throw data['message'] ?? data['error'] ?? '注册失败';
    }
  }

  Future<String> refreshToken({StatusCallback? onStatus}) async {
    final resp = await core.encryptedRequest(
      'POST',
      '${ApiCore.baseUrl}/api/auth/refresh',
      {'refresh': true},
      onStatus: onStatus,
    );
    if (resp.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(resp.body);
      return data['token'] as String;
    } else if (resp.statusCode == 401) {
      final msg = '认证令牌已失效，请重新登录';
      throw TokenExpired(msg);
    } else {
      throw '刷新认证token失败: ${resp.statusCode}';
    }
  }

  Future<bool> isTokenValid({StatusCallback? onStatus}) async {
    if (core.authToken == null || core.authToken!.isEmpty) return false;
    try {
      final resp = await core.httpRequest(
        'GET',
        '${ApiCore.baseUrl}/api/user/current',
        onStatus: onStatus,
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String> forceReLogin({
    required String username,
    required String password,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    final resp = await core.encryptedRequest(
      'POST',
      '${ApiCore.baseUrl}/api/auth/login',
      {
        'username': username,
        'password': password,
        'captchaId': captchaId,
        'captchaValue': captchaValue,
      },
      onStatus: onStatus,
    );
    if (resp.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(resp.body);
      return data['token'] as String;
    }
    throw '重新登录失败: ${resp.statusCode}';
  }

  Future<void> logout() async {
    // 使用核心 httpRequest，以在存在会话密钥时自动启用 AES 加密
    final resp = await core.httpRequest(
      'POST',
      '${ApiCore.baseUrl}/api/auth/logout',
      data: const {},
    );
    if (resp.statusCode != 200) {
      throw '注销失败: ${resp.body}';
    }
  }
}

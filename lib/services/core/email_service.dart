import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_core.dart';

class EmailService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) httpRequest;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) encryptedRequest;
  
  EmailService({required this.baseUrl, required this.httpRequest, required this.encryptedRequest});

  Future<void> sendEmailVerificationCode({
    required String email,
    required String purpose,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest(
      'POST',
      '$baseUrl/api/auth/send-email-code',
      {
        'email': email,
        'purpose': purpose,
        'captchaId': captchaId,
        'captchaValue': captchaValue,
      },
      onStatus: onStatus,
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '发送验证码失败';
      } else if (response.statusCode == 429) {
        throw '发送过于频繁，请稍后再试';
      }
      throw '发送验证码失败: ${response.statusCode}';
    }
  }

  Future<void> sendChangeEmailCode({
    required String email,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'POST',
      '$baseUrl/api/user/send-change-email-code',
      {
        'newEmail': email,
        'captchaId': captchaId,
        'captchaValue': captchaValue,
      },
      onStatus: onStatus,
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '发送验证码失败';
      } else if (response.statusCode == 429) {
        throw '发送过于频繁，请稍后再试';
      }
      throw '发送验证码失败: ${response.statusCode}';
    }
  }

  Future<void> sendEmailCodeForPasswordChange({StatusCallback? onStatus}) async {
    final response = await encryptedRequest(
      'POST',
      '$baseUrl/api/user/send-password-change-code',
      {},
      onStatus: onStatus,
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '发送验证码失败';
      } else if (response.statusCode == 429) {
        throw '发送过于频繁，请稍后再试';
      }
      throw '发送验证码失败: ${response.statusCode}';
    }
  }

  Future<bool> verifyEmailCode({
    required String email,
    required String code,
    required String purpose,
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest(
      'POST',
      '$baseUrl/api/auth/verify-email-code',
      {'email': email, 'code': code, 'purpose': purpose},
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['valid'] == true;
    } else if (response.statusCode == 400) {
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? '验证码错误';
    }
    throw '验证失败: ${response.statusCode}';
  }

  Future<void> changeEmail({
    required String newEmail,
    required String password,
    required String code,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'PUT',
      '$baseUrl/api/user/email',
      {'newEmail': newEmail, 'password': password, 'code': code},
      onStatus: onStatus,
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '邮箱格式错误';
      } else if (response.statusCode == 401) {
        throw '密码错误';
      }
      throw '更换邮箱失败: ${response.statusCode}';
    }
  }
}

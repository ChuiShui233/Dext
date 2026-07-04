import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_core.dart';

class PasswordService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) encryptedRequest;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) hybridRequest;
  
  PasswordService({required this.baseUrl, required this.encryptedRequest, required this.hybridRequest});

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'PUT',
      '$baseUrl/api/user/password',
      {'oldPassword': oldPassword, 'newPassword': newPassword},
      onStatus: onStatus,
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '密码格式错误';
      } else if (response.statusCode == 401) {
        throw '原密码错误';
      }
      throw '修改密码失败: ${response.statusCode}';
    }
  }

  Future<void> changePasswordWithEmail({
    required String code,
    required String newPassword,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'PUT',
      '$baseUrl/api/user/password-with-email',
      {'code': code, 'newPassword': newPassword},
      onStatus: onStatus,
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '验证码错误或已过期';
      }
      throw '修改密码失败: ${response.statusCode}';
    }
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
    StatusCallback? onStatus,
  }) async {
    final response = await hybridRequest(
      'POST',
      '$baseUrl/api/auth/reset-password',
      {'email': email, 'code': code, 'newPassword': newPassword},
      onStatus: onStatus,
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '验证码错误或已过期';
      }
      throw '重置密码失败: ${response.statusCode}';
    }
  }
}

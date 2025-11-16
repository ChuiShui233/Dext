import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/captcha.dart';
import 'api_core.dart';

class CaptchaService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, {StatusCallback? onStatus}) httpRequest;
  
  CaptchaService({required this.baseUrl, required this.httpRequest});

  Future<CaptchaSession> getCaptcha({StatusCallback? onStatus}) async {
    final response = await httpRequest('POST', '$baseUrl/api/getCaptcha', onStatus: onStatus);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // 后端返回格式: {code: 1, data: "base64...", captchaId: "xxx", msg: "..."}
      if (data['code'] == 1) {
        return CaptchaSession(
          token: data['captchaId'] ?? '',
          originalImageBase64: data['data'] ?? '',
          jigsawImageBase64: '',
          secretKey: '',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );
      }
      throw data['msg'] ?? '获取验证码失败';
    }
    throw '获取验证码失败: ${response.statusCode}';
  }
}

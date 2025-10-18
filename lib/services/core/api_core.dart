import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto_service.dart';

enum RequestStatus { idle, loading, success, error }

typedef ProgressCallback = void Function(int sent, int total);
typedef StatusCallback = void Function(RequestStatus status, String? message);

class ApiCore {
  ApiCore({this.authToken});

  static const String baseUrl = apiBaseUrl;
  static const Duration timeoutDuration = Duration(seconds: 15);

  String? authToken;
  final CryptoService _cryptoService = CryptoService();

  RequestStatus _currentStatus = RequestStatus.idle;
  String? _lastErrorMessage;
  final StreamController<RequestStatus> _statusController = StreamController<RequestStatus>.broadcast();
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _dataUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  RequestStatus get currentStatus => _currentStatus;
  String? get lastErrorMessage => _lastErrorMessage;
  Stream<RequestStatus> get statusStream => _statusController.stream;
  Stream<String> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get dataUpdateStream => _dataUpdateController.stream;

  void dispose() {
    _statusController.close();
    _messageController.close();
    _dataUpdateController.close();
  }

  void updateStatus(RequestStatus status, [String? message]) {
    _currentStatus = status;
    _lastErrorMessage = message;
    _statusController.add(status);
    if (message != null) _messageController.add(message);
  }

  void notifyDataUpdate(String type, dynamic data) {
    _dataUpdateController.add({
      'type': type,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void updateAuthToken(String? token) {
    authToken = token;
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  Future<http.Response> httpRequest(
    String method,
    String url, {
    Map<String, dynamic>? data,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在发送请求...');
      updateStatus(RequestStatus.loading, '正在发送请求...');

      final uri = Uri.parse(url);
      http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(timeoutDuration);
          break;
        case 'POST':
          response = await http
              .post(uri, headers: headers, body: data != null ? json.encode(data) : null)
              .timeout(timeoutDuration);
          break;
        case 'PUT':
          response = await http
              .put(uri, headers: headers, body: data != null ? json.encode(data) : null)
              .timeout(timeoutDuration);
          break;
        case 'DELETE':
          if (data != null) {
            response = await http
                .delete(uri, headers: headers, body: json.encode(data))
                .timeout(timeoutDuration);
          } else {
            response = await http.delete(uri, headers: headers).timeout(timeoutDuration);
          }
          break;
        default:
          throw '不支持的HTTP方法: $method';
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        onStatus?.call(RequestStatus.success, '请求成功');
        updateStatus(RequestStatus.success, '请求成功');
      } else {
        final errorMsg = '请求失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        updateStatus(RequestStatus.error, errorMsg);
      }

      return response;
    } catch (e) {
      final msg = _formatErrorMessage(e);
      onStatus?.call(RequestStatus.error, msg);
      updateStatus(RequestStatus.error, msg);
      rethrow;
    }
  }

  Future<http.Response> encryptedRequest(
    String method,
    String url,
    Map<String, dynamic>? data, {
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在准备请求...');
      updateStatus(RequestStatus.loading, '正在准备请求...');

      await _cryptoService.initialize();

      onStatus?.call(RequestStatus.loading, '正在加密数据...');
      updateStatus(RequestStatus.loading, '正在加密数据...');

      final reqHeaders = {
        ...headers,
        'X-Encrypted': 'rsa',
      };

      String? encryptedBody;
      if (data != null) {
        encryptedBody = await _cryptoService.encryptBody(data);
      }

      onStatus?.call(RequestStatus.loading, '正在发送请求...');
      updateStatus(RequestStatus.loading, '正在发送请求...');

      final uri = Uri.parse(url);
      final request = http.Request(method, uri);
      request.headers.addAll(reqHeaders);
      if (encryptedBody != null) request.body = encryptedBody;

      final streamedResponse = await request.send().timeout(timeoutDuration);

      onStatus?.call(RequestStatus.loading, '正在接收响应...');
      updateStatus(RequestStatus.loading, '正在接收响应...');

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        onStatus?.call(RequestStatus.success, '请求成功');
        updateStatus(RequestStatus.success, '请求成功');
      } else {
        final errorMsg = '请求失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        updateStatus(RequestStatus.error, errorMsg);
      }

      return response;
    } catch (e) {
      final msg = _formatErrorMessage(e);
      onStatus?.call(RequestStatus.error, msg);
      updateStatus(RequestStatus.error, msg);
      rethrow;
    }
  }

  String _formatErrorMessage(dynamic error) {
    final errorStr = error.toString();
    
    if (errorStr.contains('HandshakeException') || 
        errorStr.contains('Connection terminated during handshake')) {
      return '服务端维护中，请稍后再试';
    }
    
    if (errorStr.contains('Connection refused') || 
        errorStr.contains('Failed to connect')) {
      return '无法连接到服务器，服务端维护中';
    }
    
    if (errorStr.contains('CERTIFICATE_VERIFY_FAILED') ||
        errorStr.contains('certificate')) {
      return '服务器证书验证失败，请检查网络环境';
    }
    
    if (errorStr.contains('Timeout') || errorStr.contains('超时')) {
      return '请求超时，请检查您的网络连接';
    }
    
    if (errorStr.contains('Network is unreachable') ||
        errorStr.contains('SocketException')) {
      return '网络连接失败，请检查您的网络';
    }

    return '请求失败: $error';
  }

  // 统一提供 SharedPreferences 实例（便于未来替换）
  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';

import '../crypto_service.dart';
import 'XChaCha.dart';

enum RequestStatus { idle, loading, success, error }

typedef ProgressCallback = void Function(int sent, int total);
typedef StatusCallback = void Function(RequestStatus status, String? message);

class ApiCore {
  ApiCore({this.authToken});

  static const String baseUrl = apiBaseUrl;
  static const Duration timeoutDuration = Duration(seconds: 15);

  String? authToken;
  final CryptoService _cryptoService = CryptoService();
  String? _remotePublicKeyBase64; // 缓存的远程公钥（X25519）

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

      // 为支持加密响应，GET 或无请求体的请求将附带客户端临时公钥
      final upperMethod = method.toUpperCase();
      final isBodyMethod = upperMethod == 'POST' || upperMethod == 'PUT' || upperMethod == 'DELETE';
      final hasData = data != null;

      SimpleKeyPair? localEphemeralKeyPair; // 仅在需要加密响应时生成
      Map<String, String> reqHeaders = Map.of(headers);

      if (!isBodyMethod || !hasData) {
        // GET 或无Body请求：携带客户端临时公钥以启用服务端加密响应
        await _cryptoService.initialize();
        localEphemeralKeyPair = await SecurePacketFormatter.generateEphemeralKeyPair();
        final localPub = await localEphemeralKeyPair.extractPublicKey();
        reqHeaders['X-Encrypted'] = 'xchacha';
        reqHeaders['X-Client-Ephemeral-Key'] = base64Encode(localPub.bytes);
      }

      switch (upperMethod) {
        case 'GET':
          response = await http.get(uri, headers: reqHeaders).timeout(timeoutDuration);
          break;
        case 'POST':
          response = await http
              .post(uri, headers: reqHeaders, body: data != null ? json.encode(data) : null)
              .timeout(timeoutDuration);
          break;
        case 'PUT':
          response = await http
              .put(uri, headers: reqHeaders, body: data != null ? json.encode(data) : null)
              .timeout(timeoutDuration);
          break;
        case 'DELETE':
          if (data != null) {
            response = await http
                .delete(uri, headers: reqHeaders, body: json.encode(data))
                .timeout(timeoutDuration);
          } else {
            response = await http.delete(uri, headers: reqHeaders).timeout(timeoutDuration);
          }
          break;
        default:
          throw '不支持的HTTP方法: $method';
      }

      // 如服务端启用了加密响应，则在此解密
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.headers['x-encrypted'] == 'xchacha' || response.headers['X-Encrypted'] == 'xchacha') {
          try {
            if (localEphemeralKeyPair != null) {
              final Map<String, dynamic> respJson = json.decode(response.body) as Map<String, dynamic>;
              final String? eph = respJson['ephemeralPublicKey'] as String?;
              final String? pkt = respJson['packet'] as String?;
              if (eph != null && pkt != null) {
                final remoteEphemeralKey = base64Decode(eph);
                final encryptedPacket = base64Decode(pkt);
                final sessionKey = await SecurePacketFormatter.deriveSessionKey(
                  localEphemeralKeyPair,
                  remoteEphemeralKey,
                );
                final decryptedBytes = await SecurePacketFormatter.decryptPacket(
                  sessionKey,
                  encryptedPacket,
                );
                final decryptedBody = utf8.decode(decryptedBytes);
                response = http.Response(
                  decryptedBody,
                  response.statusCode,
                  headers: response.headers,
                  request: response.request,
                );
              }
            }
          } catch (_) {
            // 解密失败则返回原始响应
          }
        }

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

      onStatus?.call(RequestStatus.loading, '正在获取加密密钥...');
      updateStatus(RequestStatus.loading, '正在获取加密密钥...');

      final reqHeaders = {
        ...headers,
        'X-Encrypted': 'xchacha',
        'Content-Type': 'application/json',
      };

      onStatus?.call(RequestStatus.loading, '正在加密数据...');
      updateStatus(RequestStatus.loading, '正在加密数据...');

      String? encryptedBody;
      SimpleKeyPair? localEphemeralKeyPair; // 保存本地临时密钥对用于响应解密
      if (data != null) {
        // 获取远程公钥（X25519）
        final remotePublicKey = await _getRemotePublicKey();
        final remotePublicKeyBytes = base64Decode(remotePublicKey);
        // 生成本地临时密钥对并导出公钥
        localEphemeralKeyPair = await SecurePacketFormatter.generateEphemeralKeyPair();
        // 派生会话密钥
        final sessionKey = await SecurePacketFormatter.deriveSessionKey(
          localEphemeralKeyPair,
          remotePublicKeyBytes,
        );
        // 加密请求体
        final jsonBytes = utf8.encode(json.encode(data));
        final encryptedPacket = await SecurePacketFormatter.encryptPacket(
          sessionKey,
          jsonBytes,
        );
        final localPublicKey = await localEphemeralKeyPair.extractPublicKey();
        final payload = XChaChaEncryptedPayload(
          ephemeralPublicKey: base64Encode(localPublicKey.bytes),
          packet: base64Encode(encryptedPacket),
        );
        encryptedBody = json.encode(payload.toJson());
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

      // 处理加密响应（如有）
      http.Response decryptedResponse = response;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // 检查响应是否为 xchacha 加密
        if (response.headers['x-encrypted'] == 'xchacha' ||
            response.headers['X-Encrypted'] == 'xchacha') {
          try {
            final Map<String, dynamic> respJson = json.decode(response.body) as Map<String, dynamic>;
            final String? eph = respJson['ephemeralPublicKey'] as String?;
            final String? pkt = respJson['packet'] as String?;
            if (eph != null && pkt != null && localEphemeralKeyPair != null) {
              final remoteEphemeralKey = base64Decode(eph);
              final encryptedPacket = base64Decode(pkt);
              final sessionKey = await SecurePacketFormatter.deriveSessionKey(
                localEphemeralKeyPair,
                remoteEphemeralKey,
              );
              final decryptedBytes = await SecurePacketFormatter.decryptPacket(
                sessionKey,
                encryptedPacket,
              );
              final decryptedBody = utf8.decode(decryptedBytes);
              decryptedResponse = http.Response(
                decryptedBody,
                response.statusCode,
                headers: response.headers,
                request: response.request,
              );
            }
          } catch (_) {
            // 解密失败则返回原始响应
          }
        }

        onStatus?.call(RequestStatus.success, '请求成功');
        updateStatus(RequestStatus.success, '请求成功');
      } else {
        final errorMsg = '请求失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        updateStatus(RequestStatus.error, errorMsg);
      }

      return decryptedResponse;
    } catch (e) {
      final msg = _formatErrorMessage(e);
      onStatus?.call(RequestStatus.error, msg);
      updateStatus(RequestStatus.error, msg);
      rethrow;
    }
  }

  // 获取远程公钥（用于 XChaCha 加密）
  Future<String> _getRemotePublicKey() async {
    if (_remotePublicKeyBase64 != null && _remotePublicKeyBase64!.isNotEmpty) {
      return _remotePublicKeyBase64!;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/crypto/public-key'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['publicKey'] != null) {
          _remotePublicKeyBase64 = data['publicKey'] as String;
          return _remotePublicKeyBase64!;
        }
      }
    } catch (_) {}

    throw Exception('无法获取远程公钥，请检查网络连接');
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

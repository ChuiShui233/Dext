// Modified by ChuiShui12 on 2025/07/02.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import '/services/crypto_service.dart';
import 'core/api_core.dart' as core;
import 'auth_service.dart';
import 'project_service.dart';
import 'survey_service.dart';
import '../models/project.dart';
import '../models/survey.dart';
import '../models/survey_stats.dart';
import '../models/question.dart';
import '../models/captcha.dart';
import '../models/user.dart';
import '../models/survey_result.dart';
import '../models/paginated_response.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 令牌过期异常类
class TokenExpired {
  final String message;
  TokenExpired(this.message);
  
  @override
  String toString() => message;
}

// 统一复用 core 中的类型，避免类型不一致
typedef RequestStatus = core.RequestStatus;
typedef StatusCallback = core.StatusCallback;
typedef ProgressCallback = core.ProgressCallback;

class ApiService {
  static const String baseUrl = apiBaseUrl;
  static const Duration timeoutDuration = Duration(seconds: 15);
  // 全局401未授权处理回调（由应用在启动时注册）
  static VoidCallback? onUnauthorized;
  String? authToken;
  final CryptoService _cryptoService = CryptoService();
  // Facade over modular services
  late final core.ApiCore _core;
  late final AuthService _authService;
  late final ProjectService _projectService;
  late final SurveyService _surveyService;
  StreamSubscription<String>? _coreMsgSub;
  StreamSubscription<Map<String, dynamic>>? _coreDataSub;
  
  // 实时响应相关
  RequestStatus _currentStatus = RequestStatus.idle;
  String? _lastErrorMessage;
  final StreamController<RequestStatus> _statusController = StreamController<RequestStatus>.broadcast();
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  
  // 数据更新流 - 用于通知UI数据已更新
  final StreamController<Map<String, dynamic>> _dataUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  // 获取当前状态
  RequestStatus get currentStatus => _currentStatus;
  String? get lastErrorMessage => _lastErrorMessage;
  
  // 状态流
  Stream<RequestStatus> get statusStream => _statusController.stream;
  Stream<String> get messageStream => _messageController.stream;
  
  // 数据更新流
  Stream<Map<String, dynamic>> get dataUpdateStream => _dataUpdateController.stream;

  ApiService({this.authToken}) {
    // Initialize core and sub-services for modularization facade
    _core = core.ApiCore(authToken: authToken);
    _authService = AuthService(_core);
    _projectService = ProjectService(_core);
    _surveyService = SurveyService(_core);

    // Pipe core message/data streams to maintain compatibility with existing listeners
    _coreMsgSub = _core.messageStream.listen((m) => _messageController.add(m));
    _coreDataSub = _core.dataUpdateStream.listen((d) => _dataUpdateController.add(d));
  }

  // 确保 authToken 已加载（例如应用重启后从本地恢复）
  Future<void> _ensureAuthTokenLoaded() async {
    if (authToken == null || authToken!.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final t = prefs.getString('auth_token');
        if (t != null && t.isNotEmpty) {
          authToken = t;
          // 同步到核心请求层，保证后续请求带上 Authorization 头
          _core.updateAuthToken(authToken);
        }
        // 如果偏好存储没有，回退到安全存储（应用冷启动常见于此）
        if ((authToken == null || authToken!.isEmpty)) {
          try {
            const storage = FlutterSecureStorage();
            final st = await storage.read(key: 'auth_token');
            if (st != null && st.isNotEmpty) {
              authToken = st;
              // 回写到 SharedPreferences，便于后续快速加载
              await prefs.setString('auth_token', st);
              // 同步到核心请求层
              _core.updateAuthToken(authToken);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  // 最近提交列表（用于仪表盘卡片）
  Future<List<Map<String, dynamic>>> getRecentSubmissions({StatusCallback? onStatus}) async {
    try {
      final url = '$baseUrl/api/survey/recent-submissions';
      final response = await _httpRequest('GET', url, onStatus: onStatus);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final submissions = (data['submissions'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        return submissions;
      } else if (response.statusCode == 401) {
        throw response;
      } else {
        throw '获取最近提交失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 分析概览：总浏览数 / 总提交数
  Future<Map<String, int>> getAnalyticsOverview({StatusCallback? onStatus}) async {
    try {
      final response = await _httpRequest('GET', '$baseUrl/api/analytics/overview', onStatus: onStatus);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return {
          'totalViews': (data['totalViews'] as num?)?.toInt() ?? 0,
          'totalSubmits': (data['totalSubmits'] as num?)?.toInt() ?? 0,
        };
      } else if (response.statusCode == 401) {
        throw response;
      } else {
        throw '获取统计概览失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 判定是否为媒体相关或应排除AES加密的URL
  bool _isMediaUrl(String url) {
    // 排除真正的媒体相关（二进制/表单）接口，避免破坏上传/下载
    if (url.contains('/openassets/')) return true; // 统一的文件存储服务
    if (url.contains('/images/')) return true;     // 图像管理上传/删除
    if (url.contains('/uploads')) return true;     // 静态上传目录
    // 仅排除问卷媒体文件接口：/survey/:surveyId/media
    if (url.contains('/survey/') && url.contains('/media')) return true;
    return false;
  }

  // 提交趋势：range = '7d' | 'month'，默认 '7d'
  Future<Map<String, dynamic>> getSubmitTrend({String range = '7d', StatusCallback? onStatus}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/analytics/submit-trend').replace(queryParameters: {'range': range});
      final response = await _httpRequest('GET', uri.toString(), onStatus: onStatus);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        throw response;
      } else {
        throw '获取提交趋势失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 提交详情：返回题目、选项与我的作答
  Future<Map<String, dynamic>> getSubmissionDetail(int answerId, {StatusCallback? onStatus}) async {
    try {
      final url = '$baseUrl/api/survey/submissions/$answerId/detail';
      final response = await _httpRequest('GET', url, onStatus: onStatus);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        throw response;
      } else {
        throw '获取提交详情失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 提交记录查询（带筛选和分页）
  Future<Map<String, dynamic>> getSubmissionHistory({
    String? query,
    int? type,
    int page = 1,
    int pageSize = 20,
    StatusCallback? onStatus,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (query != null && query.trim().isNotEmpty) params['query'] = query.trim();
      if (type != null) params['type'] = type.toString();

      final uri = Uri.parse('$baseUrl/api/survey/submissions/history').replace(queryParameters: params);
      final response = await _httpRequest('GET', uri.toString(), onStatus: onStatus);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data;
      } else if (response.statusCode == 401) {
        throw response;
      } else {
        throw '获取提交记录失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 更新状态并通知监听者
  void _updateStatus(RequestStatus status, [String? message]) {
    _currentStatus = status;
    _lastErrorMessage = message;
    _statusController.add(status);
    if (message != null) {
      _messageController.add(message);
    }
  }
  
  // 通知数据更新
  void _notifyDataUpdate(String dataType, dynamic data) {
    _dataUpdateController.add({
      'type': dataType,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // 释放资源
  void dispose() {
    _statusController.close();
    _messageController.close();
    _dataUpdateController.close();
    _coreMsgSub?.cancel();
    _coreDataSub?.cancel();
    _core.dispose();
  }

  // 登录方法 - 支持RSA+AES混合加密
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在登录...');
      _updateStatus(RequestStatus.loading, '正在登录...');

      await _cryptoService.initialize();
      
      // 生成会话密钥
      onStatus?.call(RequestStatus.loading, '正在生成会话密钥...');
      _updateStatus(RequestStatus.loading, '正在生成会话密钥...');
      
      final sessionKey = _cryptoService.generateSessionKey();
      final encryptedSessionKey = await _cryptoService.encryptSessionKey(sessionKey);

      // 使用混合加密发送登录请求
      final response = await _hybridEncryptedRequest(
        'POST',
        '$baseUrl/api/auth/login',
        {
          'username': username,
          'password': password,
          'captchaId': captchaId,
          'captchaValue': captchaValue,
          'sessionKey': encryptedSessionKey,
        },
        sessionKey: sessionKey,
        onStatus: onStatus,
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> responseData;
        
        // 检查响应是否加密
        
        // 检查响应内容是否为二进制数据（可能是加密的）
        bool isEncrypted = response.headers['x-encrypted'] == 'aes' || 
                          response.body.contains('\u0000') || 
                          response.body.codeUnits.any((unit) => unit > 127);
        
        if (isEncrypted) {
          // 解密AES加密的响应
          onStatus?.call(RequestStatus.loading, '正在解密响应...');
          _updateStatus(RequestStatus.loading, '正在解密响应...');
          
          try {
            final encryptedResponse = response.bodyBytes;
            
            final decryptedBytes = _cryptoService.decryptWithAES(encryptedResponse, sessionKey);
            final decryptedJson = utf8.decode(decryptedBytes);
            
            responseData = json.decode(decryptedJson);
          } catch (e) {
            throw '响应解密失败: $e';
          }
        } else {
          // 未加密的响应（向后兼容）
          responseData = json.decode(response.body);
        }
        
        final token = responseData['token'];
        final expires = DateTime.parse(responseData['expires']);
        
        // 持久化并同步内存 token
        authToken = token?.toString();
        // 同步到核心请求层，避免加密/普通请求缺少 Authorization 头
        _core.updateAuthToken(authToken);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', authToken ?? '');
          await prefs.setString('auth_token_expires', expires.toIso8601String());
        } catch (_) {}
        
        onStatus?.call(RequestStatus.success, '登录成功');
        _updateStatus(RequestStatus.success, '登录成功');
        
        return {
          'token': token,
          'expires': expires,
        };
      } else {
        Map<String, dynamic> responseData;
        
        // 检查错误响应是否也加密了
        
        if (response.headers['x-encrypted'] == 'aes') {
          try {
            final encryptedResponse = response.bodyBytes;
            final decryptedBytes = _cryptoService.decryptWithAES(encryptedResponse, sessionKey);
            final decryptedJson = utf8.decode(decryptedBytes);
            responseData = json.decode(decryptedJson);
          } catch (e) {
            // 解密失败，尝试直接解析
            try {
              responseData = json.decode(response.body);
            } catch (jsonError) {
              responseData = {'message': '响应解析失败', 'error': response.body};
            }
          }
        } else {
          try {
            responseData = json.decode(response.body);
          } catch (jsonError) {
            responseData = {'message': '响应解析失败', 'error': response.body};
          }
        }
        
        final errorMessage = responseData['message'] ?? responseData['error'] ?? '登录失败';
        
        onStatus?.call(RequestStatus.error, errorMessage);
        _updateStatus(RequestStatus.error, errorMessage);
        
        throw errorMessage;
      }
    } catch (e) {
      
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 注册方法
  Future<void> register({
    required String username,
    required String password,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在注册...');
      _updateStatus(RequestStatus.loading, '正在注册...');

      final response = await _encryptedRequest(
        'POST',
        '$baseUrl/api/auth/register',
        {
          'username': username,
          'password': password,
          'captchaId': captchaId,
          'captchaValue': captchaValue,
        },
        onStatus: onStatus,
      );

      if (response.statusCode == 201) {
        onStatus?.call(RequestStatus.success, '注册成功');
        _updateStatus(RequestStatus.success, '注册成功');
      } else {
        final responseData = json.decode(response.body);
        final errorMessage = responseData['message'] ?? responseData['error'] ?? '注册失败';
        
        onStatus?.call(RequestStatus.error, errorMessage);
        _updateStatus(RequestStatus.error, errorMessage);
        
        throw errorMessage;
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 缓存管理方法
  Future<void> clearCache({String? specificKey}) async {
    final prefs = await SharedPreferences.getInstance();
    if (specificKey != null) {
      await prefs.remove(specificKey);
      _updateStatus(RequestStatus.success, '指定缓存已清除');
    } else {
      // 清除所有相关缓存
      await prefs.remove('projects_cache');
      await prefs.remove('surveys_cache');
      await prefs.remove('survey_stats_cache');
      // 清除所有问题缓存
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('questions_')) {
          await prefs.remove(key);
        }
      }
      _updateStatus(RequestStatus.success, '所有缓存已清除');
    }
  }

  // 强制刷新数据（忽略缓存）
  Future<List<Project>> forceRefreshProjects({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'projects_cache';
    await prefs.remove(cacheKey);
    return await _refreshProjects(prefs, cacheKey, onStatus: onStatus);
  }

  Future<List<Survey>> forceRefreshSurveys({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'surveys_cache';
    await prefs.remove(cacheKey);
    return await _refreshSurveys(prefs, cacheKey, onStatus: onStatus);
  }

  Future<List<SurveyStats>> forceRefreshSurveyStats({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'survey_stats_cache';
    await prefs.remove(cacheKey);
    return await _refreshAllSurveyStats(prefs, cacheKey, onStatus: onStatus);
  }

  Future<List<Question>> forceRefreshSurveyQuestions(
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'questions_$surveyId';
    await prefs.remove(cacheKey);
    return await _refreshSurveyQuestions(surveyId, prefs, cacheKey, onStatus: onStatus);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  // 加密请求方法（带实时响应）
  Future<http.Response> _encryptedRequest(
    String method,
    String url,
    Map<String, dynamic>? data, {
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
    bool allowRetry = true,
  }) async {
    try {
      await _ensureAuthTokenLoaded();
      onStatus?.call(RequestStatus.loading, '正在准备请求...');
      _updateStatus(RequestStatus.loading, '正在准备请求...');
      
      await _cryptoService.initialize();
      
      onStatus?.call(RequestStatus.loading, '正在加密数据...');
      _updateStatus(RequestStatus.loading, '正在加密数据...');
      
      final headers = {
        ..._headers,
        'X-Encrypted': 'rsa',
      };

      String? encryptedBody;
      if (data != null) {
        encryptedBody = await _cryptoService.encryptBody(data);
      }

      onStatus?.call(RequestStatus.loading, '正在发送请求...');
      _updateStatus(RequestStatus.loading, '正在发送请求...');

      final uri = Uri.parse(url);
      final request = http.Request(method, uri);
      request.headers.addAll(headers);
      if (encryptedBody != null) {
        request.body = encryptedBody;
      }

      final streamedResponse = await request.send().timeout(timeoutDuration);
      
      onStatus?.call(RequestStatus.loading, '正在接收响应...');
      _updateStatus(RequestStatus.loading, '正在接收响应...');
      
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        onStatus?.call(RequestStatus.success, '请求成功');
        _updateStatus(RequestStatus.success, '请求成功');
      } else if (response.statusCode == 401 && allowRetry) {
        final refreshed = await _refreshToken();
        if (refreshed) {
          return await _encryptedRequest(method, url, data, onProgress: onProgress, onStatus: onStatus, allowRetry: false);
        }
        final errorMsg = '请求失败: 401 (未授权)';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        if (ApiService.onUnauthorized != null) {
          ApiService.onUnauthorized!.call();
        }
      } else {
        final errorMsg = '请求失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
      }
      
      return response;
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '请求超时，请检查您的网络连接。';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      } else {
        final errorMsg = '请求失败: $e';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    }
  }

  // 公共加密请求方法（带实时响应）
  Future<http.Response> encryptedRequest(
    String method,
    String url,
    Map<String, dynamic>? data, {
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
  }) async {
    return _encryptedRequest(method, url, data, onProgress: onProgress, onStatus: onStatus);
  }

  // 混合加密请求方法（RSA+AES）
  Future<http.Response> _hybridEncryptedRequest(
    String method,
    String url,
    Map<String, dynamic>? data, {
    required SessionKey sessionKey,
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
    bool allowRetry = true,
  }) async {
    try {
      await _ensureAuthTokenLoaded();
      onStatus?.call(RequestStatus.loading, '正在准备混合加密请求...');
      _updateStatus(RequestStatus.loading, '正在准备混合加密请求...');
      
      await _cryptoService.initialize();
      
      onStatus?.call(RequestStatus.loading, '正在加密数据...');
      _updateStatus(RequestStatus.loading, '正在加密数据...');
      
      final headers = {
        ..._headers,
        'X-Encrypted': 'hybrid',
        'Content-Type': 'application/json',
      };

      String? encryptedBody;
      if (data != null) {
        // 使用传统RSA加密方式（向后兼容登录接口）
        encryptedBody = await _cryptoService.encryptBody(data);
      }

      onStatus?.call(RequestStatus.loading, '正在发送请求...');
      _updateStatus(RequestStatus.loading, '正在发送请求...');

      final uri = Uri.parse(url);
      final request = http.Request(method, uri);
      request.headers.addAll(headers);
      if (encryptedBody != null) {
        request.body = encryptedBody;
      }

      final streamedResponse = await request.send().timeout(timeoutDuration);
      
      onStatus?.call(RequestStatus.loading, '正在接收响应...');
      _updateStatus(RequestStatus.loading, '正在接收响应...');
      
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        onStatus?.call(RequestStatus.success, '请求成功');
        _updateStatus(RequestStatus.success, '请求成功');
      } else if (response.statusCode == 401 && allowRetry) {
        final refreshed = await _refreshToken();
        if (refreshed) {
          return await _hybridEncryptedRequest(
            method, url, data, 
            sessionKey: sessionKey,
            onProgress: onProgress, 
            onStatus: onStatus, 
            allowRetry: false
          );
        }
        final errorMsg = '请求失败: 401 (未授权)';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        if (ApiService.onUnauthorized != null) {
          ApiService.onUnauthorized!.call();
        }
      } else {
        final errorMsg = '请求失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
      }
      
      return response;
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '请求超时，请检查您的网络连接。';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      } else {
        final errorMsg = '请求失败: $e';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    }
  }


  // 普通HTTP请求方法（带实时响应）
  Future<http.Response> _httpRequest(
    String method,
    String url, {
    Map<String, dynamic>? data,
    StatusCallback? onStatus,
    bool allowRetry = true,
  }) async {
    try {
      await _ensureAuthTokenLoaded();
      onStatus?.call(RequestStatus.loading, '正在发送请求...');
      _updateStatus(RequestStatus.loading, '正在发送请求...');
      
      final uri = Uri.parse(url);
      http.Response response;

      // 仅对有请求体的方法（POST/PUT/DELETE）尝试AES加密；GET保持原样
      final upperMethod = method.toUpperCase();
      final canEncryptBody = (upperMethod == 'POST' || upperMethod == 'PUT' || upperMethod == 'DELETE')
          && data != null
          && _cryptoService.currentSessionKey != null
          && !_isMediaUrl(url);

      if (canEncryptBody) {
        // 使用AES-GCM加密请求体
        final sessionKey = _cryptoService.currentSessionKey!;
        final jsonData = json.encode(data);
        final bodyBytes = Uint8List.fromList(utf8.encode(jsonData));
        final encryptedBody = _cryptoService.encryptWithAES(bodyBytes, sessionKey);

        final headers = <String, String>{
          ..._headers,
          'X-Encrypted': 'aes',
          'Content-Type': 'application/octet-stream',
        };

        switch (upperMethod) {
          case 'POST':
            response = await http
                .post(uri, headers: headers, body: encryptedBody)
                .timeout(timeoutDuration);
            break;
          case 'PUT':
            response = await http
                .put(uri, headers: headers, body: encryptedBody)
                .timeout(timeoutDuration);
            break;
          case 'DELETE':
            response = await http
                .delete(uri, headers: headers, body: encryptedBody)
                .timeout(timeoutDuration);
            break;
          default:
            throw '不支持的HTTP方法: $method';
        }
      } else {
        // 非加密路径（GET、无数据、媒体相关或无会话密钥时）保持原逻辑
        final headers = _headers;
        switch (upperMethod) {
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
      }
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        onStatus?.call(RequestStatus.success, '请求成功');
        _updateStatus(RequestStatus.success, '请求成功');
      } else if (response.statusCode == 401 && allowRetry) {
        // 尝试刷新令牌后重试一次
        final refreshed = await _refreshToken();
        if (refreshed) {
          return await _httpRequest(method, url, data: data, onStatus: onStatus, allowRetry: false);
        }
        final errorMsg = '请求失败: 401 (未授权)';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        // 通知应用处理登录过期
        if (ApiService.onUnauthorized != null) {
          ApiService.onUnauthorized!.call();
        }
      } else {
        final errorMsg = '请求失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
      }

      return response;
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '请求超时，请检查您的网络连接。';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      } else {
        final errorMsg = '请求失败: $e';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    }
  }

  // 自动刷新token并重试的通用方法
  Future<bool> _refreshToken() async {
    try {
      // 优先使用当前内存 token
      String? token = authToken;
      // 如无内存token，尝试从本地取
      if (token == null || token.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        token = prefs.getString('auth_token');
        if (token != null && token.isNotEmpty) {
          authToken = token;
          // rely on ApiService.authToken for headers
        }
      }
      
      // 检查是否有有效的token
      if (authToken == null || authToken!.isEmpty) {
        return false;
      }
      
      // 优先尝试使用 AES（需要已有会话密钥），否则回退到 RSA 加密
      http.Response resp;
      final refreshUrl = '$baseUrl/api/auth/refresh';
      final refreshData = {'refresh': true};
      try {
        if (_cryptoService.currentSessionKey != null) {
          // 优先 AES
          resp = await _httpRequest(
            'POST',
            refreshUrl,
            data: refreshData,
            allowRetry: false,
          );
          // 若会话丢失导致 401，自动回退到 RSA 重试
          if (resp.statusCode == 401) {
            resp = await _encryptedRequest(
              'POST',
              refreshUrl,
              refreshData,
              allowRetry: false,
            );
          }
        } else {
          // 无会话密钥时使用 RSA 加密
          resp = await _encryptedRequest(
            'POST',
            refreshUrl,
            refreshData,
            allowRetry: false,
          );
        }
      } catch (_) {
        return false;
      }

      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final newToken = body['token']?.toString();
        final expiresStr = body['expires']?.toString();
        if (newToken != null && newToken.isNotEmpty) {
          authToken = newToken;
          // 同步到核心请求层
          _core.updateAuthToken(authToken);
          // 清空 AES 会话密钥，促使后续请求重新协商
          _cryptoService.clearSessionKey();
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('auth_token', newToken);
            if (expiresStr != null) {
              await prefs.setString('auth_token_expires', expiresStr);
            }
          } catch (_) {}
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // 退出登录并清除本地令牌
  Future<void> logoutAndClear({StatusCallback? onStatus}) async {
    try {
      await _httpRequest('POST', '$baseUrl/api/auth/logout', onStatus: onStatus, allowRetry: false);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_expires');
    } catch (_) {}
    authToken = null;
    // rely on ApiService.authToken for headers
    _updateStatus(RequestStatus.success, '已退出登录');
  }

  /// 严格注销：仅当服务端成功返回时才视为成功，不做本地清理
  Future<void> logoutStrict({StatusCallback? onStatus}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在退出登录...');
      _updateStatus(RequestStatus.loading, '正在退出登录...');
      // 在有会话密钥时使用 AES，否则回退到 RSA 加密
      http.Response resp;
      if (_cryptoService.currentSessionKey != null) {
        resp = await _httpRequest(
          'POST',
          '$baseUrl/api/auth/logout',
          data: const {},
          onStatus: onStatus,
          allowRetry: false,
        );
      } else {
        resp = await _encryptedRequest(
          'POST',
          '$baseUrl/api/auth/logout',
          const {},
          onStatus: onStatus,
          allowRetry: false,
        );
      }
      if (resp.statusCode != 200) {
        throw '注销失败: ${resp.body}';
      }
      onStatus?.call(RequestStatus.success, '退出登录成功');
      _updateStatus(RequestStatus.success, '退出登录成功');
    } catch (e) {
      final msg = e.toString();
      onStatus?.call(RequestStatus.error, msg);
      _updateStatus(RequestStatus.error, msg);
      rethrow;
    }
  }

  // 项目相关API（带实时响应）
  Future<List<Project>> getProjects({StatusCallback? onStatus}) async {
    // Delegate to ProjectService (preserves signature)
    return await _projectService.getProjects(onStatus: onStatus);
  }

  Future<PaginatedResponse<Project>> getProjectsPaginated({
    int page = 1,
    int pageSize = 10,
    String? search,
    StatusCallback? onStatus,
  }) async {
    return await _projectService.getProjectsPaginated(
      page: page,
      pageSize: pageSize,
      search: search,
      onStatus: onStatus,
    );
  }

  Future<List<Project>> _refreshProjects(
    SharedPreferences prefs, 
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取项目列表...');
      _updateStatus(RequestStatus.loading, '正在获取项目列表...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/project/list',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body == null || body is! List) {
          onStatus?.call(RequestStatus.success, '项目列表为空');
          _updateStatus(RequestStatus.success, '项目列表为空');
          return [];
        }
        prefs.setString(cacheKey, json.encode(body));
        final projects = body.map<Project>((json) => Project.fromJson(json)).toList();
        
        onStatus?.call(RequestStatus.success, '项目列表获取成功');
        _updateStatus(RequestStatus.success, '项目列表获取成功');
        
        return projects;
      } else if (response.statusCode == 401) {
        throw response;
      } else {
        throw '获取项目列表失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  Future<Project> createProject(
    Project project, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在创建项目...');
      _updateStatus(RequestStatus.loading, '正在创建项目...');
      
    final response = await _encryptedRequest(
      'POST',
      '$baseUrl/api/project/add',
      project.toJson(),
        onStatus: onStatus,
    );
      
    if (response.statusCode == 201) {
        final createdProject = Project.fromJson(json.decode(response.body));
        
        // 创建成功后清除相关缓存
        await _clearProjectListCache();
        
        onStatus?.call(RequestStatus.success, '项目创建成功');
        _updateStatus(RequestStatus.success, '项目创建成功');
        return createdProject;
    } else {
      throw '创建项目失败: ${response.statusCode}';
    }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 清除项目列表相关缓存
  Future<void> _clearProjectListCache() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 清除项目列表缓存
    await prefs.remove('projects_cache');
    
    // 通知UI数据已更新
    _notifyDataUpdate('projects_updated', {'action': 'created'});
  }

  Future<void> updateProject(
    Project project, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在更新项目...');
      _updateStatus(RequestStatus.loading, '正在更新项目...');
      
    final response = await _encryptedRequest(
      'PUT',
      '$baseUrl/api/project/update',
      project.toJson(),
        onStatus: onStatus,
    );

      if (response.statusCode == 200) {
        // 更新成功后清除相关缓存
        await _clearProjectListCache();
        
        onStatus?.call(RequestStatus.success, '项目更新成功');
        _updateStatus(RequestStatus.success, '项目更新成功');
      } else {
      throw '更新项目失败: ${response.statusCode}';
    }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 问卷相关API（带实时响应）
  Future<List<Survey>> getSurveys({StatusCallback? onStatus}) async {
    return await _surveyService.getSurveys(onStatus: onStatus);
  }

  Future<PaginatedResponse<Survey>> getSurveysPaginated({
    int page = 1,
    int pageSize = 5,
    String? search,
    String? type,
    StatusCallback? onStatus,
  }) async {
    return await _surveyService.getSurveysPaginated(
      page: page,
      pageSize: pageSize,
      search: search,
      type: type,
      onStatus: onStatus,
    );
  }



  Future<List<Survey>> _refreshSurveys(
    SharedPreferences prefs, 
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取问卷列表...');
      _updateStatus(RequestStatus.loading, '正在获取问卷列表...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/list',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body == null || body is! List) {
          onStatus?.call(RequestStatus.success, '问卷列表为空');
          _updateStatus(RequestStatus.success, '问卷列表为空');
          return [];
        }
        prefs.setString(cacheKey, json.encode(body));
        final surveys = body.map<Survey>((json) => Survey.fromJson(json)).toList();
        
        onStatus?.call(RequestStatus.success, '问卷列表获取成功');
        _updateStatus(RequestStatus.success, '问卷列表获取成功');
        
        return surveys;
      } else {
        throw '获取问卷列表失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  Future<Survey> createSurvey(
    Survey survey, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在创建问卷...');
      _updateStatus(RequestStatus.loading, '正在创建问卷...');
      
    final response = await _encryptedRequest(
      'POST',
      '$baseUrl/api/survey/add',
      survey.toJson(),
        onStatus: onStatus,
    );
    
    if (response.statusCode == 201) {
        final createdSurvey = Survey.fromJson(json.decode(response.body));
        
        // 创建成功后清除相关缓存
        await _clearSurveyListCache();
        
        onStatus?.call(RequestStatus.success, '问卷创建成功');
        _updateStatus(RequestStatus.success, '问卷创建成功');
        return createdSurvey;
    } else {
      throw '创建问卷失败: ${response.statusCode}';
    }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 清除问卷列表相关缓存
  Future<void> _clearSurveyListCache() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 清除问卷列表缓存
    await prefs.remove('surveys_cache');
    
    // 清除问卷统计数据缓存
    await prefs.remove('survey_stats_cache');
    
    // 通知UI数据已更新
    _notifyDataUpdate('surveys_updated', {'action': 'created'});
    _notifyDataUpdate('survey_stats_updated', {'action': 'created'});
  }

  Future<Survey> updateSurvey(
    Survey survey, {
    StatusCallback? onStatus,
  }) async {
    // Delegate to SurveyService
    return await _surveyService.updateSurvey(survey, onStatus: onStatus);
  }

  Future<void> deleteSurvey(
    int id, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在删除问卷...');
      _updateStatus(RequestStatus.loading, '正在删除问卷...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/survey/delete/$id',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        // 删除成功后清除相关缓存
        await _clearSurveyRelatedCache(id);
        
        onStatus?.call(RequestStatus.success, '问卷删除成功');
        _updateStatus(RequestStatus.success, '问卷删除成功');
      } else {
        throw '删除问卷失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 批量删除问卷
  Future<void> batchDeleteSurveys(
    List<int> surveyIds, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在批量删除问卷...');
      _updateStatus(RequestStatus.loading, '正在批量删除问卷...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/survey/batch-delete',
        data: {'surveyIds': surveyIds},
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        // 删除成功后清除相关缓存
        for (final surveyId in surveyIds) {
          await _clearSurveyRelatedCache(surveyId);
        }
        
        onStatus?.call(RequestStatus.success, '批量删除问卷成功');
        _updateStatus(RequestStatus.success, '批量删除问卷成功');
      } else {
        throw '批量删除问卷失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 清除问卷相关的缓存
  Future<void> _clearSurveyRelatedCache(int surveyId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 清除问卷列表缓存
    await prefs.remove('surveys_cache');
    
    // 清除问卷统计数据缓存
    await prefs.remove('survey_stats_cache');
    
    // 清除该问卷的问题缓存
    await prefs.remove('questions_$surveyId');
    
    // 通知UI数据已更新，强制刷新
    _notifyDataUpdate('surveys_deleted', {'deletedId': surveyId});
    _notifyDataUpdate('survey_stats_deleted', {'deletedId': surveyId});
    _notifyDataUpdate('questions_deleted', {'deletedId': surveyId});
  }

  Future<void> deleteProject(
    int id, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在删除项目...');
      _updateStatus(RequestStatus.loading, '正在删除项目...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/project/delete/$id',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        // 删除成功后清除相关缓存
        await _clearProjectRelatedCache(id);
        
        onStatus?.call(RequestStatus.success, '项目删除成功');
        _updateStatus(RequestStatus.success, '项目删除成功');
      } else {
        throw '删除项目失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 批量删除项目
  Future<void> batchDeleteProjects(
    List<int> projectIds, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在批量删除项目...');
      _updateStatus(RequestStatus.loading, '正在批量删除项目...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/project/batch-delete',
        data: {'projectIds': projectIds},
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        // 删除成功后清除相关缓存
        for (final projectId in projectIds) {
          await _clearProjectRelatedCache(projectId);
        }
        
        onStatus?.call(RequestStatus.success, '批量删除项目成功');
        _updateStatus(RequestStatus.success, '批量删除项目成功');
      } else {
        throw '批量删除项目失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 清除项目相关的缓存
  Future<void> _clearProjectRelatedCache(int projectId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 清除项目列表缓存
    await prefs.remove('projects_cache');
    
    // 清除问卷列表缓存（因为项目删除可能影响问卷）
    await prefs.remove('surveys_cache');
    
    // 清除问卷统计数据缓存
    await prefs.remove('survey_stats_cache');
    
    // 通知UI数据已更新，强制刷新
    _notifyDataUpdate('projects_deleted', {'deletedId': projectId});
    _notifyDataUpdate('surveys_deleted', {'deletedId': projectId});
    _notifyDataUpdate('survey_stats_deleted', {'deletedId': projectId});
  }

  // 问卷统计相关API（带实时响应）
  Future<SurveyStats> getSurveyStats(
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取问卷统计...');
      _updateStatus(RequestStatus.loading, '正在获取问卷统计...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/stats/$surveyId',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final stats = SurveyStats.fromJson(json.decode(response.body));
        onStatus?.call(RequestStatus.success, '问卷统计获取成功');
        _updateStatus(RequestStatus.success, '问卷统计获取成功');
        return stats;
      } else {
        throw '获取问卷统计信息失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  Future<List<SurveyStats>> getAllSurveyStats({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'survey_stats_cache';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        _updateStatus(RequestStatus.loading, '正在加载缓存数据...');
        
        final List<dynamic> jsonList = json.decode(cached);
        final List<SurveyStats> stats = jsonList.map((e) => SurveyStats.fromJson(e)).toList();
        
        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        _updateStatus(RequestStatus.success, '缓存数据加载成功');
        
        // 异步刷新网络数据，使用独立的回调避免状态混乱
        _refreshAllSurveyStatsSilently(prefs, cacheKey, stats);
        return stats;
      } catch (e) {
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        _updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }
    return await _refreshAllSurveyStats(prefs, cacheKey, onStatus: onStatus);
  }

  // 静默刷新问卷统计数据（用于异步更新）
  Future<void> _refreshAllSurveyStatsSilently(
    SharedPreferences prefs, 
    String cacheKey,
    List<SurveyStats> cachedStats,
  ) async {
    try {
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/stats',
        onStatus: null, // 不使用回调，避免状态混乱
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body is List) {
          final newStats = body.map<SurveyStats>((jsonItem) {
            if (jsonItem is Map<String, dynamic>) {
              return SurveyStats.fromJson(jsonItem);
            } else {
              return SurveyStats(
                surveyId: 0,
                surveyName: '无效数据',
                viewCount: 0,
                submitCount: 0,
                submittedUsers: [],
                lastViewTime: DateTime(1970),
                lastSubmitTime: DateTime(1970),
              );
            }
          }).toList();
          
          // 检查数据是否有变化
          if (_hasSurveyStatsChanged(cachedStats, newStats)) {
            prefs.setString(cacheKey, json.encode(body));
            
            // 通知UI数据已更新
            _notifyDataUpdate('survey_stats', newStats);
            _updateStatus(RequestStatus.success, '问卷统计数据已更新');
          }
        }
      }
    } catch (e) {
      // 静默处理错误，不影响主流程
    }
  }
  
  // 检查问卷统计数据是否有变化
  bool _hasSurveyStatsChanged(List<SurveyStats> oldStats, List<SurveyStats> newStats) {
    if (oldStats.length != newStats.length) return true;
    
    for (int i = 0; i < oldStats.length; i++) {
      if (oldStats[i].surveyId != newStats[i].surveyId ||
          oldStats[i].viewCount != newStats[i].viewCount ||
          oldStats[i].submitCount != newStats[i].submitCount ||
          oldStats[i].lastViewTime != newStats[i].lastViewTime ||
          oldStats[i].lastSubmitTime != newStats[i].lastSubmitTime) {
        return true;
      }
    }
    return false;
  }

  Future<List<SurveyStats>> _refreshAllSurveyStats(
    SharedPreferences prefs, 
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取问卷统计列表...');
      _updateStatus(RequestStatus.loading, '正在获取问卷统计列表...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/stats',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body is List) {
          prefs.setString(cacheKey, json.encode(body));
          final stats = body.map<SurveyStats>((jsonItem) {
            if (jsonItem is Map<String, dynamic>) {
              return SurveyStats.fromJson(jsonItem);
            } else {
              return SurveyStats(
                surveyId: 0,
                surveyName: '无效数据',
                viewCount: 0,
                submitCount: 0,
                submittedUsers: [],
                lastViewTime: DateTime(1970),
                lastSubmitTime: DateTime(1970),
              );
            }
          }).toList();
          
          onStatus?.call(RequestStatus.success, '问卷统计列表获取成功');
          _updateStatus(RequestStatus.success, '问卷统计列表获取成功');
          
          return stats;
        } else {
          onStatus?.call(RequestStatus.success, '问卷统计列表为空');
          _updateStatus(RequestStatus.success, '问卷统计列表为空');
          return [];
        }
      } else {
        throw '获取问卷统计信息失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 刷新认证token（带实时响应）
  Future<String> refreshToken({StatusCallback? onStatus}) async {
    // Delegate to AuthService
    return await _authService.refreshToken(onStatus: onStatus);
  }

  // 检查令牌是否有效
  Future<bool> isTokenValid({StatusCallback? onStatus}) async {
    try {
      if (authToken == null || authToken!.isEmpty) {
        return false;
      }

      onStatus?.call(RequestStatus.loading, '正在验证令牌...');
      _updateStatus(RequestStatus.loading, '正在验证令牌...');

      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/user/current',
        onStatus: onStatus,
      );

      if (response.statusCode == 200) {
        onStatus?.call(RequestStatus.success, '令牌验证成功');
        _updateStatus(RequestStatus.success, '令牌验证成功');
        return true;
      } else if (response.statusCode == 401) {
        onStatus?.call(RequestStatus.error, '令牌已失效');
        _updateStatus(RequestStatus.error, '令牌已失效');
        return false;
      } else {
        onStatus?.call(RequestStatus.error, '令牌验证失败');
        _updateStatus(RequestStatus.error, '令牌验证失败');
        return false;
      }
    } catch (e) {
      onStatus?.call(RequestStatus.error, '令牌验证异常: $e');
      _updateStatus(RequestStatus.error, '令牌验证异常: $e');
      return false;
    }
  }

  // 强制重新登录
  Future<String> forceReLogin({
    required String username,
    required String password,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在重新登录...');
      _updateStatus(RequestStatus.loading, '正在重新登录...');

      final response = await _encryptedRequest(
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
        final Map<String, dynamic> data = json.decode(response.body);
        final token = data['token'] as String;
        
        onStatus?.call(RequestStatus.success, '重新登录成功');
        _updateStatus(RequestStatus.success, '重新登录成功');
        
        return token;
      } else {
        final errorMsg = '重新登录失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  Future getProjectStats(int id) async {}

  // 问卷内容相关API（带实时响应）
  Future<List<Question>> getSurveyQuestions(
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'questions_$surveyId';
    // 先尝试读取缓存
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        _updateStatus(RequestStatus.loading, '正在加载缓存数据...');
        
        final List<dynamic> jsonList = json.decode(cached);
        final List<Question> questions = jsonList.map((e) => Question.fromJson(e)).toList();
        
        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        _updateStatus(RequestStatus.success, '缓存数据加载成功');
        
        // 异步刷新网络数据，使用独立的回调避免状态混乱
        _refreshSurveyQuestionsSilently(surveyId, prefs, cacheKey, questions);
        return questions;
      } catch (e) {
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        _updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }
    // 没有缓存或解析失败，走网络
    return await _refreshSurveyQuestions(surveyId, prefs, cacheKey, onStatus: onStatus);
  }

  // 静默刷新问卷问题数据（用于异步更新）
  Future<void> _refreshSurveyQuestionsSilently(
    int surveyId, 
    SharedPreferences prefs, 
    String cacheKey,
    List<Question> cachedQuestions,
  ) async {
    try {
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/$surveyId/questions',
        onStatus: null, // 不使用回调，避免状态混乱
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body == null || body is! List) {
          return;
        }
        
        final newQuestions = body.map<Question>((json) => Question.fromJson(json)).toList();
        
        // 检查数据是否有变化
        if (_hasQuestionsChanged(cachedQuestions, newQuestions)) {
          prefs.setString(cacheKey, json.encode(body));
          
          // 通知UI数据已更新
          _notifyDataUpdate('questions_$surveyId', newQuestions);
          _updateStatus(RequestStatus.success, '问卷问题数据已更新');
        }
      }
    } catch (e) {
      // 静默处理错误，不影响主流程
    }
  }
  
  // 检查问卷问题数据是否有变化
  bool _hasQuestionsChanged(List<Question> oldQuestions, List<Question> newQuestions) {
    if (oldQuestions.length != newQuestions.length) return true;
    
    for (int i = 0; i < oldQuestions.length; i++) {
      if (oldQuestions[i].id != newQuestions[i].id ||
          oldQuestions[i].title != newQuestions[i].title ||
          oldQuestions[i].type != newQuestions[i].type ||
          oldQuestions[i].order != newQuestions[i].order) {
        return true;
      }
    }
    return false;
  }

  Future<List<Question>> _refreshSurveyQuestions(
    int surveyId, 
    SharedPreferences prefs, 
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取问卷问题...');
      _updateStatus(RequestStatus.loading, '正在获取问卷问题...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/$surveyId/questions',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        
        if (body == null || body is! List) {
          onStatus?.call(RequestStatus.success, '问卷问题列表为空');
          _updateStatus(RequestStatus.success, '问卷问题列表为空');
          return [];
        }
        prefs.setString(cacheKey, json.encode(body));
        final questions = body.map<Question>((json) => Question.fromJson(json)).toList();
        
        onStatus?.call(RequestStatus.success, '问卷问题获取成功');
        _updateStatus(RequestStatus.success, '问卷问题获取成功');
        
        return questions;
      } else {
        throw '获取问卷问题列表失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }
Future<Question> addQuestion(
  int surveyId, 
  Question question, {
  StatusCallback? onStatus,
}) async {
  try {
    onStatus?.call(RequestStatus.loading, '正在添加问题...');
    _updateStatus(RequestStatus.loading, '正在添加问题...');


    final response = await _encryptedRequest(
      'POST',
      '$baseUrl/api/survey/$surveyId/question',
      question.toJson(),
      onStatus: onStatus,
    );

    if (response.statusCode == 201) {
      final addedQuestion = Question.fromJson(json.decode(response.body));
      
      // 添加成功后清除相关缓存
      await _clearQuestionCache(surveyId);

      onStatus?.call(RequestStatus.success, '问题添加成功');
      _updateStatus(RequestStatus.success, '问题添加成功');
      return addedQuestion;
    } else {
      throw '添加问题失败: ${response.statusCode}';
    }
  } catch (e) {
    final errorMsg = e.toString();
    onStatus?.call(RequestStatus.error, errorMsg);
    _updateStatus(RequestStatus.error, errorMsg);
    rethrow;
  }
}

  // 清除问题相关缓存
  Future<void> _clearQuestionCache(int surveyId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 清除该问卷的问题缓存
    await prefs.remove('questions_$surveyId');
    
    // 通知UI数据已更新
    _notifyDataUpdate('questions_updated', {'surveyId': surveyId, 'action': 'added'});
  }

  Future<Question> updateQuestion(
    int surveyId, 
    Question question, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在更新问题...');
      _updateStatus(RequestStatus.loading, '正在更新问题...');
      
    final response = await _encryptedRequest(
      'PUT',
      '$baseUrl/api/survey/$surveyId/question/${question.id}',
      question.toJson(),
        onStatus: onStatus,
    );
    
    if (response.statusCode == 200) {
        final updatedQuestion = Question.fromJson(json.decode(response.body));
        
        // 更新成功后清除相关缓存
        await _clearQuestionCache(surveyId);
        
        onStatus?.call(RequestStatus.success, '问题更新成功');
        _updateStatus(RequestStatus.success, '问题更新成功');
        return updatedQuestion;
    } else {
      throw '更新问题失败: ${response.statusCode}';
    }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  Future<void> deleteQuestion(
    int surveyId, 
    int questionId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在删除问题...');
      _updateStatus(RequestStatus.loading, '正在删除问题...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/survey/$surveyId/question/$questionId',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        // 删除成功后清除相关缓存
        await _clearQuestionCache(surveyId);
        
        onStatus?.call(RequestStatus.success, '问题删除成功');
        _updateStatus(RequestStatus.success, '问题删除成功');
      } else {
        throw '删除问题失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  Future<void> reorderQuestions(
    int surveyId, 
    List<int> questionIds, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在重新排序问题...');
      _updateStatus(RequestStatus.loading, '正在重新排序问题...');
      
    final response = await _encryptedRequest(
      'PUT',
      '$baseUrl/api/survey/$surveyId/questions/reorder',
      {'questionIds': questionIds},
        onStatus: onStatus,
    );
    
      if (response.statusCode == 200) {
        // 重新排序成功后清除相关缓存
        await _clearQuestionCache(surveyId);
        
        onStatus?.call(RequestStatus.success, '问题排序成功');
        _updateStatus(RequestStatus.success, '问题排序成功');
      } else {
      throw '重新排序问题失败: ${response.statusCode}';
    }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // Web平台专用的字节数据上传函数
  Future<String> uploadMediaBytes(
    int surveyId, 
    List<int> fileBytes,
    String fileName, {
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在准备上传文件...');
      _updateStatus(RequestStatus.loading, '正在准备上传文件...');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/survey/$surveyId/media'),
      );
      
      final Map<String, String> multipartHeaders = {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };
      request.headers.addAll(multipartHeaders);
      
      onStatus?.call(RequestStatus.loading, '正在准备文件...');
      _updateStatus(RequestStatus.loading, '正在准备文件...');
      
      final fileSize = fileBytes.length;
      
      if (fileSize == 0) {
        throw '文件为空，无法上传';
      }
      
      // 使用字节数据创建MultipartFile
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ));
      
      onStatus?.call(RequestStatus.loading, '正在上传文件...');
      _updateStatus(RequestStatus.loading, '正在上传文件...');
      
      final streamedResponse = await request.send();
      
      // 监听上传进度
      int uploadedBytes = 0;
      final responseBytes = <int>[];
      final startTime = DateTime.now();
      
      await for (final chunk in streamedResponse.stream) {
        responseBytes.addAll(chunk);
        uploadedBytes += chunk.length;
        
        // 计算进度
        final progress = (uploadedBytes / fileSize * 100).round();
        
        // 计算上传速度
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        final speed = elapsed > 0 ? (uploadedBytes / elapsed / 1024).round() : 0; // KB/s
        
        // 回调进度
        onProgress?.call(uploadedBytes, fileSize);
        onStatus?.call(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
        _updateStatus(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
      }
      
      // 构建响应
      final response = http.Response(
        utf8.decode(responseBytes),
        streamedResponse.statusCode,
        headers: streamedResponse.headers,
        request: streamedResponse.request,
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final url = data['publicUrl'] ?? data['url'] as String;
        
        final totalTime = DateTime.now().difference(startTime).inSeconds;
        final avgSpeed = totalTime > 0 ? (fileSize / totalTime / 1024).round() : 0;
        
        onStatus?.call(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        _updateStatus(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        
        return url;
      } else {
        final errorMsg = '上传媒体文件失败: ${response.statusCode}, Body: ${response.body}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '上传超时，请检查网络连接';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      } else {
        final errorMsg = e.toString();
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        rethrow;
      }
    }
  }

  // 通用上传方法，自动适配Web和移动端
  Future<String> uploadMediaUniversal(
    int surveyId, 
    {String? filePath,
    List<int>? fileBytes,
    String? fileName,
    ProgressCallback? onProgress,
    StatusCallback? onStatus}) async {
    
    // Web平台使用字节数据
    if (kIsWeb) {
      if (fileBytes == null || fileName == null) {
        throw 'Web平台需要提供文件字节数据和文件名';
      }
      return uploadMediaBytes(surveyId, fileBytes, fileName, 
          onProgress: onProgress, onStatus: onStatus);
    }
    
    // 桌面端优先使用字节数据，备选文件路径
    if (fileBytes != null && fileName != null) {
      return uploadMediaBytes(surveyId, fileBytes, fileName, 
          onProgress: onProgress, onStatus: onStatus);
    } else if (filePath != null) {
      return uploadMedia(surveyId, filePath, 
          onProgress: onProgress, onStatus: onStatus);
    } else {
      throw '需要提供文件路径或字节数据';
    }
  }

  // 删除媒体文件
  Future<void> deleteMediaFile(
    int surveyId, 
    String fileId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在删除媒体文件...');
      _updateStatus(RequestStatus.loading, '正在删除媒体文件...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/survey/$surveyId/media/$fileId',
      );
      
      if (response.statusCode == 200) {
        onStatus?.call(RequestStatus.success, '媒体文件删除成功');
        _updateStatus(RequestStatus.success, '媒体文件删除成功');
      } else {
        throw '删除媒体文件失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 通过文件名删除媒体文件
  Future<void> deleteMediaFileByName(
    int surveyId, 
    String fileName, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在查找媒体文件...');
      _updateStatus(RequestStatus.loading, '正在查找媒体文件...');
      
      // 先获取问卷的所有媒体文件
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/$surveyId/media',
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final files = data['files'] as List<dynamic>;
        
        // 查找匹配的文件
        String? fileId;
        for (final file in files) {
          if (file['fileName'] == fileName) {
            fileId = file['id'].toString();
            break;
          }
        }
        
        if (fileId != null) {
          // 找到文件ID，调用删除接口
          await deleteMediaFile(surveyId, fileId, onStatus: onStatus);
        } else {
          throw '未找到指定的媒体文件';
        }
      } else {
        throw '获取媒体文件列表失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 增强版流式上传函数（移动端使用文件路径）
  Future<String> uploadMedia(
    int surveyId, 
    String filePath, {
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在准备上传文件...');
      _updateStatus(RequestStatus.loading, '正在准备上传文件...');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/survey/$surveyId/media'),
      );
      
      final Map<String, String> multipartHeaders = {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };
      request.headers.addAll(multipartHeaders);
      
      onStatus?.call(RequestStatus.loading, '正在准备文件...');
      _updateStatus(RequestStatus.loading, '正在准备文件...');
      
      // 获取文件信息
      final file = File(filePath);
      final fileSize = await file.length();
      
      if (fileSize == 0) {
        throw '文件为空，无法上传';
      }
      
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      onStatus?.call(RequestStatus.loading, '正在上传文件...');
      _updateStatus(RequestStatus.loading, '正在上传文件...');
      
      // 使用流式传输，不设置超时限制
      final streamedResponse = await request.send();
      
      // 监听上传进度
      int uploadedBytes = 0;
      final responseBytes = <int>[];
      final startTime = DateTime.now();
      
      await for (final chunk in streamedResponse.stream) {
        responseBytes.addAll(chunk);
        uploadedBytes += chunk.length;
        
        // 计算进度
        final progress = (uploadedBytes / fileSize * 100).round();
        
        // 计算上传速度
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        final speed = elapsed > 0 ? (uploadedBytes / elapsed / 1024).round() : 0; // KB/s
        
        // 回调进度
        onProgress?.call(uploadedBytes, fileSize);
        onStatus?.call(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
        _updateStatus(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
      }
      
      // 构建响应
      final response = http.Response(
        utf8.decode(responseBytes),
        streamedResponse.statusCode,
        headers: streamedResponse.headers,
        request: streamedResponse.request,
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        // 优先返回 publicUrl 字段
        final url = data['publicUrl'] ?? data['url'] as String;
        
        final totalTime = DateTime.now().difference(startTime).inSeconds;
        final avgSpeed = totalTime > 0 ? (fileSize / totalTime / 1024).round() : 0;
        
        onStatus?.call(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        _updateStatus(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        
        return url;
      } else {
        final errorMsg = '上传媒体文件失败: ${response.statusCode}, Body: ${response.body}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '上传超时，请检查网络连接';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      } else {
        final errorMsg = e.toString();
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        rethrow;
      }
    }
  }

  // 增强版流式上传函数（带自定义超时）
  Future<String> uploadMediaStream(
    int surveyId, 
    String filePath, {
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
    Duration? customTimeout,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在准备上传文件...');
      _updateStatus(RequestStatus.loading, '正在准备上传文件...');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/survey/$surveyId/media'),
      );
      
      final Map<String, String> multipartHeaders = {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };
      request.headers.addAll(multipartHeaders);
      
      onStatus?.call(RequestStatus.loading, '正在准备文件...');
      _updateStatus(RequestStatus.loading, '正在准备文件...');
      
      // 获取文件信息
      final file = File(filePath);
      final fileSize = await file.length();
      
      if (fileSize == 0) {
        throw '文件为空，无法上传';
      }
      
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      onStatus?.call(RequestStatus.loading, '正在上传文件...');
      _updateStatus(RequestStatus.loading, '正在上传文件...');
      
      // 使用流式传输，可选择设置超时
      final streamedResponse = customTimeout != null 
          ? await request.send().timeout(customTimeout)
          : await request.send();
      
      // 监听上传进度
      int uploadedBytes = 0;
      final responseBytes = <int>[];
      final startTime = DateTime.now();
      
      await for (final chunk in streamedResponse.stream) {
        responseBytes.addAll(chunk);
        uploadedBytes += chunk.length;
        
        // 计算进度
        final progress = (uploadedBytes / fileSize * 100).round();
        
        // 计算上传速度
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        final speed = elapsed > 0 ? (uploadedBytes / elapsed / 1024).round() : 0; // KB/s
        
        // 回调进度
        onProgress?.call(uploadedBytes, fileSize);
        onStatus?.call(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
        _updateStatus(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
      }
      
      // 构建响应
      final response = http.Response(
        utf8.decode(responseBytes),
        streamedResponse.statusCode,
        headers: streamedResponse.headers,
        request: streamedResponse.request,
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        // 优先返回 publicUrl 字段
        final url = data['publicUrl'] ?? data['url'] as String;
        
        final totalTime = DateTime.now().difference(startTime).inSeconds;
        final avgSpeed = totalTime > 0 ? (fileSize / totalTime / 1024).round() : 0;
        
        onStatus?.call(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        _updateStatus(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        
        return url;
      } else {
        final errorMsg = '上传媒体文件失败: ${response.statusCode}, Body: ${response.body}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '上传超时，请检查网络连接';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      } else {
        final errorMsg = e.toString();
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        rethrow;
      }
    }
  }

  // 批量上传媒体文件
  Future<List<String>> uploadMultipleMedia(
    int surveyId, 
    List<String> filePaths, {
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
  }) async {
    final uploadedUrls = <String>[];
    int completedFiles = 0;
    
    try {
      onStatus?.call(RequestStatus.loading, '正在准备批量上传...');
      _updateStatus(RequestStatus.loading, '正在准备批量上传...');
      
      for (int i = 0; i < filePaths.length; i++) {
        final filePath = filePaths[i];
        final fileName = filePath.split('/').last;
        
        onStatus?.call(RequestStatus.loading, '正在上传文件 ${i + 1}/${filePaths.length}: $fileName');
        _updateStatus(RequestStatus.loading, '正在上传文件 ${i + 1}/${filePaths.length}: $fileName');
        
        try {
          final url = await uploadMediaStream(
            surveyId,
            filePath,
            onProgress: onProgress,
            onStatus: (status, message) {
              // 更新状态信息，包含文件进度
              final progressMessage = '文件 ${i + 1}/${filePaths.length}: $message';
              onStatus?.call(status, progressMessage);
            },
          );
          
          uploadedUrls.add(url);
          completedFiles++;
          
          onStatus?.call(RequestStatus.loading, '已完成 $completedFiles/${filePaths.length} 个文件');
          _updateStatus(RequestStatus.loading, '已完成 $completedFiles/${filePaths.length} 个文件');
          
        } catch (e) {
          onStatus?.call(RequestStatus.error, '文件 $fileName 上传失败: $e');
          _updateStatus(RequestStatus.error, '文件 $fileName 上传失败: $e');
          // 继续上传其他文件，不中断整个批量上传
        }
      }
      
      if (uploadedUrls.isNotEmpty) {
        onStatus?.call(RequestStatus.success, '批量上传完成，成功上传 ${uploadedUrls.length}/${filePaths.length} 个文件');
        _updateStatus(RequestStatus.success, '批量上传完成，成功上传 ${uploadedUrls.length}/${filePaths.length} 个文件');
      } else {
        throw '所有文件上传失败';
      }
      
      return uploadedUrls;
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  Future<void> updateSurveyBackground(
    int surveyId, {
  String? desktopBackground,
  String? mobileBackground,
    StatusCallback? onStatus,
}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在更新问卷背景...');
      _updateStatus(RequestStatus.loading, '正在更新问卷背景...');
      
  final Map<String, dynamic> data = {
    'desktopBackground': desktopBackground ?? '',
    'mobileBackground': mobileBackground ?? '',
  };

      final response = await _httpRequest(
        'PUT',
        '$baseUrl/api/survey/$surveyId/background',
        data: data,
        onStatus: onStatus,
      );

      if (response.statusCode == 200) {
        onStatus?.call(RequestStatus.success, '问卷背景更新成功');
        _updateStatus(RequestStatus.success, '问卷背景更新成功');
      } else {
    throw '更新问卷背景失败: ${response.statusCode}';
  }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
}

  // 获取问卷背景（带实时响应）
  Future<Map<String, dynamic>> getSurveyBackground(
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取问卷背景...');
      _updateStatus(RequestStatus.loading, '正在获取问卷背景...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/$surveyId/background',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        onStatus?.call(RequestStatus.success, '问卷背景获取成功');
        _updateStatus(RequestStatus.success, '问卷背景获取成功');
        return data;
      } else {
        throw '获取问卷背景失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  Future<ClickWordCaptchaSession> generateClickWordCaptcha({StatusCallback? onStatus}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在生成点击验证码...');
      _updateStatus(RequestStatus.loading, '正在生成点击验证码...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/auth/captcha?type=clickWord',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final captcha = ClickWordCaptchaSession.fromJson(json.decode(response.body));
        onStatus?.call(RequestStatus.success, '点击验证码生成成功');
        _updateStatus(RequestStatus.success, '点击验证码生成成功');
        return captcha;
      } else {
        throw '获取点击验证码失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  Future<CaptchaVerifyResponse> verifyCaptcha(
    CaptchaVerifyRequest request, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在验证验证码...');
      _updateStatus(RequestStatus.loading, '正在验证验证码...');
      
    final response = await _encryptedRequest(
      'POST',
      '$baseUrl/api/auth/captcha/verify',
      request.toJson(),
        onStatus: onStatus,
    );
    
    if (response.statusCode == 200) {
        final result = CaptchaVerifyResponse.fromJson(json.decode(response.body));
        onStatus?.call(RequestStatus.success, '验证码验证成功');
        _updateStatus(RequestStatus.success, '验证码验证成功');
        return result;
    } else {
      throw '验证失败: ${response.statusCode}';
    }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  Future<Survey> getSurveyById(
    int id, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取问卷详情...');
      _updateStatus(RequestStatus.loading, '正在获取问卷详情...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/detail/$id',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final survey = Survey.fromJson(json.decode(response.body));
        onStatus?.call(RequestStatus.success, '问卷详情获取成功');
        _updateStatus(RequestStatus.success, '问卷详情获取成功');
        return survey;
      } else {
        throw '获取问卷详情失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  // 获取文字验证码图片（带实时响应）
  Future<Map<String, dynamic>> getTextCaptcha({StatusCallback? onStatus}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取验证码...');
      _updateStatus(RequestStatus.loading, '正在获取验证码...');
      
      final response = await _httpRequest(
        'POST',
        '$baseUrl/api/getCaptcha',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 1) {
          onStatus?.call(RequestStatus.success, '验证码获取成功');
          _updateStatus(RequestStatus.success, '验证码获取成功');
          return data;
        } else {
          final errorMsg = data['msg'] ?? '验证码获取失败';
          onStatus?.call(RequestStatus.error, errorMsg);
          _updateStatus(RequestStatus.error, errorMsg);
          throw errorMsg;
        }
      } else {
        final errorMsg = '验证码获取失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '请求超时，请检查网络后重试';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        return {
          'code': -1,
          'msg': errorMsg,
        };
      } else {
        rethrow;
      }
    }
  }

  /// 获取当前用户信息
  Future<User> getCurrentUserHandler({StatusCallback? onStatus}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取用户信息...');
      _updateStatus(RequestStatus.loading, '正在获取用户信息...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/user/current',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        final user = User.fromJson(userData);
        onStatus?.call(RequestStatus.success, '用户信息获取成功');
        _updateStatus(RequestStatus.success, '用户信息获取成功');
        return user;
      } else {
        throw '获取用户信息失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  /// 获取用户个人资料
  Future<User> getUserProfileHandler({StatusCallback? onStatus}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取个人资料...');
      _updateStatus(RequestStatus.loading, '正在获取个人资料...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/user/profile',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final profileData = json.decode(response.body);
        final user = User.fromJson(profileData);
        onStatus?.call(RequestStatus.success, '个人资料获取成功');
        _updateStatus(RequestStatus.success, '个人资料获取成功');
        return user;
      } else {
        throw '获取个人资料失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        throw '请求超时，请检查您的网络连接。';
      }
      rethrow;
    }
  }

  /// Web平台专用的头像上传方法（使用字节数据）
  Future<String> uploadAvatarBytes({
    required List<int> imageBytes,
    required String fileName,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在上传头像...');
      _updateStatus(RequestStatus.loading, '正在上传头像...');

      final uri = Uri.parse('$baseUrl/api/user/avatar/upload');
      final request = http.MultipartRequest('POST', uri);

      // 添加请求头
      request.headers.addAll(_headers);

      // 添加图片文件（使用字节数据）
      final multipartFile = http.MultipartFile.fromBytes(
        'avatar',
        imageBytes,
        filename: fileName,
        contentType: MediaType('image', _getFileExtension(fileName)),
      );
      request.files.add(multipartFile);

      // 发送请求
      final streamedResponse = await request.send().timeout(timeoutDuration);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final avatarUrl = jsonData['avatarUrl'] as String;
        onStatus?.call(RequestStatus.success, '头像上传成功');
        _updateStatus(RequestStatus.success, '头像上传成功');
        return avatarUrl;
      } else {
        throw '上传失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '上传超时，请检查网络连接';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      } else {
        final errorMsg = e.toString();
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        rethrow;
      }
    }
  }

  /// 通用头像上传方法，自动适配Web和移动端
  Future<String> uploadAvatarUniversal({
    File? imageFile,
    List<int>? imageBytes,
    String? fileName,
    StatusCallback? onStatus,
  }) async {
    // Web平台使用字节数据
    if (kIsWeb) {
      if (imageBytes == null || fileName == null) {
        throw 'Web平台需要提供图片字节数据和文件名';
      }
      return uploadAvatarBytes(
        imageBytes: imageBytes,
        fileName: fileName,
        onStatus: onStatus,
      );
    }
    
    // 移动端使用文件对象
    if (imageFile == null) {
      throw '移动端需要提供图片文件';
    }
    return uploadAvatar(imageFile: imageFile, onStatus: onStatus);
  }

  /// 上传用户头像（移动端使用文件对象）
  Future<String> uploadAvatar({
    required File imageFile,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在上传头像...');
      _updateStatus(RequestStatus.loading, '正在上传头像...');

      final uri = Uri.parse('$baseUrl/api/user/avatar/upload');
      final request = http.MultipartRequest('POST', uri);

      // 添加请求头
      request.headers.addAll(_headers);

      // 添加图片文件
      final multipartFile = await http.MultipartFile.fromPath(
        'avatar',
        imageFile.path,
        contentType: MediaType('image', _getFileExtension(imageFile.path)),
      );
      request.files.add(multipartFile);

      // 发送请求
      final streamedResponse = await request.send().timeout(timeoutDuration);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final avatarUrl = jsonData['avatarUrl'] as String;
        onStatus?.call(RequestStatus.success, '头像上传成功');
        _updateStatus(RequestStatus.success, '头像上传成功');
        return avatarUrl;
      } else {
        throw '上传失败: ${response.statusCode}';
      }
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('超时')) {
        final errorMsg = '上传超时，请检查网络连接';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      } else {
        final errorMsg = e.toString();
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        rethrow;
      }
    }
  }

  /// 获取文件扩展名
  String _getFileExtension(String filePath) {
    return filePath.split('.').last.toLowerCase();
  }

  /// 注销用户并使令牌失效
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    if (token == null) {
      throw '未找到令牌';
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/logout'),
      headers: {
        'Authorization': token,
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw '注销失败: ${response.body}';
    }

    // 注销成功后清除本地存储的令牌
    await prefs.remove('authToken');
  }

  // 公开访问问卷信息（无需认证）
  Future<Map<String, dynamic>> getPublicSurvey(
    String surveyUID, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取问卷信息...');
      _updateStatus(RequestStatus.loading, '正在获取问卷信息...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/public/survey/$surveyUID',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        onStatus?.call(RequestStatus.success, '问卷信息获取成功');
        _updateStatus(RequestStatus.success, '问卷信息获取成功');
        return data;
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else {
        throw '获取问卷信息失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 公开提交问卷答案（无需认证）
  Future<void> submitPublicAnswer(
    String surveyUID,
    Map<String, dynamic> answers, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在提交答案...');
      _updateStatus(RequestStatus.loading, '正在提交答案...');
      
      final response = await _encryptedRequest(
        'POST',
        '$baseUrl/api/public/survey/$surveyUID/submit',
        answers,
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        onStatus?.call(RequestStatus.success, '答案提交成功');
        _updateStatus(RequestStatus.success, '答案提交成功');
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else {
        throw '提交答案失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 获取问卷作答结果
  Future<List<SurveyResult>> getSurveyResults(
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取作答结果...');
      _updateStatus(RequestStatus.loading, '正在获取作答结果...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/answer/list/$surveyId',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final results = data.map((item) => SurveyResult.fromJson(item)).toList();
        onStatus?.call(RequestStatus.success, '作答结果获取成功');
        _updateStatus(RequestStatus.success, '作答结果获取成功');
        return results;
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else {
        throw '获取作答结果失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 删除单个答案
  Future<void> deleteAnswer(
    int answerId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在删除答案...');
      _updateStatus(RequestStatus.loading, '正在删除答案...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/answer/$answerId',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        onStatus?.call(RequestStatus.success, '答案删除成功');
        _updateStatus(RequestStatus.success, '答案删除成功');
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else if (response.statusCode == 403) {
        throw '无权限删除此答案';
      } else {
        throw '删除答案失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 批量删除答案
  Future<void> batchDeleteAnswers(
    List<int> answerIds, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在批量删除答案...');
      _updateStatus(RequestStatus.loading, '正在批量删除答案...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/answers/batch',
        data: {'answerIds': answerIds},
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final deletedCount = responseData['deletedCount'] ?? answerIds.length;
        onStatus?.call(RequestStatus.success, '成功删除 $deletedCount 条答案');
        _updateStatus(RequestStatus.success, '成功删除 $deletedCount 条答案');
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else if (response.statusCode == 403) {
        throw '无权限删除这些答案';
      } else {
        throw '批量删除答案失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  /// 更新用户名
  Future<Map<String, dynamic>> updateUsername({
    required String newUsername,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在更新用户名...');
      _updateStatus(RequestStatus.loading, '正在更新用户名...');

      // 使用加密请求，后端 DecryptMiddleware 要求 PUT 必须加密
      final response = await _encryptedRequest(
        'PUT',
        '$baseUrl/api/user/username',
        {
          'newUsername': newUsername,
        },
        onStatus: onStatus,
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        onStatus?.call(RequestStatus.success, '用户名更新成功');
        _updateStatus(RequestStatus.success, '用户名更新成功');
        
        // 如果返回了新的token，更新本地存储的token
        if (responseData['token'] != null) {
          final newToken = responseData['token'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', newToken);
          authToken = newToken;
          
          // 同步更新核心服务的token
          _core.updateAuthToken(newToken);
          
          // 强制清除加密服务的会话密钥，确保使用新token重新建立会话
          _cryptoService.clearSessionKey();
          
          // 通知数据更新，触发UI刷新
          _dataUpdateController.add({
            'type': 'token_updated',
            'data': {'newUsername': responseData['newUsername']},
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
        
        return responseData;
      } else if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw errorData['error'] ?? '用户名格式错误';
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else {
        throw '更新用户名失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }
}
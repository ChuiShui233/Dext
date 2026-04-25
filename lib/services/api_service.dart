import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart' as dio;
import 'config.dart';
import '/services/crypto_service.dart';
import 'core/api_core.dart' as core;
import 'core/XChaCha.dart';
import 'package:cryptography/cryptography.dart';
import 'core/analytics_service.dart' as core;
import 'core/auth_service.dart' as core;
import 'core/email_service.dart' as core;
import 'core/password_service.dart' as core;
import 'core/user_service.dart' as core;
import 'core/captcha_service.dart' as core;
import 'core/question_service.dart' as core;
import 'core/survey_stats_service.dart' as core;
import 'core/cache_service.dart' as core;
import 'core/token_service.dart' as core;
import 'core/result_service.dart' as core;
import 'core/image_service.dart' as core;
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

class TokenExpired {
  final String message;
  TokenExpired(this.message);
  
  @override
  String toString() => message;
}

typedef RequestStatus = core.RequestStatus;
typedef StatusCallback = core.StatusCallback;
typedef ProgressCallback = core.ProgressCallback;

class ApiService {
  static const String baseUrl = apiBaseUrl;
  static const Duration timeoutDuration = Duration(seconds: 15);
  static VoidCallback? onUnauthorized;
  String? authToken;
  final CryptoService _cryptoService = CryptoService();
  String? _remotePublicKeyBase64; // 缓存的远程公钥
  late final core.ApiCore _core;
  late final AuthService _authService;
  late final ProjectService _projectService;
  late final SurveyService _surveyService;
  late final core.AnalyticsService _analyticsService;
  late final core.AuthService _coreAuthService;
  late final core.EmailService _emailService;
  late final core.PasswordService _passwordService;
  late final core.UserService _userService;
  late final core.CaptchaService _captchaService;
  // 现有上传逻辑已在 ApiService 中直接实现
  late final core.QuestionService _questionService;
  late final core.SurveyStatsService _statsService;
  late final core.CacheService _cacheService;
  late final core.TokenService _tokenService;
  late final core.ResultService _resultService;
  StreamSubscription<String>? _coreMsgSub;
  StreamSubscription<Map<String, dynamic>>? _coreDataSub;
  
  RequestStatus _currentStatus = RequestStatus.idle;
  String? _lastErrorMessage;
  final StreamController<RequestStatus> _statusController = StreamController<RequestStatus>.broadcast();
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  
  final StreamController<Map<String, dynamic>> _dataUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  RequestStatus get currentStatus => _currentStatus;
  String? get lastErrorMessage => _lastErrorMessage;
  
  Stream<RequestStatus> get statusStream => _statusController.stream;
  Stream<String> get messageStream => _messageController.stream;
  
  // 数据更新流
  Stream<Map<String, dynamic>> get dataUpdateStream => _dataUpdateController.stream;

  ApiService({this.authToken}) {
    _core = core.ApiCore(authToken: authToken);
    _authService = AuthService(_core);
    _projectService = ProjectService(_core);
    _surveyService = SurveyService(_core);
    
    _analyticsService = core.AnalyticsService(
      baseUrl: baseUrl,
      httpRequest: (method, url, {onStatus}) => _httpRequest(method, url, onStatus: onStatus),
    );
    _coreAuthService = core.AuthService(
      baseUrl: baseUrl,
      cryptoService: _cryptoService,
      encryptedRequest: (method, url, data, {onStatus}) => _encryptedRequest(method, url, data, onStatus: onStatus),
      hybridRequest: (method, url, data, {onStatus}) => _hybridEncryptedRequest(
        method, 
        url, 
        data, 
        sessionKey: _cryptoService.generateSessionKey(),
        onStatus: onStatus,
      ),
    );
    _emailService = core.EmailService(
      baseUrl: baseUrl,
      httpRequest: (method, url, data, {onStatus}) => _httpRequest(method, url, data: data, onStatus: onStatus),
      encryptedRequest: (method, url, data, {onStatus}) => _encryptedRequest(method, url, data, onStatus: onStatus),
    );
    _passwordService = core.PasswordService(
      baseUrl: baseUrl,
      encryptedRequest: (method, url, data, {onStatus}) => _encryptedRequest(method, url, data, onStatus: onStatus),
      hybridRequest: (method, url, data, {onStatus}) => _hybridEncryptedRequest(
        method, 
        url, 
        data, 
        sessionKey: _cryptoService.generateSessionKey(),
        onStatus: onStatus,
      ),
    );
    _userService = core.UserService(
      baseUrl: baseUrl,
      cryptoService: _cryptoService,
      httpRequest: (method, url, {onStatus}) => _httpRequest(method, url, onStatus: onStatus),
      encryptedRequest: (method, url, data, {onStatus}) => _encryptedRequest(method, url, data, onStatus: onStatus),
    );
    _captchaService = core.CaptchaService(
      baseUrl: baseUrl,
      httpRequest: (method, url, {onStatus}) => _httpRequest(method, url, onStatus: onStatus),
    );
    // _fileService = core.FileService(
    //   baseUrl: baseUrl,
    //   httpRequest: (method, url, {onStatus}) => _httpRequest(method, url, onStatus: onStatus),
    // );
    _questionService = core.QuestionService(
      baseUrl: baseUrl,
      httpRequest: (method, url, {onStatus}) => _httpRequest(method, url, onStatus: onStatus),
      encryptedRequest: (method, url, data, {onStatus}) => _encryptedRequest(method, url, data, onStatus: onStatus),
    );
    _statsService = core.SurveyStatsService(
      baseUrl: baseUrl,
      httpRequest: (method, url, {onStatus}) => _httpRequest(method, url, onStatus: onStatus),
    );
    _cacheService = core.CacheService();
    _tokenService = core.TokenService(
      baseUrl: baseUrl,
      cryptoService: _cryptoService,
      authToken: authToken,
    );
    _resultService = core.ResultService(
      baseUrl: baseUrl,
      httpRequest: (method, url, {onStatus}) => _httpRequest(method, url, onStatus: onStatus),
    );

    _coreMsgSub = _core.messageStream.listen((message) => _messageController.add(message));
    _coreDataSub = _core.dataUpdateStream.listen((payload) => _dataUpdateController.add(payload));
  }

  Future<void> _ensureAuthTokenLoaded() async {
    if (authToken == null || authToken!.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final tokenInPrefs = prefs.getString('auth_token');
        if (tokenInPrefs != null && tokenInPrefs.isNotEmpty) {
          authToken = tokenInPrefs;
          _core.updateAuthToken(authToken);
          _tokenService.updateAuthToken(tokenInPrefs);

          final expiryStr = prefs.getString('auth_token_expires');
          if (expiryStr != null) {
            final expiry = DateTime.tryParse(expiryStr);
            if (expiry != null) {
              _tokenService.setTokenExpires(expiry);
            }
          }
        }
        if (authToken == null || authToken!.isEmpty) {
          try {
            const storage = FlutterSecureStorage();
            final tokenInSecure = await storage.read(key: 'auth_token');
            if (tokenInSecure != null && tokenInSecure.isNotEmpty) {
              authToken = tokenInSecure;
              await prefs.setString('auth_token', tokenInSecure);
              _core.updateAuthToken(authToken);
              _tokenService.updateAuthToken(tokenInSecure);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (authToken != null && _tokenService.shouldRefreshToken()) {
      try {
        await _refreshToken();
      } catch (e) {
        if (kDebugMode) print('[ApiService] 主动刷新失败: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getRecentSubmissions({StatusCallback? onStatus}) async {
    return await _analyticsService.getRecentSubmissions(onStatus: onStatus);
  }

  Future<Map<String, int>> getAnalyticsOverview({StatusCallback? onStatus}) async {
    return await _analyticsService.getAnalyticsOverview(onStatus: onStatus);
  }

  Future<Map<String, dynamic>> getSubmitTrend({String range = '7d', StatusCallback? onStatus}) async {
    return await _analyticsService.getSubmitTrend(range: range, onStatus: onStatus);
  }

  // 提交详情：返回题目、选项与我的作答
  Future<Map<String, dynamic>> getSubmissionDetail(int answerId, {StatusCallback? onStatus}) async {
    return await _analyticsService.getSubmissionDetail(answerId, onStatus: onStatus);
  }

  Future<Map<String, dynamic>> getSubmissionHistory({
    String? query,
    int? type,
    int page = 1,
    int pageSize = 20,
    StatusCallback? onStatus,
  }) async {
    return await _analyticsService.getSubmissionHistory(
      query: query,
      type: type,
      page: page,
      pageSize: pageSize,
      onStatus: onStatus,
    );
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

  // 判断URL是否是媒体URL（不需要加密请求体）
  bool _isMediaUrl(String url) {
    return url.contains('/assets/') || 
           url.contains('/upload') || 
           url.contains('/files/');
  }

  /// 获取远程公钥（用于 XChaCha 加密）
  /// 如果缓存中没有，则尝试从服务器获取
  Future<String> _getRemotePublicKey() async {
    if (_remotePublicKeyBase64 != null && _remotePublicKeyBase64!.isNotEmpty) {
      return _remotePublicKeyBase64!;
    }

    try {
      // 尝试从服务器获取公钥
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
    } catch (e) {
      if (kDebugMode) print('[ApiService] 获取远程公钥失败: $e');
    }

    // 如果获取失败，使用默认公钥（这里需要根据实际情况设置）
    // 注意：在生产环境中，应该确保从服务器获取公钥
    throw Exception('无法获取远程公钥，请检查网络连接');
  }
  
  // 通知数据更新
  void _notifyDataUpdate(String dataType, dynamic data) {
    _dataUpdateController.add({
      'type': dataType,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 获取令牌状态信息
  Map<String, dynamic> getTokenStatus() {
    final remainingTime = _tokenService.getTokenRemainingTime();
    return {
      'hasToken': authToken != null && authToken!.isNotEmpty,
      'shouldRefresh': _tokenService.shouldRefreshToken(),
      'remainingTime': remainingTime?.inMinutes,
      'remainingTimeFormatted': remainingTime != null 
          ? '${remainingTime.inHours}h ${remainingTime.inMinutes % 60}m'
          : null,
    };
  }

  /// 主动刷新令牌（公共方法）
  Future<bool> refreshTokenIfNeeded() async {
    if (!_tokenService.shouldRefreshToken()) return true;
    
    try {
      await _refreshToken();
      return true;
    } catch (e) {
      if (kDebugMode) print('[ApiService] 主动刷新令牌失败: $e');
      return false;
    }
  }

  // 释放资源
  void dispose() {
    _statusController.close();
    _messageController.close();
    _dataUpdateController.close();
    _coreMsgSub?.cancel();
    _coreDataSub?.cancel();
    _tokenService.dispose();
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
        final encryptionType = response.headers['x-encrypted'] ?? response.headers['X-Encrypted'];
        
        if (encryptionType == 'xchacha') {
          // XChaCha 加密的响应已经在 _hybridEncryptedRequest 中解密
          try {
            if (kDebugMode) {
              print('[Login] XChaCha 响应体: ${response.body}');
              print('[Login] 响应体长度: ${response.body.length}');
            }
            responseData = json.decode(response.body);
            if (kDebugMode) {
              print('[Login] 解析后的响应数据: $responseData');
            }
          } catch (e) {
            if (kDebugMode) {
              print('[Login] JSON 解析失败: $e');
              print('[Login] 响应体内容: ${response.body}');
            }
            throw '响应解析失败: $e';
          }
        } else if (encryptionType == 'aes') {
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
        final expiresStr = responseData['expires'];
        if (expiresStr == null) {
          throw '响应中缺少 expires 字段';
        }
        final expires = DateTime.parse(expiresStr.toString());
        final refreshToken = responseData['refresh_token'];
        final refreshExpiresStr = responseData['refresh_expires'];
        final DateTime? refreshExpires = refreshExpiresStr != null && refreshExpiresStr.toString().isNotEmpty
            ? DateTime.tryParse(refreshExpiresStr.toString())
            : null;
        
        authToken = token?.toString();
        _core.updateAuthToken(authToken);
        _tokenService.updateAuthToken(authToken ?? '');
        _tokenService.setTokenExpires(expires);
        
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', authToken ?? '');
          await prefs.setString('auth_token_expires', expires.toIso8601String());
          if (refreshToken != null && refreshToken.toString().isNotEmpty) {
            await prefs.setString('refresh_token', refreshToken.toString());
            if (refreshExpires != null) {
              await prefs.setString('refresh_token_expires', refreshExpires.toIso8601String());
            }
            try {
              const storage = FlutterSecureStorage();
              await storage.write(key: 'refresh_token', value: refreshToken.toString());
            } catch (_) {}
          }
        } catch (_) {}
        
        onStatus?.call(RequestStatus.success, '登录成功');
        _updateStatus(RequestStatus.success, '登录成功');
        
        return {
          'token': token,
          'expires': expires,
        };
      } else {
        // 登录失败，清除所有本地认证信息，防止使用旧 token
        authToken = null;
        _core.updateAuthToken(null);
        _cryptoService.clearSessionKey();
        
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('auth_token');
          await prefs.remove('auth_token_expires');
          await prefs.remove('refresh_token');
          await prefs.remove('refresh_token_expires');
          
          const storage = FlutterSecureStorage();
          await storage.delete(key: 'auth_token');
          await storage.delete(key: 'refresh_token');
          await storage.delete(key: 'session_key');
        } catch (e) {
          if (kDebugMode) print('[Login] 清理本地存储失败: $e');
        }
        
        Map<String, dynamic> responseData;
        
        final encryptionType = response.headers['x-encrypted'] ?? response.headers['X-Encrypted'];
        
        if (encryptionType == 'xchacha') {
          // XChaCha 加密的响应已经在 _hybridEncryptedRequest 中解密
          try {
            responseData = json.decode(response.body);
          } catch (e) {
            responseData = {'message': '响应解析失败', 'error': response.body};
          }
        } else if (encryptionType == 'aes') {
          try {
            final encryptedResponse = response.bodyBytes;
            final decryptedBytes = _cryptoService.decryptWithAES(encryptedResponse, sessionKey);
            final decryptedJson = utf8.decode(decryptedBytes);
            responseData = json.decode(decryptedJson);
          } catch (e) {
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
        
        if (kDebugMode) print('[Login] ❌ 登录失败，已清除所有本地认证信息: $errorMessage');
        
        throw errorMessage;
      }
    } catch (e) {
      
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 获取回收站列表
  Future<List<Map<String, dynamic>>> getRecycleBinAnswers(
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取回收站列表...');
      _updateStatus(RequestStatus.loading, '正在获取回收站列表...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/answer/recycle-bin/$surveyId',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
      final dynamic decodedData = json.decode(response.body);
      final List<dynamic> data = decodedData is List ? decodedData : [];
      onStatus?.call(RequestStatus.success, '获取成功');
      _updateStatus(RequestStatus.success, '获取成功');
      return data.cast<Map<String, dynamic>>();
    } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else if (response.statusCode == 403) {
        throw '无权限查看回收站';
      } else {
        throw '获取回收站列表失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 恢复单个答卷
  Future<void> restoreAnswer(
    int answerId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在恢复答卷...');
      _updateStatus(RequestStatus.loading, '正在恢复答卷...');
      
      final response = await _httpRequest(
        'POST',
        '$baseUrl/api/answer/recycle-bin/restore/$answerId',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        onStatus?.call(RequestStatus.success, '答卷恢复成功');
        _updateStatus(RequestStatus.success, '答卷恢复成功');
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else if (response.statusCode == 403) {
        throw '无权限恢复此答卷';
      } else {
        throw '恢复答卷失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 批量恢复答卷
  Future<void> batchRestoreAnswers(
    List<int> answerIds, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在批量恢复答卷...');
      _updateStatus(RequestStatus.loading, '正在批量恢复答卷...');
      
      final response = await _httpRequest(
        'POST',
        '$baseUrl/api/answers/recycle-bin/batch-restore',
        data: {'answerIds': answerIds},
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        onStatus?.call(RequestStatus.success, '批量恢复成功');
        _updateStatus(RequestStatus.success, '批量恢复成功');
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else if (response.statusCode == 403) {
        throw '无权限恢复这些答卷';
      } else {
        throw '批量恢复失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 发送邮箱验证码（注册/重置密码，无需登录）
  Future<void> sendEmailVerificationCode({
    required String email,
    required String purpose,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    return await _emailService.sendEmailVerificationCode(
      email: email,
      purpose: purpose,
      captchaId: captchaId,
      captchaValue: captchaValue,
      onStatus: onStatus,
    );
  }

  Future<Map<String, dynamic>> bindOAuth({
    required String provider,
    required String accessToken,
  }) async {
    await _ensureAuthTokenLoaded();
    return await _coreAuthService.bindOAuth(provider: provider, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> unbindOAuth({
    required String provider,
  }) async {
    await _ensureAuthTokenLoaded();
    return await _coreAuthService.unbindOAuth(provider: provider);
  }


  Future<void> sendChangeEmailCode({
    required String email,
    required String captchaId,
    required String captchaValue,
    StatusCallback? onStatus,
  }) async {
    await _ensureAuthTokenLoaded();
    return await _emailService.sendChangeEmailCode(
      email: email,
      captchaId: captchaId,
      captchaValue: captchaValue,
      onStatus: onStatus,
    );
  }

  Future<bool> verifyEmailCode({
    required String email,
    required String code,
    required String purpose,
    StatusCallback? onStatus,
  }) async {
    return await _emailService.verifyEmailCode(
      email: email,
      code: code,
      purpose: purpose,
      onStatus: onStatus,
    );
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
    StatusCallback? onStatus,
  }) async {
    return await _passwordService.resetPassword(
      email: email,
      code: code,
      newPassword: newPassword,
      onStatus: onStatus,
    );
  }

  Future<void> changeEmail({
    required String newEmail,
    required String password,
    required String code,
    StatusCallback? onStatus,
  }) async {
    await _ensureAuthTokenLoaded();
    return await _emailService.changeEmail(
      newEmail: newEmail,
      password: password,
      code: code,
      onStatus: onStatus,
    );
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    StatusCallback? onStatus,
  }) async {
    await _ensureAuthTokenLoaded();
    return await _passwordService.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
      onStatus: onStatus,
    );
  }

  Future<void> sendEmailCodeForPasswordChange({
    StatusCallback? onStatus,
  }) async {
    await _ensureAuthTokenLoaded();
    return await _emailService.sendEmailCodeForPasswordChange(onStatus: onStatus);
  }


  Future<void> changePasswordWithEmail({
    required String code,
    required String newPassword,
    StatusCallback? onStatus,
  }) async {
    await _ensureAuthTokenLoaded();
    return await _passwordService.changePasswordWithEmail(
      code: code,
      newPassword: newPassword,
      onStatus: onStatus,
    );
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
    return await _coreAuthService.register(
      username: username,
      password: password,
      captchaId: captchaId,
      captchaValue: captchaValue,
      email: email,
      emailCode: emailCode,
      onStatus: onStatus,
    );
  }

  // 缓存管理方法
  Future<void> clearCache({String? specificKey}) async {
    return await _cacheService.clearCache(specificKey: specificKey);
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
    await _cacheService.clearCache(specificKey: 'survey_stats_cache');
    return await _statsService.getSurveyStats(onStatus: onStatus);
  }

  // 格式化错误消息
  String _formatErrorMessage(dynamic error) {
    final errorStr = error.toString();
    
    // HandshakeException - SSL/TLS 握手失败
    if (errorStr.contains('HandshakeException') || 
        errorStr.contains('Connection terminated during handshake')) {
      return '服务端维护中，请稍后再试';
    }
    
    // 连接被拒绝
    if (errorStr.contains('Connection refused') || 
        errorStr.contains('Failed to connect')) {
      return '无法连接到服务器，服务端维护中';
    }
    
    // 证书错误
    if (errorStr.contains('CERTIFICATE_VERIFY_FAILED') ||
        errorStr.contains('certificate')) {
      return '服务器证书验证失败，请检查网络环境';
    }
    
    // 超时错误
    if (errorStr.contains('Timeout') || errorStr.contains('超时')) {
      return '请求超时，请检查您的网络连接';
    }
    
    // 网络不可达
    if (errorStr.contains('Network is unreachable') ||
        errorStr.contains('SocketException')) {
      return '网络连接失败，请检查您的网络';
    }
    
    // 默认错误消息
    return '请求失败: $error';
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

  // 加密请求方法（带实时响应）- 使用 XChaCha 加密
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
      
      // 获取远程公钥
      onStatus?.call(RequestStatus.loading, '正在获取加密密钥...');
      _updateStatus(RequestStatus.loading, '正在获取加密密钥...');
      final remotePublicKey = await _getRemotePublicKey();
      
      onStatus?.call(RequestStatus.loading, '正在加密数据...');
      _updateStatus(RequestStatus.loading, '正在加密数据...');
      
      final headers = {
        ..._headers,
        'X-Encrypted': 'xchacha',
        'Content-Type': 'application/json',
      };

      String? encryptedBody;
      SimpleKeyPair? localEphemeralKeyPair; // 保存本地临时密钥对用于响应解密
      if (data != null) {
        // 使用 XChaCha 加密，与 _hybridEncryptedRequest 保持一致
        final remotePublicKeyBytes = base64Decode(remotePublicKey);
        localEphemeralKeyPair = await SecurePacketFormatter.generateEphemeralKeyPair();
        final sessionKey = await SecurePacketFormatter.deriveSessionKey(
          localEphemeralKeyPair,
          remotePublicKeyBytes,
        );

        final jsonBytes = utf8.encode(json.encode(data));
        final encryptedPacket = await SecurePacketFormatter.encryptPacket(
          sessionKey,
          jsonBytes,
        );

        final localPublicKey = await localEphemeralKeyPair.extractPublicKey();
        final encryptedPayload = XChaChaEncryptedPayload(
          ephemeralPublicKey: base64Encode(localPublicKey.bytes),
          packet: base64Encode(encryptedPacket),
        );
        encryptedBody = json.encode(encryptedPayload.toJson());
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
      
      // 处理加密响应
      http.Response decryptedResponse = response;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // 检查响应是否加密
        if (response.headers['x-encrypted'] == 'xchacha' || 
            response.headers['X-Encrypted'] == 'xchacha') {
          try {
            onStatus?.call(RequestStatus.loading, '正在解密响应...');
            _updateStatus(RequestStatus.loading, '正在解密响应...');
            
            final responseData = json.decode(response.body);
            if (responseData['ephemeralPublicKey'] != null && responseData['packet'] != null) {
              // 解密响应
              final remoteEphemeralKey = base64Decode(responseData['ephemeralPublicKey'] as String);
              final encryptedPacket = base64Decode(responseData['packet'] as String);
              
              // 使用请求时保存的本地临时密钥对解密响应
              if (localEphemeralKeyPair == null) {
                throw '缺少本地临时密钥对，无法解密响应';
              }
              final responseSessionKey = await SecurePacketFormatter.deriveSessionKey(
                localEphemeralKeyPair,
                remoteEphemeralKey,
              );
              
              final decryptedBytes = await SecurePacketFormatter.decryptPacket(
                responseSessionKey,
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
          } catch (e) {
            if (kDebugMode) print('[ApiService] 解密响应失败: $e');
            // 如果解密失败，返回原始响应
          }
        }
        
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
      
      return decryptedResponse;
    } catch (e) {
      final errorMsg = _formatErrorMessage(e);
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw errorMsg;
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

  // 混合加密请求方法（使用 XChaCha）
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
      onStatus?.call(RequestStatus.loading, '正在准备加密请求...');
      _updateStatus(RequestStatus.loading, '正在准备加密请求...');
      
      await _cryptoService.initialize();
      
      // 获取远程公钥
      onStatus?.call(RequestStatus.loading, '正在获取加密密钥...');
      _updateStatus(RequestStatus.loading, '正在获取加密密钥...');
      final remotePublicKey = await _getRemotePublicKey();
      
      onStatus?.call(RequestStatus.loading, '正在加密数据...');
      _updateStatus(RequestStatus.loading, '正在加密数据...');
      
      final headers = {
        ..._headers,
        'X-Encrypted': 'xchacha',
        'Content-Type': 'application/json',
      };

      String? encryptedBody;
      SimpleKeyPair? localEphemeralKeyPair; // 保存本地临时密钥对用于响应解密
      if (data != null) {
        // 使用 XChaCha 加密
        final remotePublicKeyBytes = base64Decode(remotePublicKey);
        localEphemeralKeyPair = await SecurePacketFormatter.generateEphemeralKeyPair();
        final xSessionKey = await SecurePacketFormatter.deriveSessionKey(
          localEphemeralKeyPair,
          remotePublicKeyBytes,
        );
        
        final jsonBytes = utf8.encode(json.encode(data));
        final encryptedPacket = await SecurePacketFormatter.encryptPacket(
          xSessionKey,
          jsonBytes,
        );
        
        final localPublicKey = await localEphemeralKeyPair.extractPublicKey();
        final encryptedPayload = XChaChaEncryptedPayload(
          ephemeralPublicKey: base64Encode(localPublicKey.bytes),
          packet: base64Encode(encryptedPacket),
        );
        encryptedBody = json.encode(encryptedPayload.toJson());
        
        if (kDebugMode) {
          final keyBytes = await xSessionKey.extractBytes();
          print('[ApiService] 加密请求: sessionKey长度=${keyBytes.length}, packet长度=${encryptedPacket.length}, localPublicKey长度=${localPublicKey.bytes.length}');
          print('[ApiService] 服务器公钥前8字节: ${remotePublicKeyBytes.sublist(0, min(8, remotePublicKeyBytes.length)).map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
          print('[ApiService] 客户端临时公钥前8字节: ${localPublicKey.bytes.sublist(0, min(8, localPublicKey.bytes.length)).map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
          if (keyBytes.length >= 8) {
            print('[ApiService] 派生出的sessionKey前8字节: ${keyBytes.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
          }
          if (encryptedPacket.length >= 24) {
            print('[ApiService] packet前24字节(nonce): ${encryptedPacket.sublist(0, 24).map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
          }
        }
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
      
      // 处理加密响应
      http.Response decryptedResponse = response;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // 检查响应是否加密
        if (response.headers['x-encrypted'] == 'xchacha' || 
            response.headers['X-Encrypted'] == 'xchacha') {
          try {
            onStatus?.call(RequestStatus.loading, '正在解密响应...');
            _updateStatus(RequestStatus.loading, '正在解密响应...');
            
            final responseData = json.decode(response.body);
            if (responseData['ephemeralPublicKey'] != null && responseData['packet'] != null) {
              // 解密响应
              final serverEphemeralKey = base64Decode(responseData['ephemeralPublicKey'] as String);
              final encryptedPacket = base64Decode(responseData['packet'] as String);
              
              // 使用请求时保存的本地临时密钥对解密响应
              if (localEphemeralKeyPair == null) {
                throw '缺少本地临时密钥对，无法解密响应';
              }
              
              final responseSessionKey = await SecurePacketFormatter.deriveSessionKey(
                localEphemeralKeyPair,
                serverEphemeralKey,
              );
              
              final decryptedBytes = await SecurePacketFormatter.decryptPacket(
                responseSessionKey,
                encryptedPacket,
              );
              
              final decryptedBody = utf8.decode(decryptedBytes);
              if (kDebugMode) {
                print('[ApiService] 解密后的响应体: $decryptedBody');
              }
              decryptedResponse = http.Response(
                decryptedBody,
                response.statusCode,
                headers: response.headers,
                request: response.request,
              );
            }
          } catch (e) {
            if (kDebugMode) print('[ApiService] 解密响应失败: $e');
            // 如果解密失败，返回原始响应
          }
        }
        
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
      
      return decryptedResponse;
    } catch (e) {
      final errorMsg = _formatErrorMessage(e);
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw errorMsg;
    }
  }


  // 公共API请求方法（使用 XChaCha 加密）
  Future<http.Response> _publicRequest(
    String method,
    String url, {
    Map<String, dynamic>? data,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在准备请求...');
      _updateStatus(RequestStatus.loading, '正在准备请求...');
      
      final uri = Uri.parse(url);
      http.Response response;
      SimpleKeyPair? localEphemeralKeyPair; // 保存本地临时密钥对用于响应解密

      final upperMethod = method.toUpperCase();
      final isBodyMethod = (upperMethod == 'POST' || upperMethod == 'PUT' || upperMethod == 'DELETE');
      final hasData = data != null;

      if (isBodyMethod && hasData) {
        // 对于有请求体的公共请求，使用 XChaCha 加密
        await _cryptoService.initialize();
        
        onStatus?.call(RequestStatus.loading, '正在获取加密密钥...');
        _updateStatus(RequestStatus.loading, '正在获取加密密钥...');
        final remotePublicKey = await _getRemotePublicKey();
        
        onStatus?.call(RequestStatus.loading, '正在加密数据...');
        _updateStatus(RequestStatus.loading, '正在加密数据...');
        
        // 生成本地临时密钥对并使用 XChaCha 加密
        localEphemeralKeyPair = await SecurePacketFormatter.generateEphemeralKeyPair();
        final remotePublicKeyBytes = base64Decode(remotePublicKey);
        final sessionKey = await SecurePacketFormatter.deriveSessionKey(
          localEphemeralKeyPair,
          remotePublicKeyBytes,
        );
        final jsonBytes = utf8.encode(json.encode(data));
        final encryptedPacket = await SecurePacketFormatter.encryptPacket(
          sessionKey,
          jsonBytes,
        );
        final localPublicKey = await localEphemeralKeyPair.extractPublicKey();
        final encryptedBody = json.encode(
          XChaChaEncryptedPayload(
            ephemeralPublicKey: base64Encode(localPublicKey.bytes),
            packet: base64Encode(encryptedPacket),
          ).toJson(),
        );
        
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'X-Encrypted': 'xchacha',
        };

        onStatus?.call(RequestStatus.loading, '正在发送请求...');
        _updateStatus(RequestStatus.loading, '正在发送请求...');

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
        // GET 请求或没有数据的请求 —— 为支持响应加密，生成本地临时密钥对并携带到请求头
        await _cryptoService.initialize();
        final epk = await SecurePacketFormatter.generateEphemeralKeyPair();
        localEphemeralKeyPair = epk;
        final localPubForHeader = await epk.extractPublicKey();
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'X-Encrypted': 'xchacha',
          'X-Client-Ephemeral-Key': base64Encode(localPubForHeader.bytes),
        };

        switch (upperMethod) {
          case 'GET':
            response = await http
                .get(uri, headers: headers)
                .timeout(timeoutDuration);
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
            response = await http
                .delete(uri, headers: headers, body: data != null ? json.encode(data) : null)
                .timeout(timeoutDuration);
            break;
          default:
            throw '不支持的HTTP方法: $method';
        }
      }

      // 处理加密响应
      http.Response decryptedResponse = response;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // 检查响应是否加密
        if (response.headers['x-encrypted'] == 'xchacha' || 
            response.headers['X-Encrypted'] == 'xchacha') {
          try {
            onStatus?.call(RequestStatus.loading, '正在解密响应...');
            _updateStatus(RequestStatus.loading, '正在解密响应...');
            
            final responseData = json.decode(response.body);
            if (responseData['ephemeralPublicKey'] != null && responseData['packet'] != null) {
              // 解密响应
              final remoteEphemeralKey = base64Decode(responseData['ephemeralPublicKey'] as String);
              final encryptedPacket = base64Decode(responseData['packet'] as String);
              
              // 使用请求时保存的本地临时密钥对解密响应
              final responseSessionKey = await SecurePacketFormatter.deriveSessionKey(
                localEphemeralKeyPair,
                remoteEphemeralKey,
              );
              
              final decryptedBytes = await SecurePacketFormatter.decryptPacket(
                responseSessionKey,
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
          } catch (e) {
            if (kDebugMode) print('[ApiService] 解密响应失败: $e');
            // 如果解密失败，返回原始响应
          }
        }
      }

      return decryptedResponse;
    } catch (e) {
      final errorMsg = _formatErrorMessage(e);
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  // 普通HTTP请求方法（带实时响应）- 所有请求使用 XChaCha 加密
  Future<http.Response> _httpRequest(
    String method,
    String url, {
    Map<String, dynamic>? data,
    StatusCallback? onStatus,
    bool allowRetry = true,
  }) async {
    try {
      await _ensureAuthTokenLoaded();
      onStatus?.call(RequestStatus.loading, '正在准备请求...');
      _updateStatus(RequestStatus.loading, '正在准备请求...');
      
      final uri = Uri.parse(url);
      http.Response response;
      SimpleKeyPair? localEphemeralKeyPair; // 保存本地临时密钥对用于响应解密（仅在加密请求时使用）

      final upperMethod = method.toUpperCase();
      final isBodyMethod = (upperMethod == 'POST' || upperMethod == 'PUT' || upperMethod == 'DELETE');
      final hasData = data != null;
      final isMediaRequest = _isMediaUrl(url);

      // 对于媒体上传请求，保持原逻辑（multipart/form-data 不适合加密）
      if (isMediaRequest) {
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
      } else if (isBodyMethod && hasData) {
        // 对于有请求体的请求，使用 XChaCha 加密
        await _cryptoService.initialize();
        
        onStatus?.call(RequestStatus.loading, '正在获取加密密钥...');
        _updateStatus(RequestStatus.loading, '正在获取加密密钥...');
        final remotePublicKey = await _getRemotePublicKey();
        
        onStatus?.call(RequestStatus.loading, '正在加密数据...');
        _updateStatus(RequestStatus.loading, '正在加密数据...');
        
        // 生成本地临时密钥对并进行 XChaCha 加密
        localEphemeralKeyPair = await SecurePacketFormatter.generateEphemeralKeyPair();
        final remotePublicKeyBytes = base64Decode(remotePublicKey);
        final sessionKey = await SecurePacketFormatter.deriveSessionKey(
          localEphemeralKeyPair,
          remotePublicKeyBytes,
        );
        final jsonBytes = utf8.encode(json.encode(data));
        final encryptedPacket = await SecurePacketFormatter.encryptPacket(
          sessionKey,
          jsonBytes,
        );
        final localPublicKey = await localEphemeralKeyPair.extractPublicKey();
        final encryptedBody = json.encode(
          XChaChaEncryptedPayload(
            ephemeralPublicKey: base64Encode(localPublicKey.bytes),
            packet: base64Encode(encryptedPacket),
          ).toJson(),
        );
        
        final headers = {
          ..._headers,
          'X-Encrypted': 'xchacha',
          'Content-Type': 'application/json',
        };

        onStatus?.call(RequestStatus.loading, '正在发送请求...');
        _updateStatus(RequestStatus.loading, '正在发送请求...');

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
        // GET 请求或没有数据的请求，仍需支持加密响应：携带客户端临时公钥
        await _cryptoService.initialize();
        final epk = await SecurePacketFormatter.generateEphemeralKeyPair();
        localEphemeralKeyPair = epk;
        final localPubForHeader = await epk.extractPublicKey();
        final headers = {
          ..._headers,
          'X-Encrypted': 'xchacha',
          'X-Client-Ephemeral-Key': base64Encode(localPubForHeader.bytes),
        };
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
      
      // 处理加密响应
      http.Response decryptedResponse = response;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // 检查响应是否加密
        if (response.headers['x-encrypted'] == 'xchacha' || 
            response.headers['X-Encrypted'] == 'xchacha') {
          try {
            onStatus?.call(RequestStatus.loading, '正在解密响应...');
            _updateStatus(RequestStatus.loading, '正在解密响应...');
            
            final responseData = json.decode(response.body);
            if (responseData['ephemeralPublicKey'] != null && responseData['packet'] != null) {
              // 解密响应
              final remoteEphemeralKey = base64Decode(responseData['ephemeralPublicKey'] as String);
              final encryptedPacket = base64Decode(responseData['packet'] as String);
              
              // 使用请求时保存的本地临时密钥对解密响应
              if (localEphemeralKeyPair == null) {
                throw '缺少本地临时密钥对，无法解密响应';
              }
              final responseSessionKey = await SecurePacketFormatter.deriveSessionKey(
                localEphemeralKeyPair,
                remoteEphemeralKey,
              );
              
              final decryptedBytes = await SecurePacketFormatter.decryptPacket(
                responseSessionKey,
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
          } catch (e) {
            if (kDebugMode) print('[ApiService] 解密响应失败: $e');
            // 如果解密失败，返回原始响应
          }
        }
        
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

      return decryptedResponse;
    } catch (e) {
      final errorMsg = _formatErrorMessage(e);
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw errorMsg;
    }
  }

  // 自动刷新token并重试的通用方法
  Future<bool> _refreshToken() async {
    try {
      final newToken = await _tokenService.refreshToken();
      if (newToken != null && newToken.isNotEmpty) {
        authToken = newToken;
        _core.updateAuthToken(authToken);
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('[RefreshToken] 刷新失败: $e');
      return false;
    }
  }


  // 退出登录并清除本地令牌
  Future<void> logoutAndClear({StatusCallback? onStatus}) async {
    await _userService.logout(onStatus: onStatus);
    authToken = null;
    _updateStatus(RequestStatus.success, '已退出登录');
  }

  /// 严格注销：先调用服务端注销，成功后清理所有本地令牌和会话数据
  Future<void> logoutStrict({StatusCallback? onStatus}) async {
    await _userService.logout(onStatus: onStatus);
    authToken = null;
  }

  /// 清除所有本地缓存数据
  Future<void> clearAllLocalData() async {
    await _userService.clearAllLocalData();
    authToken = null;
  }

  Future<List<Project>> getProjects({StatusCallback? onStatus}) async {

    return await _projectService.getProjects(onStatus: onStatus);
  }

  Future<PaginatedResponse<Project>> getProjectsPaginated({
    int page = 1,
    int pageSize = 10,
    String? search,
    bool skipCache = false,
    StatusCallback? onStatus,
  }) async {
    return await _projectService.getProjectsPaginated(
      page: page,
      pageSize: pageSize,
      search: search,
      skipCache: skipCache,
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
  Future<List<Survey>> getSurveys({StatusCallback? onStatus, bool skipCache = false}) async {
    return await _surveyService.getSurveys(onStatus: onStatus, skipCache: skipCache);
  }

  Future<PaginatedResponse<Survey>> getSurveysPaginated({
    int page = 1,
    int pageSize = 5,
    String? search,
    String? type,
    bool skipCache = false,
    StatusCallback? onStatus,
  }) async {
    return await _surveyService.getSurveysPaginated(
      page: page,
      pageSize: pageSize,
      search: search,
      skipCache: skipCache,
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
    return await _statsService.getSingleSurveyStats(
      surveyId: surveyId,
      onStatus: onStatus,
    );
  }
  Future<List<SurveyStats>> getAllSurveyStats({StatusCallback? onStatus}) async {
    return await _statsService.getSurveyStats(onStatus: onStatus);
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
    return await _questionService.getSurveyQuestions(surveyId, onStatus: onStatus);
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

  // Web平台专用的字节数据上传函数（使用Dio实现真正的上传进度）
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
      
      final fileSize = fileBytes.length;
      if (fileSize == 0) {
        throw '文件为空，无法上传';
      }
      
      // 使用Dio实现真正的上传进度监听
      final dioClient = dio.Dio();
      dioClient.options.headers = {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };
      
      // 优化超时配置，支持大文件上传
      final fileSizeMB = fileSize / (1024 * 1024);
      
      // 根据文件大小动态设置超时时间
      if (fileSizeMB > 10) {
        // 大文件（>10MB）：设置更长的超时时间
        dioClient.options.connectTimeout = const Duration(seconds: 60);
        dioClient.options.sendTimeout = const Duration(minutes: 10); // 10分钟上传超时
        dioClient.options.receiveTimeout = const Duration(seconds: 60);
      } else if (fileSizeMB > 5) {
        // 中等文件（5-10MB）
        dioClient.options.connectTimeout = const Duration(seconds: 45);
        dioClient.options.sendTimeout = const Duration(minutes: 5); // 5分钟上传超时
        dioClient.options.receiveTimeout = const Duration(seconds: 45);
      } else {
        // 小文件（<5MB）：保持原有设置
        dioClient.options.connectTimeout = const Duration(seconds: 30);
        dioClient.options.sendTimeout = const Duration(minutes: 2); // 2分钟上传超时
        dioClient.options.receiveTimeout = const Duration(seconds: 30);
      }
      
      // Web平台仍然使用fromBytes，因为Stream方式会导致Dio无法追踪进度
      // Dio的onSendProgress需要知道总大小，fromBytes可以正确计算进度
      final formData = dio.FormData.fromMap({
        'file': dio.MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
        ),
      });
      
      onStatus?.call(RequestStatus.loading, '正在上传文件...');
      _updateStatus(RequestStatus.loading, '正在上传文件...');
      
      final startTime = DateTime.now();
      
      final response = await dioClient.post(
        '$baseUrl/api/survey/$surveyId/media',
        data: formData,
        onSendProgress: (sent, total) {
          // 真正的上传进度回调
          final progress = (sent / total * 100).round();
          final elapsed = DateTime.now().difference(startTime).inSeconds;
          final speed = elapsed > 0 ? (sent / elapsed / 1024).round() : 0;
          
          onProgress?.call(sent, total);
          onStatus?.call(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
          _updateStatus(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final url = data['url'] as String;
        
        final totalTime = DateTime.now().difference(startTime).inSeconds;
        final avgSpeed = totalTime > 0 ? (fileSize / totalTime / 1024).round() : 0;
        
        onStatus?.call(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        _updateStatus(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        
        return url;
      } else {
        final errorMsg = '上传媒体文件失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    } on dio.DioException catch (e) {
      String errorMsg;
      if (e.type == dio.DioExceptionType.connectionTimeout || 
          e.type == dio.DioExceptionType.sendTimeout) {
        errorMsg = '上传超时，请检查网络连接';
      } else if (e.response != null) {
        errorMsg = '上传失败: ${e.response?.statusCode} - ${e.response?.data}';
      } else {
        errorMsg = '上传失败: ${e.message}';
      }
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw errorMsg;
    } catch (e) {
      final errorMsg = '上传失败: ${e.toString()}';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
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

  // 增强版流式上传函数（移动端使用文件路径，使用Dio实现真正的上传进度）
  Future<String> uploadMedia(
    int surveyId, 
    String filePath, {
    ProgressCallback? onProgress,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在准备上传文件...');
      _updateStatus(RequestStatus.loading, '正在准备上传文件...');
      
      // 获取文件信息
      final file = File(filePath);
      final fileSize = await file.length();
      
      if (fileSize == 0) {
        throw '文件为空，无法上传';
      }
      
      // 使用Dio实现真正的上传进度监听
      final dioClient = dio.Dio();
      dioClient.options.headers = {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };
      
      // 优化超时配置，支持大文件上传
      final fileSizeMB = fileSize / (1024 * 1024);
      
      // 根据文件大小动态设置超时时间
      if (fileSizeMB > 10) {
        // 大文件（>10MB）：设置更长的超时时间
        dioClient.options.connectTimeout = const Duration(seconds: 60);
        dioClient.options.sendTimeout = const Duration(minutes: 10); // 10分钟上传超时
        dioClient.options.receiveTimeout = const Duration(seconds: 60);
      } else if (fileSizeMB > 5) {
        // 中等文件（5-10MB）
        dioClient.options.connectTimeout = const Duration(seconds: 45);
        dioClient.options.sendTimeout = const Duration(minutes: 5); // 5分钟上传超时
        dioClient.options.receiveTimeout = const Duration(seconds: 45);
      } else {
        // 小文件（<5MB）：保持原有设置
        dioClient.options.connectTimeout = const Duration(seconds: 30);
        dioClient.options.sendTimeout = const Duration(minutes: 2); // 2分钟上传超时
        dioClient.options.receiveTimeout = const Duration(seconds: 30);
      }
      
      final fileName = filePath.split(Platform.pathSeparator).last;
      // 使用fromFile实现流式传输，不会一次性加载整个文件到内存
      final formData = dio.FormData.fromMap({
        'file': await dio.MultipartFile.fromFile(
          filePath,
          filename: fileName,
        ),
      });
      
      onStatus?.call(RequestStatus.loading, '正在上传文件...');
      _updateStatus(RequestStatus.loading, '正在上传文件...');
      
      final startTime = DateTime.now();
      
      final response = await dioClient.post(
        '$baseUrl/api/survey/$surveyId/media',
        data: formData,
        onSendProgress: (sent, total) {
          // 真正的上传进度回调
          final progress = (sent / total * 100).round();
          final elapsed = DateTime.now().difference(startTime).inSeconds;
          final speed = elapsed > 0 ? (sent / elapsed / 1024).round() : 0;
          
          onProgress?.call(sent, total);
          onStatus?.call(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
          _updateStatus(RequestStatus.loading, '上传进度: $progress% ($speed KB/s)');
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final url = data['url'] as String;
        
        final totalTime = DateTime.now().difference(startTime).inSeconds;
        final avgSpeed = totalTime > 0 ? (fileSize / totalTime / 1024).round() : 0;
        
        onStatus?.call(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        _updateStatus(RequestStatus.success, '文件上传成功 (平均速度: $avgSpeed KB/s)');
        
        return url;
      } else {
        final errorMsg = '上传媒体文件失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw errorMsg;
      }
    } on dio.DioException catch (e) {
      String errorMsg;
      if (e.type == dio.DioExceptionType.connectionTimeout || 
          e.type == dio.DioExceptionType.sendTimeout) {
        errorMsg = '上传超时，请检查网络连接';
      } else if (e.response != null) {
        errorMsg = '上传失败: ${e.response?.statusCode} - ${e.response?.data}';
      } else {
        errorMsg = '上传失败: ${e.message}';
      }
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw errorMsg;
    } catch (e) {
      final errorMsg = '上传失败: ${e.toString()}';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
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

  Future<CaptchaSession> getTextCaptcha({StatusCallback? onStatus}) async {
    return await _captchaService.getCaptcha(onStatus: onStatus);
  }

  /// 清除用户信息缓存
  Future<void> clearUserCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user_cache');
  }

  /// 获取当前用户信息（带缓存）
  Future<User> getCurrentUserHandler({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'current_user_cache';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        _updateStatus(RequestStatus.loading, '正在加载缓存数据...');
        
        // 防御性检查：空字符串或非 JSON
        if (cached.isEmpty || !cached.trim().startsWith('{')) {
          debugPrint('[getCurrentUserHandler] 缓存格式异常，长度=${cached.length}，前100字符: ${cached.substring(0, cached.length > 100 ? 100 : cached.length)}');
          await prefs.remove(cacheKey);
          // 直接跳到网络获取
        } else {
          final userData = json.decode(cached) as Map<String, dynamic>;
          final user = User.fromJson(userData);
          
          onStatus?.call(RequestStatus.success, '缓存数据加载成功');
          _updateStatus(RequestStatus.success, '缓存数据加载成功');
          
          // 静默刷新
          _refreshCurrentUserSilently(prefs, cacheKey, user);
          return user;
        }
      } catch (e, st) {
        debugPrint('[getCurrentUserHandler] 缓存解析失败: $e');
        debugPrint('堆栈: $st');
        await prefs.remove(cacheKey);
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        _updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }
    
    return _refreshCurrentUser(prefs, cacheKey, onStatus: onStatus);
  }
  
  Future<void> _refreshCurrentUserSilently(
    SharedPreferences prefs,
    String cacheKey,
    User cached,
  ) async {
    try {
      final response = await _httpRequest('GET', '$baseUrl/api/user/current');
      if (response.statusCode == 200) {
        final userData = json.decode(response.body) as Map<String, dynamic>;
        final newUser = User.fromJson(userData);
        
        if (_userHasChanged(cached, newUser)) {
          prefs.setString(cacheKey, json.encode(userData));
          _notifyDataUpdate('current_user', newUser);
          _updateStatus(RequestStatus.success, '用户信息已更新');
        }
      }
    } catch (_) {}
  }
  
  bool _userHasChanged(User a, User b) {
    return a.id != b.id ||
           a.username != b.username ||
           a.email != b.email ||
           a.avatarUrl != b.avatarUrl ||
           a.gender != b.gender ||
           a.userStatus != b.userStatus ||
           _oauthBindingsChanged(a.oauthBindings, b.oauthBindings);
  }
  
  bool _oauthBindingsChanged(OAuthBindings? a, OAuthBindings? b) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    
    return a.count != b.count ||
           a.googleBound != b.googleBound ||
           a.githubBound != b.githubBound ||
           a.microsoftBound != b.microsoftBound;
  }
  
  Future<User> _refreshCurrentUser(
    SharedPreferences prefs,
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取用户信息...');
      _updateStatus(RequestStatus.loading, '正在获取用户信息...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/user/current',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        try {
          // ignore: avoid_print
          print('✅ [_refreshCurrentUser] HTTP 200 响应成功');
          // ignore: avoid_print
          print('响应头 x-encrypted: ${response.headers['x-encrypted']}');
          // ignore: avoid_print
          print('响应体原始长度: ${response.body.length}');
          
          String body;
          
          // 检查是否为加密响应
          if (response.headers['x-encrypted'] == 'aes') {
            // ignore: avoid_print
            print('🔐 检测到加密响应，正在解密...');
            try {
              final sessionKey = _cryptoService.currentSessionKey;
              if (sessionKey == null) {
                throw '没有会话密钥，无法解密响应';
              }
              final encryptedBytes = response.bodyBytes;
              final decryptedBytes = _cryptoService.decryptWithAES(encryptedBytes, sessionKey);
              body = utf8.decode(decryptedBytes);
              // ignore: avoid_print
              print('✅ 解密成功，解密后长度: ${body.length}');
            } catch (e) {
              // ignore: avoid_print
              print('❌ 解密失败: $e');
              throw '响应解密失败: $e';
            }
          } else {
            body = response.body;
          }
          
          // 防御性检查：验证响应体
          if (body.isEmpty) {
            // ignore: avoid_print
            print('❌ 响应体为空');
            throw FormatException('服务器返回空响应');
          }
          if (!body.trim().startsWith('{') && !body.trim().startsWith('[')) {
            // ignore: avoid_print
            print('❌ 响应体非JSON，长度=${body.length}');
            // ignore: avoid_print
            print('前200字符: ${body.substring(0, body.length > 200 ? 200 : body.length)}');
            throw FormatException('服务器返回非JSON响应');
          }
          
          final userData = json.decode(body) as Map<String, dynamic>;
          prefs.setString(cacheKey, json.encode(userData));
          final user = User.fromJson(userData);
          onStatus?.call(RequestStatus.success, '用户信息获取成功');
          _updateStatus(RequestStatus.success, '用户信息获取成功');
          return user;
        } catch (e, st) {
          // 使用 print 确保输出不被过滤
          // ignore: avoid_print
          print('❌❌❌ [_refreshCurrentUser] JSON解析失败 ❌❌❌');
          // ignore: avoid_print
          print('错误: $e');
          // ignore: avoid_print
          print('堆栈: $st');
          // ignore: avoid_print
          print('响应体长度: ${response.body.length}');
          // ignore: avoid_print
          print('响应体内容(前500字符): ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
          rethrow;
        }
      } else {
        // ignore: avoid_print
        print('❌ [_refreshCurrentUser] HTTP错误: ${response.statusCode}');
        // ignore: avoid_print
        print('响应体: ${response.body}');
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
      // 确保 token 已加载
      await _ensureAuthTokenLoaded();
      
      onStatus?.call(RequestStatus.loading, '正在上传头像...');
      _updateStatus(RequestStatus.loading, '正在上传头像...');

      final uri = Uri.parse('$baseUrl/api/user/avatar/upload');
      final request = http.MultipartRequest('POST', uri);

      // 仅设置鉴权头，避免覆盖 multipart/form-data 的 Content-Type
      final multipartHeaders = <String, String>{
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };
      request.headers.addAll(multipartHeaders);

      // 添加图片文件（使用字节数据）
      final multipartFile = http.MultipartFile.fromBytes(
        'avatar',
        imageBytes,
        filename: fileName,
        contentType: MediaType('image', _getFileExtension(fileName)),
      );
      request.files.add(multipartFile);

      // 发送请求（头像上传给更宽的超时，避免弱网下超时）
      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
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
    // 优先使用字节数据（Web和桌面端）
    if (imageBytes != null && fileName != null) {
      return uploadAvatarBytes(
        imageBytes: imageBytes,
        fileName: fileName,
        onStatus: onStatus,
      );
    }
    
    // 移动端使用文件对象
    if (imageFile != null) {
      return uploadAvatar(imageFile: imageFile, onStatus: onStatus);
    }
    
    throw '需要提供图片字节数据或文件对象';
  }

  /// 上传用户头像（移动端使用文件对象）
  Future<String> uploadAvatar({
    required File imageFile,
    StatusCallback? onStatus,
  }) async {
    try {
      // 确保 token 已加载
      await _ensureAuthTokenLoaded();
      
      onStatus?.call(RequestStatus.loading, '正在上传头像...');
      _updateStatus(RequestStatus.loading, '正在上传头像...');

      final uri = Uri.parse('$baseUrl/api/user/avatar/upload');
      final request = http.MultipartRequest('POST', uri);

      // 仅设置鉴权头，避免覆盖 multipart/form-data 的 Content-Type
      final multipartHeaders = <String, String>{
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };
      request.headers.addAll(multipartHeaders);

      // 添加图片文件
      final multipartFile = await http.MultipartFile.fromPath(
        'avatar',
        imageFile.path,
        contentType: MediaType('image', _getFileExtension(imageFile.path)),
      );
      request.files.add(multipartFile);

      // 发送请求（头像上传给更宽的超时，避免弱网下超时）
      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
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
    await _userService.logout();
    authToken = null;
  }

  // 公开访问问卷信息（无需认证）
  Future<Map<String, dynamic>> getPublicSurvey(String surveyUID, {StatusCallback? onStatus}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取问卷信息...');
      _updateStatus(RequestStatus.loading, '正在获取问卷信息...');
      
      final response = await _publicRequest(
        'GET',
        '$baseUrl/api/public/survey/$surveyUID',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final raw = response.body.trim();
        if (raw.isEmpty || raw.toLowerCase() == 'null') {
          onStatus?.call(RequestStatus.success, '问卷信息获取成功');
          _updateStatus(RequestStatus.success, '问卷信息获取成功');
          return <String, dynamic>{};
        }
        final dynamic decoded = json.decode(raw);
        final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
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

  // 公开提交问卷答案（无需认证，但后端要求加密通道）
  Future<void> submitPublicAnswer(
    String surveyUID,
    Map<String, dynamic> answers, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在提交答案...');
      _updateStatus(RequestStatus.loading, '正在提交答案...');
      
      // 注意：后端 DecryptMiddleware 要求 POST 使用加密
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

  Future<List<SurveyResult>> getSurveyResults(
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    // Note: ResultService.getSurveyResults returns paginated data
    // This method may need adjustment based on actual usage
    final response = await _resultService.getSurveyResults(
      surveyId: surveyId,
      page: 1,
      pageSize: 1000,  // Large page size to get all results
      onStatus: onStatus,
    );
    return response.items;
  }
  

  // 逻辑删除单个答案
  Future<void> deleteAnswer(
    int answerId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在删除答案...');
      _updateStatus(RequestStatus.loading, '正在删除答案...');
      
      final response = await _httpRequest(
        'POST',
        '$baseUrl/api/answer/logic-delete/$answerId',
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

  // 批量逻辑删除答案
  Future<void> batchDeleteAnswers(
    List<int> answerIds, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在批量删除答案...');
      _updateStatus(RequestStatus.loading, '正在批量删除答案...');
      
      final response = await _httpRequest(
        'POST',
        '$baseUrl/api/answers/batch-logic-delete',
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

  // 物理删除单个答案（仅限创建者）
  Future<void> physicalDeleteAnswer(
    int answerId, {
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在物理删除答案...');
      _updateStatus(RequestStatus.loading, '正在物理删除答案...');
      
      final response = await _httpRequest(
        'DELETE',
        '$baseUrl/api/answer/$answerId',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        onStatus?.call(RequestStatus.success, '答案物理删除成功');
        _updateStatus(RequestStatus.success, '答案物理删除成功');
      } else if (response.statusCode == 401) {
        throw TokenExpired('未登录或登录已过期');
      } else if (response.statusCode == 403) {
        throw '无权限物理删除此答案';
      } else {
        throw '物理删除答案失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateUsername({
    required String newUsername,
    StatusCallback? onStatus,
  }) async {
    return await _userService.updateUsername(
      newUsername: newUsername,
      onStatus: onStatus,
    );
  }

  // ==================== 图片 URL 工具方法 ====================
  
  static String getImageUrl(String? imageUrl, {String quality = 'medium'}) {
    return core.ImageService.getImageUrl(imageUrl, quality: quality);
  }

  static String getThumbUrl(String? imageUrl) {
    return core.ImageService.getThumbUrl(imageUrl);
  }

  static String getMediumUrl(String? imageUrl) {
    return core.ImageService.getMediumUrl(imageUrl);
  }

  static String getOriginalUrl(String? imageUrl) {
    return core.ImageService.getOriginalUrl(imageUrl);
  }

  // ==================== 配置信息相关方法 ====================
  
  /// 获取应用配置信息，包括隐私政策链接等
  Future<Map<String, dynamic>> getAppConfig({StatusCallback? onStatus}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在获取配置信息...');
      _updateStatus(RequestStatus.loading, '正在获取配置信息...');
      
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/config',
        onStatus: onStatus,
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        onStatus?.call(RequestStatus.success, '配置信息获取成功');
        _updateStatus(RequestStatus.success, '配置信息获取成功');
        return data;
      } else {
        throw '获取配置信息失败: ${response.statusCode}';
      }
    } catch (e) {
      final errorMsg = e.toString();
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
    
      return {
        'privacyPolicyUrl': '$baseUrl/static',
        'version': '1.0.0',
      };
    }
  }
  
  /// 获取隐私政策链接
  Future<String> getPrivacyPolicyUrl({StatusCallback? onStatus}) async {
    try {
      final config = await getAppConfig(onStatus: onStatus);
      return config['privacyPolicyUrl'] ?? '$baseUrl/static';
    } catch (e) {
      // 如果获取失败，返回默认链接
      return '$baseUrl/static';
    }
  }
}
// Modified by ChuiShui12 on 2025/07/02.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;
import '/services/crypto_service.dart';
import '../models/project.dart';
import '../models/survey.dart';
import '../models/survey_stats.dart';
import '../models/question.dart';
import '../models/captcha.dart';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 令牌过期异常类
class TokenExpiredException implements Exception {
  final String message;
  TokenExpiredException(this.message);
  
  @override
  String toString() => message;
}

// 请求状态枚举
enum RequestStatus {
  idle,
  loading,
  success,
  error,
}

// 请求进度回调
typedef ProgressCallback = void Function(int sent, int total);
typedef StatusCallback = void Function(RequestStatus status, String? message);

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:11222';  //wucode.xyz:11222
  static const Duration timeoutDuration = Duration(seconds: 15);
  String? authToken;
  final CryptoService _cryptoService = CryptoService();
  
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

  ApiService({this.authToken});

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
  }

  // 登录方法
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
        final responseData = json.decode(response.body);
        final token = responseData['token'];
        final expires = DateTime.parse(responseData['expires']);
        
        onStatus?.call(RequestStatus.success, '登录成功');
        _updateStatus(RequestStatus.success, '登录成功');
        
        return {
          'token': token,
          'expires': expires,
        };
      } else {
        final responseData = json.decode(response.body);
        final errorMessage = responseData['message'] ?? responseData['error'] ?? '登录失败';
        
        onStatus?.call(RequestStatus.error, errorMessage);
        _updateStatus(RequestStatus.error, errorMessage);
        
        throw Exception(errorMessage);
      }
    } catch (e) {
      final errorMsg = '登录失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
        
        throw Exception(errorMessage);
      }
    } catch (e) {
      final errorMsg = '注册失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
  }) async {
    try {
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
      } else {
        final errorMsg = '请求失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
      }
      
      return response;
    } on TimeoutException {
      final errorMsg = '请求超时，请检查您的网络连接。';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    } catch (e) {
      final errorMsg = '请求失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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

  // 普通HTTP请求方法（带实时响应）
  Future<http.Response> _httpRequest(
    String method,
    String url, {
    Map<String, dynamic>? data,
    StatusCallback? onStatus,
  }) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在发送请求...');
      _updateStatus(RequestStatus.loading, '正在发送请求...');
      
      final uri = Uri.parse(url);
      final headers = _headers;
      
      http.Response response;
      
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(timeoutDuration);
          break;
        case 'POST':
          response = await http.post(
            uri, 
            headers: headers,
            body: data != null ? json.encode(data) : null,
          ).timeout(timeoutDuration);
          break;
        case 'PUT':
          response = await http.put(
            uri, 
            headers: headers,
            body: data != null ? json.encode(data) : null,
          ).timeout(timeoutDuration);
          break;
        case 'DELETE':
          if (data != null) {
            response = await http.delete(
              uri, 
              headers: headers,
              body: json.encode(data),
            ).timeout(timeoutDuration);
          } else {
            response = await http.delete(uri, headers: headers).timeout(timeoutDuration);
          }
          break;
        default:
          throw Exception('不支持的HTTP方法: $method');
      }
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        onStatus?.call(RequestStatus.success, '请求成功');
        _updateStatus(RequestStatus.success, '请求成功');
      } else {
        final errorMsg = '请求失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
      }
      
      return response;
    } on TimeoutException {
      final errorMsg = '请求超时，请检查您的网络连接。';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    } catch (e) {
      final errorMsg = '请求失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    }
  }

  // 自动刷新token并重试的通用方法

  // 项目相关API（带实时响应）
  Future<List<Project>> getProjects({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'projects_cache';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        _updateStatus(RequestStatus.loading, '正在加载缓存数据...');
        
        final List<dynamic> jsonList = json.decode(cached);
        final List<Project> projects = jsonList.map((e) => Project.fromJson(e)).toList();
        
        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        _updateStatus(RequestStatus.success, '缓存数据加载成功');
        
        // 异步刷新网络数据，使用独立的回调避免状态混乱
        _refreshProjectsSilently(prefs, cacheKey, projects);
        return projects;
      } catch (e) {
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        _updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }
    return await _refreshProjects(prefs, cacheKey, onStatus: onStatus);
  }

  // 静默刷新项目数据（用于异步更新）
  Future<void> _refreshProjectsSilently(
    SharedPreferences prefs, 
    String cacheKey,
    List<Project> cachedProjects,
  ) async {
    try {
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/project/list',
        onStatus: null, // 不使用回调，避免状态混乱
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body == null || body is! List) {
          return;
        }
        
        final newProjects = body.map<Project>((json) => Project.fromJson(json)).toList();
        
        // 检查数据是否有变化
        if (_hasProjectsChanged(cachedProjects, newProjects)) {
          prefs.setString(cacheKey, json.encode(body));
          
          // 通知UI数据已更新
          _notifyDataUpdate('projects', newProjects);
          _updateStatus(RequestStatus.success, '项目数据已更新');
        }
      }
    } catch (e) {
      // 静默处理错误，不影响主流程
    }
  }
  
  // 检查项目数据是否有变化
  bool _hasProjectsChanged(List<Project> oldProjects, List<Project> newProjects) {
    if (oldProjects.length != newProjects.length) return true;
    
    for (int i = 0; i < oldProjects.length; i++) {
      if (oldProjects[i].id != newProjects[i].id ||
          oldProjects[i].projectName != newProjects[i].projectName ||
          oldProjects[i].projectDescription != newProjects[i].projectDescription ||
          oldProjects[i].updateTime != newProjects[i].updateTime) {
        return true;
      }
    }
    return false;
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
        throw Exception('获取项目列表失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
      throw Exception('创建项目失败: ${response.statusCode}');
    }
    } catch (e) {
      final errorMsg = '创建项目失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
      throw Exception('更新项目失败: ${response.statusCode}');
    }
    } catch (e) {
      final errorMsg = '更新项目失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    }
  }

  // 问卷相关API（带实时响应）
  Future<List<Survey>> getSurveys({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'surveys_cache';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        _updateStatus(RequestStatus.loading, '正在加载缓存数据...');
        
        final List<dynamic> jsonList = json.decode(cached);
        final List<Survey> surveys = jsonList.map((e) => Survey.fromJson(e)).toList();
        
        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        _updateStatus(RequestStatus.success, '缓存数据加载成功');
        
        // 异步刷新网络数据，使用独立的回调避免状态混乱
        _refreshSurveysSilently(prefs, cacheKey, surveys);
        return surveys;
      } catch (e) {
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        _updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }
    return await _refreshSurveys(prefs, cacheKey, onStatus: onStatus);
  }

  // 静默刷新问卷数据（用于异步更新）
  Future<void> _refreshSurveysSilently(
    SharedPreferences prefs, 
    String cacheKey,
    List<Survey> cachedSurveys,
  ) async {
    try {
      final response = await _httpRequest(
        'GET',
        '$baseUrl/api/survey/list',
        onStatus: null, // 不使用回调，避免状态混乱
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(response.body);
        if (body == null || body is! List) {
          return;
        }
        
        final newSurveys = body.map<Survey>((json) => Survey.fromJson(json)).toList();
        
        // 检查数据是否有变化
        if (_hasSurveysChanged(cachedSurveys, newSurveys)) {
          prefs.setString(cacheKey, json.encode(body));
          
          // 通知UI数据已更新
          _notifyDataUpdate('surveys', newSurveys);
          _updateStatus(RequestStatus.success, '问卷数据已更新');
        }
      }
    } catch (e) {
      // 静默处理错误，不影响主流程
    }
  }
  
  // 检查问卷数据是否有变化
  bool _hasSurveysChanged(List<Survey> oldSurveys, List<Survey> newSurveys) {
    if (oldSurveys.length != newSurveys.length) return true;
    
    for (int i = 0; i < oldSurveys.length; i++) {
      if (oldSurveys[i].id != newSurveys[i].id ||
          oldSurveys[i].surveyName != newSurveys[i].surveyName ||
          oldSurveys[i].description != newSurveys[i].description ||
          oldSurveys[i].updateTime != newSurveys[i].updateTime) {
        return true;
      }
    }
    return false;
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
        throw Exception('获取问卷列表失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
      throw Exception('创建问卷失败: ${response.statusCode}');
    }
    } catch (e) {
      final errorMsg = '创建问卷失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
    try {
      onStatus?.call(RequestStatus.loading, '正在更新问卷...');
      _updateStatus(RequestStatus.loading, '正在更新问卷...');
      
    final response = await _encryptedRequest(
      'PUT',
      '$baseUrl/api/survey/update',
      survey.toJson(),
        onStatus: onStatus,
    );
    
    if (response.statusCode == 200) {
        final updatedSurvey = Survey.fromJson(json.decode(response.body));
        
        // 更新成功后清除相关缓存
        await _clearSurveyListCache();
        
        onStatus?.call(RequestStatus.success, '问卷更新成功');
        _updateStatus(RequestStatus.success, '问卷更新成功');
        return updatedSurvey;
    } else {
      throw Exception('更新问卷失败: ${response.statusCode}');
    }
    } catch (e) {
      final errorMsg = '更新问卷失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    }
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
        throw Exception('删除问卷失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
        throw Exception('批量删除问卷失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
        throw Exception('删除项目失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
        throw Exception('批量删除项目失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
        throw Exception('获取问卷统计信息失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
        throw Exception('获取问卷统计信息失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
    }
  }

  // 刷新认证token（带实时响应）
  Future<String> refreshToken({StatusCallback? onStatus}) async {
    try {
      onStatus?.call(RequestStatus.loading, '正在刷新认证令牌...');
      _updateStatus(RequestStatus.loading, '正在刷新认证令牌...');
      
      final response = await _encryptedRequest(
        'POST',
        '$baseUrl/api/auth/refresh',
        {'refresh': true},
        onStatus: onStatus,
      );
    
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final token = data['token'] as String;
        
        onStatus?.call(RequestStatus.success, '认证令牌刷新成功');
        _updateStatus(RequestStatus.success, '认证令牌刷新成功');
        
        return token;
      } else if (response.statusCode == 401) {
        // 令牌已失效，需要重新登录
        final errorMsg = '认证令牌已失效，请重新登录';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw TokenExpiredException(errorMsg);
      } else {
        final errorMsg = '刷新认证token失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw Exception(errorMsg);
      }
    } catch (e) {
      if (e is TokenExpiredException) {
        rethrow; // 重新抛出TokenExpiredException
      }
      final errorMsg = '刷新认证令牌失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    }
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
        throw Exception(errorMsg);
      }
    } catch (e) {
      final errorMsg = '重新登录失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
        print('后端返回的原始数据: $body'); // 调试日志
        
        if (body == null || body is! List) {
          onStatus?.call(RequestStatus.success, '问卷问题列表为空');
          _updateStatus(RequestStatus.success, '问卷问题列表为空');
          return [];
        }
        prefs.setString(cacheKey, json.encode(body));
        final questions = body.map<Question>((json) {
          print('解析问题JSON: $json'); // 调试日志
          return Question.fromJson(json);
        }).toList();
        
        print('解析后的问题数量: ${questions.length}'); // 调试日志
        for (int i = 0; i < questions.length; i++) {
          print('问题 $i: 标题=${questions[i].title}, 类型=${questions[i].type}, 选项数量=${questions[i].options.length}');
        }
        
        onStatus?.call(RequestStatus.success, '问卷问题获取成功');
        _updateStatus(RequestStatus.success, '问卷问题获取成功');
        
        return questions;
      } else {
        throw Exception('获取问卷问题列表失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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

    // 打印漂亮格式的上传数据
    final prettyJson = const JsonEncoder.withIndent('  ').convert(question.toJson());
    print('上传的数据:\n$prettyJson');

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
      throw Exception('添加问题失败: ${response.statusCode}');
    }
  } catch (e) {
    final errorMsg = '添加问题失败: $e';
    onStatus?.call(RequestStatus.error, errorMsg);
    _updateStatus(RequestStatus.error, errorMsg);
    throw Exception(errorMsg);
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
      throw Exception('更新问题失败: ${response.statusCode}');
    }
    } catch (e) {
      final errorMsg = '更新问题失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
        throw Exception('删除问题失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
      throw Exception('重新排序问题失败: ${response.statusCode}');
    }
    } catch (e) {
      final errorMsg = '重新排序问题失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    }
  }

  // 增强版流式上传函数
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
        throw Exception('文件为空，无法上传');
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
        throw Exception(errorMsg);
      }
    } on TimeoutException {
      final errorMsg = '上传超时，请检查网络连接';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    } catch (e) {
      final errorMsg = '上传媒体文件失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
        throw Exception('文件为空，无法上传');
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
        throw Exception(errorMsg);
      }
    } on TimeoutException {
      final errorMsg = '上传超时，请检查网络连接';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    } catch (e) {
      final errorMsg = '上传媒体文件失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
        throw Exception('所有文件上传失败');
      }
      
      return uploadedUrls;
    } catch (e) {
      final errorMsg = '批量上传失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
    throw Exception('更新问卷背景失败: ${response.statusCode}');
  }
    } catch (e) {
      final errorMsg = '更新问卷背景失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
        throw Exception('获取问卷背景失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
        throw Exception('获取点击验证码失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
      throw Exception('验证失败: ${response.statusCode}');
    }
    } catch (e) {
      final errorMsg = '验证码验证失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
        throw Exception('获取问卷详情失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
          throw Exception(errorMsg);
        }
      } else {
        final errorMsg = '验证码获取失败: ${response.statusCode}';
        onStatus?.call(RequestStatus.error, errorMsg);
        _updateStatus(RequestStatus.error, errorMsg);
        throw Exception(errorMsg);
      }
    } on TimeoutException {
      final errorMsg = '请求超时，请检查网络后重试';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      return {
        'code': -1,
        'msg': errorMsg,
      };
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
        throw Exception('获取用户信息失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
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
        throw Exception('获取个人资料失败: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查您的网络连接。');
    }
  }

  /// 上传用户头像
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
        throw Exception('上传失败: ${response.statusCode}');
      }
    } on TimeoutException {
      final errorMsg = '上传超时，请检查网络连接';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
    } catch (e) {
      final errorMsg = '头像上传失败: $e';
      onStatus?.call(RequestStatus.error, errorMsg);
      _updateStatus(RequestStatus.error, errorMsg);
      throw Exception(errorMsg);
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
      throw Exception('未找到令牌');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/logout'),
      headers: {
        'Authorization': token,
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('注销失败: ${response.body}');
    }

    // 注销成功后清除本地存储的令牌
    await prefs.remove('authToken');
  }
}
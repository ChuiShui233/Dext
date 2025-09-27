import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';

class HomeState extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Timer? _tokenRefreshTimer;
  
  String _token = '';
  DateTime _tokenExpiry = DateTime.now();
  int _projectCount = 0;
  int _surveyCount = 0;
  bool _isLoading = false;

  String get token => _token;
  DateTime get tokenExpiry => _tokenExpiry;
  int get projectCount => _projectCount;
  int get surveyCount => _surveyCount;
  bool get isLoading => _isLoading;

  void initialize(String token, DateTime tokenExpiry) {
    _token = token;
    _tokenExpiry = tokenExpiry;
    _setupTokenRefresh();
    _loadData();
  }

  void _setupTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    final remaining = _tokenExpiry.difference(DateTime.now());
    const threshold = Duration(minutes: 5);

    if (remaining > threshold) {
      _tokenRefreshTimer = Timer(remaining - threshold, _refreshToken);
    } else {
      _refreshToken();
    }
  }

  Future<void> _refreshToken() async {
    try {
      final apiService = ApiService(authToken: _token);
      final newToken = await apiService.refreshToken();
      final newExpiry = DateTime.now().add(const Duration(hours: 1));

      await _storage.write(key: 'auth_token', value: newToken);
      await _storage.write(key: 'token_expiry', value: newExpiry.toIso8601String());

      _token = newToken;
      _tokenExpiry = newExpiry;
      notifyListeners();
      _setupTokenRefresh();
    } on TokenExpired {
      // 令牌已过期，需要重新登录
      _handleLogout();
    } catch (e) {
      // 其他错误，也触发登出
      _handleLogout();
    }
  }

  Future<void> _loadData() async {
    if (_token.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      final apiService = ApiService(authToken: _token);
      final projects = await apiService.getProjects();
      final surveys = await apiService.getSurveys();

      _projectCount = projects.length;
      _surveyCount = surveys.length;
    } catch (e) {
      // 处理错误
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _handleLogout() {
    // 这里需要通知外部处理登出
    // 可以通过回调或者事件总线来处理
  }

  void refreshData() {
    _loadData();
  }

  @override
  void dispose() {
    _tokenRefreshTimer?.cancel();
    super.dispose();
  }
} 
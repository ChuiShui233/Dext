import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_core.dart';

class AnalyticsService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, {StatusCallback? onStatus}) httpRequest;
  
  AnalyticsService({required this.baseUrl, required this.httpRequest});

  Future<List<Map<String, dynamic>>> getRecentSubmissions({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'recent_submissions';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        final dynamic data = json.decode(cached);
        List<Map<String, dynamic>> submissions;
        if (data is Map<String, dynamic>) {
          submissions = (data['submissions'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
        } else if (data is List) {
          submissions = data.whereType<Map<String, dynamic>>().toList();
        } else {
          submissions = const <Map<String, dynamic>>[];
        }
        _refreshRecentSubmissionsSilently(prefs, cacheKey);
        return submissions;
      } catch (_) {}
    }
    
    return _refreshRecentSubmissions(prefs, cacheKey, onStatus: onStatus);
  }
  
  Future<void> _refreshRecentSubmissionsSilently(SharedPreferences prefs, String cacheKey) async {
    try {
      final url = '$baseUrl/api/survey/recent-submissions';
      final response = await httpRequest('GET', url);
      if (response.statusCode == 200) {
        prefs.setString(cacheKey, response.body);
      }
    } catch (_) {}
  }
  
  Future<List<Map<String, dynamic>>> _refreshRecentSubmissions(
    SharedPreferences prefs,
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    final url = '$baseUrl/api/survey/recent-submissions';
    final response = await httpRequest('GET', url, onStatus: onStatus);
    if (response.statusCode == 200) {
      prefs.setString(cacheKey, response.body);
      final raw = response.body.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') {
        return const <Map<String, dynamic>>[];
      }
      final dynamic data = json.decode(raw);
      if (data is Map<String, dynamic>) {
        return (data['submissions'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList();
      }
      return const <Map<String, dynamic>>[];
    }
    throw '获取最近提交失败: ${response.statusCode}';
  }

  Future<Map<String, int>> getAnalyticsOverview({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'analytics_overview';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        final data = json.decode(cached) as Map<String, dynamic>;
        final overview = {
          'totalViews': (data['totalViews'] as num?)?.toInt() ?? 0,
          'totalSubmits': (data['totalSubmits'] as num?)?.toInt() ?? 0,
          'totalSurveys': (data['totalSurveys'] as num?)?.toInt() ?? 0,
          'activeSurveys': (data['activeSurveys'] as num?)?.toInt() ?? 0,
        };
        _refreshAnalyticsOverviewSilently(prefs, cacheKey, overview);
        return overview;
      } catch (_) {}
    }
    
    return _refreshAnalyticsOverview(prefs, cacheKey, onStatus: onStatus);
  }
  
  Future<void> _refreshAnalyticsOverviewSilently(
    SharedPreferences prefs,
    String cacheKey,
    Map<String, int> cached,
  ) async {
    try {
      final url = '$baseUrl/api/analytics/overview';
      final response = await httpRequest('GET', url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final fresh = {
          'totalViews': (data['totalViews'] as num?)?.toInt() ?? 0,
          'totalSubmits': (data['totalSubmits'] as num?)?.toInt() ?? 0,
          'totalSurveys': (data['totalSurveys'] as num?)?.toInt() ?? 0,
          'activeSurveys': (data['activeSurveys'] as num?)?.toInt() ?? 0,
        };
        if (fresh != cached) {
          prefs.setString(cacheKey, response.body);
        }
      }
    } catch (_) {}
  }
  
  Future<Map<String, int>> _refreshAnalyticsOverview(
    SharedPreferences prefs,
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    final url = '$baseUrl/api/analytics/overview';
    final response = await httpRequest('GET', url, onStatus: onStatus);
    if (response.statusCode == 200) {
      prefs.setString(cacheKey, response.body);
      final data = json.decode(response.body);
      return {
        'totalViews': (data['totalViews'] as num?)?.toInt() ?? 0,
        'totalSubmits': (data['totalSubmits'] as num?)?.toInt() ?? 0,
        'totalSurveys': (data['totalSurveys'] as num?)?.toInt() ?? 0,
        'activeSurveys': (data['activeSurveys'] as num?)?.toInt() ?? 0,
      };
    }
    throw '获取分析概览失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> getSubmitTrend({String range = '7d', StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'submit_trend_$range';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        final data = json.decode(cached) as Map<String, dynamic>;
        _refreshSubmitTrendSilently(prefs, cacheKey, range, data);
        return data;
      } catch (_) {}
    }
    
    return _refreshSubmitTrend(prefs, cacheKey, range, onStatus: onStatus);
  }
  
  Future<void> _refreshSubmitTrendSilently(
    SharedPreferences prefs,
    String cacheKey,
    String range,
    Map<String, dynamic> cached,
  ) async {
    try {
      final url = '$baseUrl/api/analytics/submit-trend?range=$range';
      final response = await httpRequest('GET', url);
      if (response.statusCode == 200) {
        final raw = response.body.trim();
        if (raw.isEmpty || raw.toLowerCase() == 'null') {
          return;
        }
        final dynamic decoded = json.decode(raw);
        if (decoded is! Map<String, dynamic>) {
          return;
        }
        final Map<String, dynamic> fresh = decoded;
        final labelsA = (cached['labels'] as List?)?.join(',') ?? '';
        final countsA = (cached['counts'] as List?)?.join(',') ?? '';
        final labelsB = (fresh['labels'] as List?)?.join(',') ?? '';
        final countsB = (fresh['counts'] as List?)?.join(',') ?? '';
        if (labelsA != labelsB || countsA != countsB) {
          prefs.setString(cacheKey, response.body);
        }
      }
    } catch (_) {}
  }
  
  Future<Map<String, dynamic>> _refreshSubmitTrend(
    SharedPreferences prefs,
    String cacheKey,
    String range, {
    StatusCallback? onStatus,
  }) async {
    final url = '$baseUrl/api/analytics/submit-trend?range=$range';
    final response = await httpRequest('GET', url, onStatus: onStatus);
    if (response.statusCode == 200) {
      prefs.setString(cacheKey, response.body);
      final raw = response.body.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') {
        return <String, dynamic>{};
      }
      try {
        final dynamic decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
      return <String, dynamic>{};
    }
    throw '获取提交趋势失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> getSubmissionDetail(int answerId, {StatusCallback? onStatus}) async {
    final url = '$baseUrl/api/survey/submissions/$answerId/detail';
    final response = await httpRequest('GET', url, onStatus: onStatus);
    if (response.statusCode == 200) {
      final raw = response.body.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') {
        return <String, dynamic>{};
      }
      try {
        final dynamic data = json.decode(raw);
        if (data is Map<String, dynamic>) return data;
      } catch (_) {}
      return <String, dynamic>{};
    } else if (response.statusCode == 404) {
      throw '提交记录不存在';
    }
    throw '获取提交详情失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> getSubmissionHistory({
    String? query,
    int? type,
    int page = 1,
    int pageSize = 20,
    StatusCallback? onStatus,
  }) async {
    var url = '$baseUrl/api/survey/submissions/history?page=$page&pageSize=$pageSize';
    if (query != null && query.isNotEmpty) {
      url += '&query=${Uri.encodeComponent(query)}';
    }
    if (type != null) {
      url += '&type=$type';
    }
    
    final response = await httpRequest('GET', url, onStatus: onStatus);
    if (response.statusCode == 200) {
      final raw = response.body.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') {
        return <String, dynamic>{};
      }
      try {
        final dynamic data = json.decode(raw);
        if (data is Map<String, dynamic>) return data;
      } catch (_) {}
      return <String, dynamic>{};
    }
    throw '获取提交历史失败: ${response.statusCode}';
  }
}

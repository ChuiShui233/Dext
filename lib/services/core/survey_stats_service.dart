import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/survey_stats.dart';
import 'api_core.dart';

class SurveyStatsService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, {StatusCallback? onStatus}) httpRequest;
  
  SurveyStatsService({required this.baseUrl, required this.httpRequest});

  // 获取单个问卷统计（调用后端专用端点）
  Future<SurveyStats> getSingleSurveyStats({
    required int surveyId,
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest(
      'GET',
      '$baseUrl/api/survey/stats/$surveyId',
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      return SurveyStats.fromJson(json.decode(response.body));
    }
    throw '获取问卷统计失败: ${response.statusCode}';
  }

  // 获取所有问卷统计列表
  Future<List<SurveyStats>> getSurveyStats({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'survey_stats_cache';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        final dynamic data = json.decode(cached);
        List<SurveyStats> stats;
        if (data is Map<String, dynamic>) {
          final list = (data['stats'] as List?) ?? const [];
          stats = list.map((e) => SurveyStats.fromJson(e)).toList();
        } else if (data is List) {
          stats = data.map((e) => SurveyStats.fromJson(e)).toList();
        } else {
          stats = const <SurveyStats>[];
        }
        _refreshStatsSilently(prefs, cacheKey);
        return stats;
      } catch (_) {}
    }
    
    return _refreshStats(prefs, cacheKey, onStatus: onStatus);
  }

  Future<void> _refreshStatsSilently(SharedPreferences prefs, String cacheKey) async {
    try {
      final response = await httpRequest('GET', '$baseUrl/api/survey/stats');
      if (response.statusCode == 200) {
        prefs.setString(cacheKey, response.body);
      }
    } catch (_) {}
  }

  Future<List<SurveyStats>> _refreshStats(
    SharedPreferences prefs,
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest('GET', '$baseUrl/api/survey/stats', onStatus: onStatus);
    if (response.statusCode == 200) {
      prefs.setString(cacheKey, response.body);
      final raw = response.body.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') {
        return const <SurveyStats>[];
      }
      final dynamic data = json.decode(raw);
      if (data is Map<String, dynamic>) {
        final list = (data['stats'] as List?) ?? const [];
        return list.map((e) => SurveyStats.fromJson(e)).toList();
      }
      if (data is List) {
        return data.map((e) => SurveyStats.fromJson(e)).toList();
      }
      return const <SurveyStats>[];
    }
    throw '获取问卷统计失败: ${response.statusCode}';
  }

}

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
        final data = json.decode(cached) as Map<String, dynamic>;
        final stats = (data['stats'] as List).map((e) => SurveyStats.fromJson(e)).toList();
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
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (data['stats'] as List).map((e) => SurveyStats.fromJson(e)).toList();
    }
    throw '获取问卷统计失败: ${response.statusCode}';
  }

}

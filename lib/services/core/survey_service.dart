import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/survey.dart';
import 'api_core.dart';

class SurveyService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, {StatusCallback? onStatus}) httpRequest;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) encryptedRequest;
  
  SurveyService({required this.baseUrl, required this.httpRequest, required this.encryptedRequest});

  Future<List<Survey>> getSurveys({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'surveys_cache';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        final data = json.decode(cached) as Map<String, dynamic>;
        final surveys = (data['surveys'] as List).map((e) => Survey.fromJson(e)).toList();
        _refreshSurveysSilently(prefs, cacheKey);
        return surveys;
      } catch (_) {}
    }
    
    return _refreshSurveys(prefs, cacheKey, onStatus: onStatus);
  }

  Future<void> _refreshSurveysSilently(SharedPreferences prefs, String cacheKey) async {
    try {
      final response = await httpRequest('GET', '$baseUrl/api/surveys');
      if (response.statusCode == 200) {
        prefs.setString(cacheKey, response.body);
      }
    } catch (_) {}
  }

  Future<List<Survey>> _refreshSurveys(
    SharedPreferences prefs,
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest('GET', '$baseUrl/api/surveys', onStatus: onStatus);
    if (response.statusCode == 200) {
      prefs.setString(cacheKey, response.body);
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (data['surveys'] as List).map((e) => Survey.fromJson(e)).toList();
    }
    throw '获取问卷列表失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> createSurvey({
    required int projectId,
    required String surveyName,
    String? description,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'POST',
      '$baseUrl/api/surveys',
      {'projectId': projectId, 'surveyName': surveyName, 'description': description},
      onStatus: onStatus,
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else if (response.statusCode == 400) {
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? '创建问卷失败';
    }
    throw '创建问卷失败: ${response.statusCode}';
  }

  Future<void> deleteSurvey(int surveyId, {StatusCallback? onStatus}) async {
    final response = await httpRequest('DELETE', '$baseUrl/api/surveys/$surveyId', onStatus: onStatus);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw '删除问卷失败: ${response.statusCode}';
    }
  }

  Future<Map<String, dynamic>> updateSurvey({
    required int surveyId,
    String? surveyName,
    String? description,
    bool? isActive,
    bool? allowAnonymous,
    bool? autoSubmit,
    String? desktopBackground,
    String? mobileBackground,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'PUT',
      '$baseUrl/api/surveys/$surveyId',
      {
        if (surveyName != null) 'surveyName': surveyName,
        if (description != null) 'description': description,
        if (isActive != null) 'isActive': isActive,
        if (allowAnonymous != null) 'allowAnonymous': allowAnonymous,
        if (autoSubmit != null) 'autoSubmit': autoSubmit,
        if (desktopBackground != null) 'desktopBackground': desktopBackground,
        if (mobileBackground != null) 'mobileBackground': mobileBackground,
      },
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw '更新问卷失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> getPublicSurvey(String surveyUID, {StatusCallback? onStatus}) async {
    final response = await httpRequest('GET', '$baseUrl/api/public/surveys/$surveyUID', onStatus: onStatus);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 404) {
      throw '问卷不存在或已关闭';
    }
    throw '获取问卷失败: ${response.statusCode}';
  }

  Future<void> submitSurvey({
    required String surveyUID,
    required Map<int, List<String>> answers,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'POST',
      '$baseUrl/api/public/surveys/$surveyUID/submit',
      {'answers': answers.map((k, v) => MapEntry(k.toString(), v))},
      onStatus: onStatus,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      if (response.statusCode == 403) {
        throw '您可能没有权限提交此问卷或达到提交次数限制';
      } else if (response.statusCode == 404) {
        throw '问卷不存在';
      }
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? '提交失败: ${response.statusCode}';
    }
  }
}

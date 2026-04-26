import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/question.dart';
import 'api_core.dart';

class QuestionService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, {StatusCallback? onStatus}) httpRequest;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) encryptedRequest;
  
  QuestionService({required this.baseUrl, required this.httpRequest, required this.encryptedRequest});

  Future<List<Question>> getSurveyQuestions(int surveyId, {StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'questions_$surveyId';
    return _refreshQuestions(prefs, cacheKey, surveyId, onStatus: onStatus);
  }

  Future<List<Question>> _refreshQuestions(
    SharedPreferences prefs,
    String cacheKey,
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest('GET', '$baseUrl/api/survey/$surveyId/questions', onStatus: onStatus);
    if (response.statusCode == 200) {
      final raw = response.body.trim();
      prefs.setString(cacheKey, response.body);
      if (raw.isEmpty || raw.toLowerCase() == 'null') {
        return <Question>[];
      }
      dynamic data;
      try {
        data = json.decode(raw);
      } catch (_) {
        return <Question>[];
      }
      // 后端直接返回数组
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map((e) => Question.fromJson(e))
            .toList();
      }
      // 如果是包装对象，提取questions字段（可能缺失或为null）
      if (data is Map<String, dynamic>) {
        final q = data['questions'];
        if (q is List) {
          return q
              .whereType<Map<String, dynamic>>()
              .map((e) => Question.fromJson(e))
              .toList();
        }
        return <Question>[];
      }
      return <Question>[];
    }
    throw '获取问题列表失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> createQuestion({
    required int surveyId,
    required String title,
    required String type,
    List<Map<String, dynamic>>? options,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'POST',
      '$baseUrl/api/questions',
      {
        'surveyId': surveyId,
        'title': title,
        'type': type,
        if (options != null) 'options': options,
      },
      onStatus: onStatus,
    );

    if (response.statusCode == 201) {
      await _invalidate(surveyId);
      return json.decode(response.body);
    }
    throw '创建问题失败: ${response.statusCode}';
  }

  Future<void> deleteQuestion(int surveyId, int questionId, {StatusCallback? onStatus}) async {
    final response = await httpRequest('DELETE', '$baseUrl/api/questions/$questionId', onStatus: onStatus);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw '删除问题失败: ${response.statusCode}';
    }
    await _invalidate(surveyId);
  }

  Future<Map<String, dynamic>> updateQuestion({
    required int surveyId,
    required int questionId,
    String? title,
    List<Map<String, dynamic>>? options,
    Map<int, int>? jumpLogic,
    bool? required,
    List<String>? mediaUrls,
    double? imageScale,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'PUT',
      '$baseUrl/api/questions/$questionId',
      {
        if (title != null) 'title': title,
        if (options != null) 'options': options,
        if (jumpLogic != null) 'jumpLogic': jumpLogic.map((k, v) => MapEntry(k.toString(), v)),
        if (required != null) 'required': required,
        if (mediaUrls != null) 'mediaUrls': mediaUrls,
        if (imageScale != null) 'imageScale': imageScale,
      },
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      await _invalidate(surveyId);
      return json.decode(response.body);
    }
    throw '更新问题失败: ${response.statusCode}';
  }

  Future<void> updateQuestionsOrder({
    required int surveyId,
    required List<int> questionIds,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'PUT',
      '$baseUrl/api/survey/$surveyId/questions/reorder',
      {'questionIds': questionIds},
      onStatus: onStatus,
    );

    if (response.statusCode != 200) {
      throw '更新问题顺序失败: ${response.statusCode}';
    }
    await _invalidate(surveyId);
  }

  Future<void> _invalidate(int surveyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('questions_$surveyId');
    await prefs.remove('questions_cache_$surveyId');
  }
}

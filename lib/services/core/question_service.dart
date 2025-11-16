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
    final cacheKey = 'questions_cache_$surveyId';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        final data = json.decode(cached);
        List<Question> questions;
        if (data is List) {
          questions = data.map((e) => Question.fromJson(e)).toList();
        } else {
          questions = (data['questions'] as List).map((e) => Question.fromJson(e)).toList();
        }
        _refreshQuestionsSilently(prefs, cacheKey, surveyId);
        return questions;
      } catch (_) {}
    }
    
    return _refreshQuestions(prefs, cacheKey, surveyId, onStatus: onStatus);
  }

  Future<void> _refreshQuestionsSilently(SharedPreferences prefs, String cacheKey, int surveyId) async {
    try {
      final response = await httpRequest('GET', '$baseUrl/api/survey/$surveyId/questions');
      if (response.statusCode == 200) {
        prefs.setString(cacheKey, response.body);
      }
    } catch (_) {}
  }

  Future<List<Question>> _refreshQuestions(
    SharedPreferences prefs,
    String cacheKey,
    int surveyId, {
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest('GET', '$baseUrl/api/survey/$surveyId/questions', onStatus: onStatus);
    if (response.statusCode == 200) {
      prefs.setString(cacheKey, response.body);
      final data = json.decode(response.body);
      // 后端直接返回数组
      if (data is List) {
        return data.map((e) => Question.fromJson(e)).toList();
      }
      // 如果是包装对象，提取questions字段
      return (data['questions'] as List).map((e) => Question.fromJson(e)).toList();
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
      return json.decode(response.body);
    }
    throw '创建问题失败: ${response.statusCode}';
  }

  Future<void> deleteQuestion(int questionId, {StatusCallback? onStatus}) async {
    final response = await httpRequest('DELETE', '$baseUrl/api/questions/$questionId', onStatus: onStatus);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw '删除问题失败: ${response.statusCode}';
    }
  }

  Future<Map<String, dynamic>> updateQuestion({
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
  }
}

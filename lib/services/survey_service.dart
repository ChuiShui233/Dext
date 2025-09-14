import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/survey.dart';
import '../models/survey_stats.dart';
import '../models/question.dart';
import 'core/api_core.dart';

class SurveyService {
  final ApiCore core;
  SurveyService(this.core);

  // ===== Surveys =====
  Future<List<Survey>> getSurveys({StatusCallback? onStatus}) async {
    final prefs = await core.prefs();
    const cacheKey = 'surveys_cache';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        core.updateStatus(RequestStatus.loading, '正在加载缓存数据...');

        final List<dynamic> jsonList = json.decode(cached);
        final surveys = jsonList.map((e) => Survey.fromJson(e)).toList();

        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        core.updateStatus(RequestStatus.success, '缓存数据加载成功');

        _refreshSurveysSilently(prefs, cacheKey, surveys);
        return surveys;
      } catch (_) {
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        core.updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }
    return _refreshSurveys(prefs, cacheKey, onStatus: onStatus);
  }

  Future<void> _refreshSurveysSilently(
    SharedPreferences prefs,
    String cacheKey,
    List<Survey> cached,
  ) async {
    try {
      final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/survey/list');
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body is! List) return;
        final newList = body.map<Survey>((j) => Survey.fromJson(j)).toList();
        if (_hasChanged(cached, newList)) {
          prefs.setString(cacheKey, json.encode(body));
          core.notifyDataUpdate('surveys', newList);
          core.updateStatus(RequestStatus.success, '问卷数据已更新');
        }
      }
    } catch (_) {}
  }

  bool _hasChanged(List<Survey> a, List<Survey> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].surveyName != b[i].surveyName ||
          a[i].description != b[i].description ||
          a[i].updateTime != b[i].updateTime) {
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
    final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/survey/list', onStatus: onStatus);
    if (resp.statusCode == 200) {
      final body = json.decode(resp.body);
      if (body is! List) return [];
      prefs.setString(cacheKey, json.encode(body));
      return body.map<Survey>((j) => Survey.fromJson(j)).toList();
    }
    throw Exception('获取问卷列表失败: ${resp.statusCode}');
  }

  Future<Survey> createSurvey(Survey survey, {StatusCallback? onStatus}) async {
    final resp = await core.encryptedRequest('POST', '${ApiCore.baseUrl}/api/survey/add', survey.toJson(), onStatus: onStatus);
    if (resp.statusCode == 201) {
      await _clearSurveyListCache();
      return Survey.fromJson(json.decode(resp.body));
    }
    throw Exception('创建问卷失败: ${resp.statusCode}');
  }

  Future<Survey> updateSurvey(Survey survey, {StatusCallback? onStatus}) async {
    final resp = await core.encryptedRequest('PUT', '${ApiCore.baseUrl}/api/survey/update', survey.toJson(), onStatus: onStatus);
    if (resp.statusCode == 200) {
      await _clearSurveyListCache();
      return Survey.fromJson(json.decode(resp.body));
    }
    throw Exception('更新问卷失败: ${resp.statusCode}');
  }

  Future<void> deleteSurvey(int id, {StatusCallback? onStatus}) async {
    final resp = await core.httpRequest('DELETE', '${ApiCore.baseUrl}/api/survey/delete/$id', onStatus: onStatus);
    if (resp.statusCode == 200) {
      await _clearSurveyRelatedCache(id);
      return;
    }
    throw Exception('删除问卷失败: ${resp.statusCode}');
  }

  Future<void> batchDeleteSurveys(List<int> ids, {StatusCallback? onStatus}) async {
    final resp = await core.httpRequest('DELETE', '${ApiCore.baseUrl}/api/survey/batch-delete', data: {'surveyIds': ids}, onStatus: onStatus);
    if (resp.statusCode == 200) {
      for (final id in ids) {
        await _clearSurveyRelatedCache(id);
      }
      return;
    }
    throw Exception('批量删除问卷失败: ${resp.statusCode}');
  }

  Future<void> _clearSurveyListCache() async {
    final prefs = await core.prefs();
    await prefs.remove('surveys_cache');
    await prefs.remove('survey_stats_cache');
    core.notifyDataUpdate('surveys_updated', {'action': 'mutated'});
    core.notifyDataUpdate('survey_stats_updated', {'action': 'mutated'});
  }

  Future<void> _clearSurveyRelatedCache(int surveyId) async {
    final prefs = await core.prefs();
    await prefs.remove('surveys_cache');
    await prefs.remove('survey_stats_cache');
    await prefs.remove('questions_$surveyId');
    core.notifyDataUpdate('surveys_deleted', {'deletedId': surveyId});
    core.notifyDataUpdate('survey_stats_deleted', {'deletedId': surveyId});
    core.notifyDataUpdate('questions_deleted', {'deletedId': surveyId});
  }

  // ===== Background =====
  Future<void> updateSurveyBackground(
    int surveyId, {
    String? desktopBackground,
    String? mobileBackground,
    StatusCallback? onStatus,
  }) async {
    final Map<String, dynamic> data = {
      'desktopBackground': desktopBackground ?? '',
      'mobileBackground': mobileBackground ?? '',
    };
    final resp = await core.httpRequest('PUT', '${ApiCore.baseUrl}/api/survey/$surveyId/background', data: data, onStatus: onStatus);
    if (resp.statusCode != 200) {
      throw Exception('更新问卷背景失败: ${resp.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getSurveyBackground(int surveyId, {StatusCallback? onStatus}) async {
    final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/survey/$surveyId/background', onStatus: onStatus);
    if (resp.statusCode == 200) {
      return json.decode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('获取问卷背景失败: ${resp.statusCode}');
  }

  // ===== Questions (skeleton for future phases) =====
  Future<List<Question>> getSurveyQuestions(int surveyId, {StatusCallback? onStatus}) async {
    final prefs = await core.prefs();
    final cacheKey = 'questions_$surveyId';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        core.updateStatus(RequestStatus.loading, '正在加载缓存数据...');
        final List<dynamic> jsonList = json.decode(cached);
        final questions = jsonList.map((e) => Question.fromJson(e)).toList();
        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        core.updateStatus(RequestStatus.success, '缓存数据加载成功');
        _refreshSurveyQuestionsSilently(surveyId, prefs, cacheKey, questions);
        return questions;
      } catch (_) {}
    }
    return _refreshSurveyQuestions(surveyId, prefs, cacheKey, onStatus: onStatus);
  }

  Future<void> _refreshSurveyQuestionsSilently(
    int surveyId,
    SharedPreferences prefs,
    String cacheKey,
    List<Question> cached,
  ) async {
    try {
      final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/survey/$surveyId/questions');
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body is! List) return;
        final newList = body.map<Question>((j) => Question.fromJson(j)).toList();
        if (_questionsChanged(cached, newList)) {
          prefs.setString(cacheKey, json.encode(body));
          core.notifyDataUpdate('questions_$surveyId', newList);
          core.updateStatus(RequestStatus.success, '问卷问题数据已更新');
        }
      }
    } catch (_) {}
  }

  bool _questionsChanged(List<Question> a, List<Question> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].title != b[i].title || a[i].type != b[i].type || a[i].order != b[i].order) {
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
    final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/survey/$surveyId/questions', onStatus: onStatus);
    if (resp.statusCode == 200) {
      final body = json.decode(resp.body);
      if (body is! List) return [];
      prefs.setString(cacheKey, json.encode(body));
      return body.map<Question>((j) => Question.fromJson(j)).toList();
    }
    throw Exception('获取问卷问题列表失败: ${resp.statusCode}');
  }

  // ===== Stats (skeleton for future phases) =====
  Future<SurveyStats> getSurveyStats(int surveyId, {StatusCallback? onStatus}) async {
    final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/survey/stats/$surveyId', onStatus: onStatus);
    if (resp.statusCode == 200) {
      return SurveyStats.fromJson(json.decode(resp.body));
    }
    throw Exception('获取问卷统计信息失败: ${resp.statusCode}');
  }

  Future<List<SurveyStats>> getAllSurveyStats({StatusCallback? onStatus}) async {
    final prefs = await core.prefs();
    const cacheKey = 'survey_stats_cache';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final List<dynamic> jsonList = json.decode(cached);
        final stats = jsonList.map((e) => SurveyStats.fromJson(e)).toList();
        _refreshAllSurveyStatsSilently(prefs, cacheKey, stats);
        return stats;
      } catch (_) {}
    }
    return _refreshAllSurveyStats(prefs, cacheKey, onStatus: onStatus);
  }

  Future<void> _refreshAllSurveyStatsSilently(
    SharedPreferences prefs,
    String cacheKey,
    List<SurveyStats> cached,
  ) async {
    try {
      final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/survey/stats');
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body is List) {
          final next = body.map<SurveyStats>((j) => SurveyStats.fromJson(j)).toList();
          if (_statsChanged(cached, next)) {
            prefs.setString(cacheKey, json.encode(body));
            core.notifyDataUpdate('survey_stats', next);
            core.updateStatus(RequestStatus.success, '问卷统计数据已更新');
          }
        }
      }
    } catch (_) {}
  }

  bool _statsChanged(List<SurveyStats> a, List<SurveyStats> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].surveyId != b[i].surveyId ||
          a[i].viewCount != b[i].viewCount ||
          a[i].submitCount != b[i].submitCount ||
          a[i].lastViewTime != b[i].lastViewTime ||
          a[i].lastSubmitTime != b[i].lastSubmitTime) {
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
    final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/survey/stats', onStatus: onStatus);
    if (resp.statusCode == 200) {
      final body = json.decode(resp.body);
      if (body is List) {
        prefs.setString(cacheKey, json.encode(body));
        return body.map<SurveyStats>((j) => SurveyStats.fromJson(j)).toList();
      }
      return [];
    }
    throw Exception('获取问卷统计信息失败: ${resp.statusCode}');
  }
}

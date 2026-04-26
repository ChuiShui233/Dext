import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/survey.dart';
import '../models/paginated_response.dart';
import 'core/api_core.dart';

class SurveyService {
  final ApiCore core;
  SurveyService(this.core);

  // ===== Surveys =====
  Future<List<Survey>> getSurveys({StatusCallback? onStatus, bool skipCache = false}) async {
    final prefs = await core.prefs();
    const cacheKey = 'surveys_cache';
    final cached = prefs.getString(cacheKey);
    if (cached != null && !skipCache) {
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

  Future<PaginatedResponse<Survey>> getSurveysPaginated({
    int page = 1,
    int pageSize = 10,
    String? search,
    String? type,
    bool skipCache = false,
    StatusCallback? onStatus,
  }) async {
    final prefs = await core.prefs();
    final cacheKey = 'surveys_paginated_${page}_${pageSize}_${search ?? ""}_${type ?? ""}';
    final cached = prefs.getString(cacheKey);

    if (cached != null && !skipCache) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        core.updateStatus(RequestStatus.loading, '正在加载缓存数据...');

        final cachedData = json.decode(cached);
        PaginatedResponse<Survey> paginatedResponse;

        if (cachedData is List) {
          final items = cachedData.map<Survey>((j) => Survey.fromJson(j as Map<String, dynamic>)).toList();
          paginatedResponse = PaginatedResponse<Survey>(
            items: items,
            total: items.length,
            page: page,
            pageSize: pageSize,
            totalPages: items.isEmpty ? 0 : ((items.length + pageSize - 1) ~/ pageSize),
          );
        } else {
          paginatedResponse = PaginatedResponse.fromJson(cachedData as Map<String, dynamic>, (json) => Survey.fromJson(json));
        }

        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        core.updateStatus(RequestStatus.success, '缓存数据加载成功');

        // 静默刷新
        _refreshSurveysPaginatedSilently(prefs, cacheKey, page, pageSize, search, type, paginatedResponse);
        return paginatedResponse;
      } catch (_) {
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        core.updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }

    return _refreshSurveysPaginated(prefs, cacheKey, page, pageSize, search, type, onStatus: onStatus);
  }

  Future<void> _refreshSurveysPaginatedSilently(
    SharedPreferences prefs,
    String cacheKey,
    int page,
    int pageSize,
    String? search,
    String? type,
    PaginatedResponse<Survey> cached,
  ) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (search != null && search.isNotEmpty) {
        queryParams['query'] = search;
      }
      if (type != null && type.isNotEmpty) {
        queryParams['type'] = type;
      }
      final uri = Uri.parse('${ApiCore.baseUrl}/api/survey/list').replace(queryParameters: queryParams);
      final resp = await core.httpRequest('GET', uri.toString());

      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        PaginatedResponse<Survey> newResponse;

        if (body is List) {
          final items = body.map<Survey>((j) => Survey.fromJson(j as Map<String, dynamic>)).toList();
          newResponse = PaginatedResponse<Survey>(
            items: items,
            total: items.length,
            page: page,
            pageSize: pageSize,
            totalPages: items.isEmpty ? 0 : ((items.length + pageSize - 1) ~/ pageSize),
          );
        } else {
          newResponse = PaginatedResponse.fromJson(body as Map<String, dynamic>, (json) => Survey.fromJson(json));
        }

        if (_surveysPaginatedHasChanged(cached, newResponse)) {
          prefs.setString(cacheKey, json.encode(body));
          core.notifyDataUpdate('surveys_paginated', newResponse);
          core.updateStatus(RequestStatus.success, '问卷数据已更新');
        }
      }
    } catch (_) {}
  }

  bool _surveysPaginatedHasChanged(PaginatedResponse<Survey> a, PaginatedResponse<Survey> b) {
    if (a.total != b.total || a.items.length != b.items.length) return true;
    return _hasChanged(a.items, b.items);
  }

  Future<PaginatedResponse<Survey>> _refreshSurveysPaginated(
    SharedPreferences prefs,
    String cacheKey,
    int page,
    int pageSize,
    String? search,
    String? type, {
    StatusCallback? onStatus,
  }) async {
    onStatus?.call(RequestStatus.loading, '正在获取问卷列表...');
    core.updateStatus(RequestStatus.loading, '正在获取问卷列表...');

    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (search != null && search.isNotEmpty) {
      queryParams['query'] = search;
    }
    if (type != null && type.isNotEmpty) {
      queryParams['type'] = type;
    }

    final uri = Uri.parse('${ApiCore.baseUrl}/api/survey/list').replace(queryParameters: queryParams);
    final resp = await core.httpRequest('GET', uri.toString(), onStatus: onStatus);

    if (resp.statusCode == 200) {
      final dynamic body = json.decode(resp.body);
      prefs.setString(cacheKey, json.encode(body));

      // 兼容两种返回格式：
      // 1) 非分页：直接返回数组 [ {...}, {...} ]
      // 2) 分页：返回对象 { items: [...], total: n, page: n, pageSize: n, totalPages: n }
      if (body is List) {
        final items = body.map<Survey>((j) => Survey.fromJson(j as Map<String, dynamic>)).toList();
        final paginated = PaginatedResponse<Survey>(
          items: items,
          total: items.length,
          page: page,
          pageSize: pageSize,
          totalPages: items.isEmpty ? 0 : ((items.length + pageSize - 1) ~/ pageSize),
        );
        onStatus?.call(RequestStatus.success, '问卷列表获取成功');
        core.updateStatus(RequestStatus.success, '问卷列表获取成功');
        return paginated;
      } else if (body is Map<String, dynamic>) {
        final paginatedResponse = PaginatedResponse.fromJson(body, (json) => Survey.fromJson(json));
        onStatus?.call(RequestStatus.success, '问卷列表获取成功');
        core.updateStatus(RequestStatus.success, '问卷列表获取成功');
        return paginatedResponse;
      } else {
        throw '未知的问卷列表返回格式';
      }
    }
    throw '获取问卷列表失败: ${resp.statusCode}';
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
    throw '获取问卷列表失败: ${resp.statusCode}';
  }

  Future<Survey> updateSurvey(Survey survey, {StatusCallback? onStatus}) async {
    final resp = await core.encryptedRequest('PUT', '${ApiCore.baseUrl}/api/survey/update', survey.toJson(), onStatus: onStatus);
    if (resp.statusCode == 200) {
      await _clearSurveyListCache();
      return Survey.fromJson(json.decode(resp.body));
    }
    throw '更新问卷失败: ${resp.statusCode}';
  }

  Future<void> _clearSurveyListCache() async {
    final prefs = await core.prefs();
    await prefs.remove('surveys_cache');
    await prefs.remove('survey_stats_cache');
    // 清除所有分页缓存
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('surveys_paginated_')) {
        await prefs.remove(key);
      }
    }
    core.notifyDataUpdate('surveys_updated', {'action': 'mutated'});
    core.notifyDataUpdate('survey_stats_updated', {'action': 'mutated'});
  }
}

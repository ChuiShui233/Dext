import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../models/paginated_response.dart';
import 'core/api_core.dart';

class ProjectService {
  final ApiCore core;
  ProjectService(this.core);

  Future<List<Project>> getProjects({StatusCallback? onStatus}) async {
    final prefs = await core.prefs();
    const cacheKey = 'projects_cache';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        core.updateStatus(RequestStatus.loading, '正在加载缓存数据...');

        final List<dynamic> jsonList = json.decode(cached);
        final projects = jsonList.map((e) => Project.fromJson(e)).toList();

        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        core.updateStatus(RequestStatus.success, '缓存数据加载成功');

        // 静默刷新
        _refreshProjectsSilently(prefs, cacheKey, projects);
        return projects;
      } catch (_) {
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        core.updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }
    return _refreshProjects(prefs, cacheKey, onStatus: onStatus);
  }

  Future<PaginatedResponse<Project>> getProjectsPaginated({
    int page = 1,
    int pageSize = 10,
    String? search,
    StatusCallback? onStatus,
  }) async {
    final prefs = await core.prefs();
    final cacheKey = 'projects_paginated_${page}_${pageSize}_${search ?? ""}';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        onStatus?.call(RequestStatus.loading, '正在加载缓存数据...');
        core.updateStatus(RequestStatus.loading, '正在加载缓存数据...');
        
        final cachedData = json.decode(cached) as Map<String, dynamic>;
        final paginatedResponse = PaginatedResponse.fromJson(cachedData, (json) => Project.fromJson(json));
        
        onStatus?.call(RequestStatus.success, '缓存数据加载成功');
        core.updateStatus(RequestStatus.success, '缓存数据加载成功');
        
        // 静默刷新
        _refreshProjectsPaginatedSilently(prefs, cacheKey, page, pageSize, search, paginatedResponse);
        return paginatedResponse;
      } catch (_) {
        onStatus?.call(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
        core.updateStatus(RequestStatus.error, '缓存数据解析失败，正在从网络获取...');
      }
    }
    
    return _refreshProjectsPaginated(prefs, cacheKey, page, pageSize, search, onStatus: onStatus);
  }

  Future<void> _refreshProjectsPaginatedSilently(
    SharedPreferences prefs,
    String cacheKey,
    int page,
    int pageSize,
    String? search,
    PaginatedResponse<Project> cached,
  ) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      final uri = Uri.parse('${ApiCore.baseUrl}/api/project/list').replace(queryParameters: queryParams);
      final resp = await core.httpRequest('GET', uri.toString());
      
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final newResponse = PaginatedResponse.fromJson(body, (json) => Project.fromJson(json));
        
        if (_paginatedHasChanged(cached, newResponse)) {
          prefs.setString(cacheKey, json.encode(body));
          core.notifyDataUpdate('projects_paginated', newResponse);
          core.updateStatus(RequestStatus.success, '项目数据已更新');
        }
      }
    } catch (_) {}
  }

  bool _paginatedHasChanged(PaginatedResponse<Project> a, PaginatedResponse<Project> b) {
    if (a.total != b.total || a.items.length != b.items.length) return true;
    return _hasChanged(a.items, b.items);
  }

  Future<PaginatedResponse<Project>> _refreshProjectsPaginated(
    SharedPreferences prefs,
    String cacheKey,
    int page,
    int pageSize,
    String? search, {
    StatusCallback? onStatus,
  }) async {
    onStatus?.call(RequestStatus.loading, '正在获取项目列表...');
    core.updateStatus(RequestStatus.loading, '正在获取项目列表...');

    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    final uri = Uri.parse('${ApiCore.baseUrl}/api/project/list').replace(queryParameters: queryParams);
    final resp = await core.httpRequest('GET', uri.toString(), onStatus: onStatus);
    
    if (resp.statusCode == 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      prefs.setString(cacheKey, json.encode(body));
      final paginatedResponse = PaginatedResponse.fromJson(body, (json) => Project.fromJson(json));
      
      onStatus?.call(RequestStatus.success, '项目列表获取成功');
      core.updateStatus(RequestStatus.success, '项目列表获取成功');
      
      return paginatedResponse;
    }
    throw '获取项目列表失败: ${resp.statusCode}';
  }

  Future<void> _refreshProjectsSilently(
    SharedPreferences prefs,
    String cacheKey,
    List<Project> cached,
  ) async {
    try {
      final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/project/list');
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body is! List) return;
        final newList = body.map<Project>((j) => Project.fromJson(j)).toList();
        if (_hasChanged(cached, newList)) {
          prefs.setString(cacheKey, json.encode(body));
          core.notifyDataUpdate('projects', newList);
          core.updateStatus(RequestStatus.success, '项目数据已更新');
        }
      }
    } catch (_) {}
  }

  bool _hasChanged(List<Project> a, List<Project> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].projectName != b[i].projectName ||
          a[i].projectDescription != b[i].projectDescription ||
          a[i].updateTime != b[i].updateTime) {
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
    final resp = await core.httpRequest('GET', '${ApiCore.baseUrl}/api/project/list', onStatus: onStatus);
    if (resp.statusCode == 200) {
      final body = json.decode(resp.body);
      if (body is! List) return [];
      prefs.setString(cacheKey, json.encode(body));
      return body.map<Project>((j) => Project.fromJson(j)).toList();
    }
    throw '获取项目列表失败: ${resp.statusCode}';
  }

  Future<Project> createProject(Project project, {StatusCallback? onStatus}) async {
    final resp = await core.encryptedRequest('POST', '${ApiCore.baseUrl}/api/project/add', project.toJson(), onStatus: onStatus);
    if (resp.statusCode == 201) {
      await _clearProjectListCache();
      return Project.fromJson(json.decode(resp.body));
    }
    throw '创建项目失败: ${resp.statusCode}';
  }

  Future<void> updateProject(Project project, {StatusCallback? onStatus}) async {
    final resp = await core.encryptedRequest('PUT', '${ApiCore.baseUrl}/api/project/update', project.toJson(), onStatus: onStatus);
    if (resp.statusCode == 200) {
      await _clearProjectListCache();
      return;
    }
    throw '更新项目失败: ${resp.statusCode}';
  }

  Future<void> deleteProject(int id, {StatusCallback? onStatus}) async {
    final resp = await core.httpRequest('DELETE', '${ApiCore.baseUrl}/api/project/delete/$id', onStatus: onStatus);
    if (resp.statusCode == 200) {
      await _clearProjectRelatedCache(id);
      return;
    }
    throw '删除项目失败: ${resp.statusCode}';
  }

  Future<void> batchDeleteProjects(List<int> ids, {StatusCallback? onStatus}) async {
    final resp = await core.httpRequest('DELETE', '${ApiCore.baseUrl}/api/project/batch-delete', data: {'projectIds': ids}, onStatus: onStatus);
    if (resp.statusCode == 200) {
      for (final id in ids) {
        await _clearProjectRelatedCache(id);
      }
      return;
    }
    throw '批量删除项目失败: ${resp.statusCode}';
  }

  Future<void> _clearProjectListCache() async {
    final prefs = await core.prefs();
    await prefs.remove('projects_cache');
    // 清除所有分页缓存
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('projects_paginated_')) {
        await prefs.remove(key);
      }
    }
    core.notifyDataUpdate('projects_updated', {'action': 'mutated'});
  }

  Future<void> _clearProjectRelatedCache(int projectId) async {
    final prefs = await core.prefs();
    await prefs.remove('projects_cache');
    await prefs.remove('surveys_cache');
    await prefs.remove('survey_stats_cache');
    // 清除所有分页缓存
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('projects_paginated_') || 
          key.startsWith('surveys_paginated_')) {
        await prefs.remove(key);
      }
    }
    core.notifyDataUpdate('projects_deleted', {'deletedId': projectId});
    core.notifyDataUpdate('surveys_deleted', {'deletedId': projectId});
    core.notifyDataUpdate('survey_stats_deleted', {'deletedId': projectId});
  }
}

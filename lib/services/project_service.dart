import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
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
    throw Exception('获取项目列表失败: ${resp.statusCode}');
  }

  Future<Project> createProject(Project project, {StatusCallback? onStatus}) async {
    final resp = await core.encryptedRequest('POST', '${ApiCore.baseUrl}/api/project/add', project.toJson(), onStatus: onStatus);
    if (resp.statusCode == 201) {
      await _clearProjectListCache();
      return Project.fromJson(json.decode(resp.body));
    }
    throw Exception('创建项目失败: ${resp.statusCode}');
  }

  Future<void> updateProject(Project project, {StatusCallback? onStatus}) async {
    final resp = await core.encryptedRequest('PUT', '${ApiCore.baseUrl}/api/project/update', project.toJson(), onStatus: onStatus);
    if (resp.statusCode == 200) {
      await _clearProjectListCache();
      return;
    }
    throw Exception('更新项目失败: ${resp.statusCode}');
  }

  Future<void> deleteProject(int id, {StatusCallback? onStatus}) async {
    final resp = await core.httpRequest('DELETE', '${ApiCore.baseUrl}/api/project/delete/$id', onStatus: onStatus);
    if (resp.statusCode == 200) {
      await _clearProjectRelatedCache(id);
      return;
    }
    throw Exception('删除项目失败: ${resp.statusCode}');
  }

  Future<void> batchDeleteProjects(List<int> ids, {StatusCallback? onStatus}) async {
    final resp = await core.httpRequest('DELETE', '${ApiCore.baseUrl}/api/project/batch-delete', data: {'projectIds': ids}, onStatus: onStatus);
    if (resp.statusCode == 200) {
      for (final id in ids) {
        await _clearProjectRelatedCache(id);
      }
      return;
    }
    throw Exception('批量删除项目失败: ${resp.statusCode}');
  }

  Future<void> _clearProjectListCache() async {
    final prefs = await core.prefs();
    await prefs.remove('projects_cache');
    core.notifyDataUpdate('projects_updated', {'action': 'mutated'});
  }

  Future<void> _clearProjectRelatedCache(int projectId) async {
    final prefs = await core.prefs();
    await prefs.remove('projects_cache');
    await prefs.remove('surveys_cache');
    await prefs.remove('survey_stats_cache');
    core.notifyDataUpdate('projects_deleted', {'deletedId': projectId});
    core.notifyDataUpdate('surveys_deleted', {'deletedId': projectId});
    core.notifyDataUpdate('survey_stats_deleted', {'deletedId': projectId});
  }
}

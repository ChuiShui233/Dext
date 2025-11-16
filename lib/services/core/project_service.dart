import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/project.dart';
import 'api_core.dart';

class ProjectService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, {StatusCallback? onStatus}) httpRequest;
  final Future<http.Response> Function(String, String, Map<String, dynamic>?, {StatusCallback? onStatus}) encryptedRequest;
  
  ProjectService({required this.baseUrl, required this.httpRequest, required this.encryptedRequest});

  Future<List<Project>> getProjects({StatusCallback? onStatus}) async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'projects_cache';
    final cached = prefs.getString(cacheKey);
    
    if (cached != null) {
      try {
        final data = json.decode(cached);
        List<Project> projects;
        if (data is List) {
          projects = data.map((e) => Project.fromJson(e)).toList();
        } else {
          projects = (data['items'] as List).map((e) => Project.fromJson(e)).toList();
        }
        _refreshProjectsSilently(prefs, cacheKey);
        return projects;
      } catch (_) {}
    }
    
    return _refreshProjects(prefs, cacheKey, onStatus: onStatus);
  }

  Future<void> _refreshProjectsSilently(SharedPreferences prefs, String cacheKey) async {
    try {
      final response = await httpRequest('GET', '$baseUrl/api/project/list');
      if (response.statusCode == 200) {
        prefs.setString(cacheKey, response.body);
      }
    } catch (_) {}
  }

  Future<List<Project>> _refreshProjects(
    SharedPreferences prefs,
    String cacheKey, {
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest('GET', '$baseUrl/api/project/list', onStatus: onStatus);
    if (response.statusCode == 200) {
      prefs.setString(cacheKey, response.body);
      final data = json.decode(response.body);
      // 后端无分页参数时直接返回数组
      if (data is List) {
        return data.map((e) => Project.fromJson(e)).toList();
      }
      // 如果是分页对象，提取items
      return (data['items'] as List).map((e) => Project.fromJson(e)).toList();
    }
    throw '获取项目列表失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> createProject({
    required String projectName,
    String? description,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'POST',
      '$baseUrl/api/projects',
      {'projectName': projectName, 'description': description},
      onStatus: onStatus,
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else if (response.statusCode == 400) {
      final errorData = json.decode(response.body);
      throw errorData['error'] ?? '创建项目失败';
    }
    throw '创建项目失败: ${response.statusCode}';
  }

  Future<void> deleteProject(int projectId, {StatusCallback? onStatus}) async {
    final response = await httpRequest('DELETE', '$baseUrl/api/projects/$projectId', onStatus: onStatus);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw '删除项目失败: ${response.statusCode}';
    }
  }

  Future<Map<String, dynamic>> updateProject({
    required int projectId,
    String? projectName,
    String? description,
    StatusCallback? onStatus,
  }) async {
    final response = await encryptedRequest(
      'PUT',
      '$baseUrl/api/projects/$projectId',
      {
        if (projectName != null) 'projectName': projectName,
        if (description != null) 'description': description,
      },
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw '更新项目失败: ${response.statusCode}';
  }
}

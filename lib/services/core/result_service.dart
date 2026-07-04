import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/survey_result.dart';
import '../../models/paginated_response.dart';
import 'api_core.dart';

class ResultService {
  final String baseUrl;
  final Future<http.Response> Function(String, String, {StatusCallback? onStatus}) httpRequest;
  
  ResultService({required this.baseUrl, required this.httpRequest});

  Future<PaginatedResponse<SurveyResult>> getSurveyResults({
    required int surveyId,
    int page = 1,
    int pageSize = 20,
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest(
      'GET',
      '$baseUrl/api/answer/list/$surveyId',
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      final raw = response.body.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') {
        return PaginatedResponse<SurveyResult>(
          items: const <SurveyResult>[],
          total: 0,
          page: 1,
          pageSize: 0,
          totalPages: 0,
        );
      }
      dynamic data;
      try {
        data = json.decode(raw);
      } catch (_) {
        return PaginatedResponse<SurveyResult>(
          items: const <SurveyResult>[],
          total: 0,
          page: 1,
          pageSize: 0,
          totalPages: 0,
        );
      }
      // 后端直接返回数组，需要包装为分页格式
      if (data is List) {
        final items = data
            .whereType<Map<String, dynamic>>()
            .map((e) => SurveyResult.fromJson(e))
            .toList();
        return PaginatedResponse<SurveyResult>(
          items: items,
          total: items.length,
          page: 1,
          pageSize: items.length,
          totalPages: 1,
        );
      }
      // 如果是分页对象，直接解析；否则返回空
      if (data is Map<String, dynamic>) {
        return PaginatedResponse<SurveyResult>.fromJson(
          data,
          (json) => SurveyResult.fromJson(json),
        );
      }
      return PaginatedResponse<SurveyResult>(
        items: const <SurveyResult>[],
        total: 0,
        page: 1,
        pageSize: 0,
        totalPages: 0,
      );
    }
    throw '获取问卷结果失败: ${response.statusCode}';
  }

  Future<Map<String, dynamic>> exportResults({
    required int surveyId,
    String format = 'csv',
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest(
      'GET',
      '$baseUrl/api/surveys/$surveyId/export?format=$format',
      onStatus: onStatus,
    );

    if (response.statusCode == 200) {
      final raw = response.body.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') {
        return <String, dynamic>{};
      }
      try {
        final dynamic data = json.decode(raw);
        if (data is Map<String, dynamic>) return data;
      } catch (_) {}
      return <String, dynamic>{};
    }
    throw '导出结果失败: ${response.statusCode}';
  }

  Future<void> deleteResult({
    required int surveyId,
    required int resultId,
    StatusCallback? onStatus,
  }) async {
    final response = await httpRequest(
      'DELETE',
      '$baseUrl/api/answer/$resultId',
      onStatus: onStatus,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw '删除结果失败: ${response.statusCode}';
    }
  }
}

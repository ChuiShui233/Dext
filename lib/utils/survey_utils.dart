class SurveyUtils {
  /// 从文本或 URL 中提取 16 位问卷 ID
  static String extractSurveyId(String text) {
    if (text.isEmpty) return '';
    
    String surveyId = text.trim();
    
    // 尝试从 URL 参数中提取 (例如 ?id=...)
    if (surveyId.contains('?id=')) {
      final uri = Uri.tryParse(surveyId);
      if (uri != null && uri.queryParameters.containsKey('id')) {
        return uri.queryParameters['id']!;
      }
    }
    
    // 尝试从路径中提取 (例如 /survey/...)
    if (surveyId.contains('/')) {
      final parts = surveyId.split('/');
      // 过滤掉空字符串并取最后一个
      final lastPart = parts.where((p) => p.isNotEmpty).last;
      return lastPart;
    }
    
    return surveyId;
  }

  /// 验证问卷 ID 是否有效 (目前为 16 位)
  static bool isValidSurveyId(String id) {
    return id.length == 16;
  }
}

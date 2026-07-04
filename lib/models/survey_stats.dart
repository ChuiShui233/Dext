class SurveyStats {
  final int surveyId;
  final String surveyName;
  final int viewCount;
  final int submitCount;
  final List<String> submittedUsers;
  final DateTime lastViewTime;
  final DateTime lastSubmitTime;

  SurveyStats({
    required this.surveyId,
    required this.surveyName,
    required this.viewCount,
    required this.submitCount,
    required this.submittedUsers,
    required this.lastViewTime,
    required this.lastSubmitTime,
  });

  factory SurveyStats.fromJson(Map<String, dynamic> json) {
    // 安全处理 submittedUsers 字段
    List<String> users = [];
    if (json['submittedUsers'] != null) {
      if (json['submittedUsers'] is List) {
        users = List<String>.from(
          json['submittedUsers'].map((e) => e.toString())
        );
      } else {
        // 处理单个用户字符串的情况
        users = [json['submittedUsers'].toString()];
      }
    }
    
    // 安全处理时间字段
    DateTime parseTime(dynamic time) {
      if (time == null) return DateTime(1970);
      try {
        // 尝试解析 ISO 8601 格式
        final timeStr = time.toString();
        if (timeStr == '1970-01-01T00:00:00Z') {
          return DateTime(1970);
        }
        return DateTime.parse(timeStr);
      } catch (e) {
        // 如果解析失败，返回 1970 年
        return DateTime(1970);
      }
    }

    return SurveyStats(
      surveyId: (json['surveyId'] ?? 0) as int,
      surveyName: (json['surveyName'] ?? '') as String,
      viewCount: (json['viewCount'] ?? 0) as int,
      submitCount: (json['submitCount'] ?? 0) as int,
      submittedUsers: users,
      lastViewTime: parseTime(json['lastViewTime']),
      lastSubmitTime: parseTime(json['lastSubmitTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'surveyId': surveyId,
      'surveyName': surveyName,
      'viewCount': viewCount,
      'submitCount': submitCount,
      'submittedUsers': submittedUsers,
      'lastViewTime': lastViewTime.toIso8601String(),
      'lastSubmitTime': lastSubmitTime.toIso8601String(),
    };
  }
}
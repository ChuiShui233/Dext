class SurveyResult {
  final int id;
  final int surveyId;
  final String userId;
  final String userAccount;
  final String createTime;
  final List<AnswerDetail> questions;

  SurveyResult({
    required this.id,
    required this.surveyId,
    required this.userId,
    required this.userAccount,
    required this.createTime,
    required this.questions,
  });

  factory SurveyResult.fromJson(Map<String, dynamic> json) {
    return SurveyResult(
      id: json['id'] as int? ?? 0,
      surveyId: json['surveyId'] as int? ?? 0,
      userId: json['userId'] as String? ?? '',
      userAccount: json['userAccount'] as String? ?? '',
      createTime: json['createTime'] as String? ?? '',
      questions: (json['questions'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((q) => AnswerDetail.fromJson(q))
              .toList() 
          ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'surveyId': surveyId,
      'userId': userId,
      'userAccount': userAccount,
      'createTime': createTime,
      'questions': questions.map((q) => q.toJson()).toList(),
    };
  }
}

class AnswerDetail {
  final int id;
  final int answerId;
  final int questionId;
  final List<int> selectedOptions;
  final String selectChoices;

  AnswerDetail({
    required this.id,
    required this.answerId,
    required this.questionId,
    required this.selectedOptions,
    required this.selectChoices,
  });

  factory AnswerDetail.fromJson(Map<String, dynamic> json) {
    // 兼容后端新旧字段：
    // - 选项索引：优先 selectedOptions，其次 indices
    // - 文本答案：优先 selectChoices，其次 answer（可能是字符串或字符串数组）
    List<int> parseSelectedOptions(dynamic value) {
      final list = (value as List<dynamic>?) ?? const [];
      return list.map((e) {
        if (e is int) return e;
        final parsed = int.tryParse(e.toString());
        return parsed ?? 0;
      }).toList();
    }

    String parseSelectChoices(Map<String, dynamic> j) {
      final direct = j['selectChoices'] as String?;
      if (direct != null && direct.isNotEmpty) return direct;
      final ans = j['answer'];
      if (ans is String && ans.isNotEmpty) return ans;
      if (ans is List && ans.isNotEmpty) return ans.first.toString();
      return '';
    }

    final selected = json.containsKey('selectedOptions')
        ? parseSelectedOptions(json['selectedOptions'])
        : parseSelectedOptions(json['indices']);

    return AnswerDetail(
      id: json['id'] as int? ?? 0,
      answerId: json['answerId'] as int? ?? 0,
      questionId: json['questionId'] as int? ?? 0,
      selectedOptions: selected,
      selectChoices: parseSelectChoices(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'answerId': answerId,
      'questionId': questionId,
      'selectedOptions': selectedOptions,
      'selectChoices': selectChoices,
    };
  }
}

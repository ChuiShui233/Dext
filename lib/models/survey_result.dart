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
          ?.map((q) => AnswerDetail.fromJson(q))
          .toList() ?? [],
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
    return AnswerDetail(
      id: json['id'] as int? ?? 0,
      answerId: json['answerId'] as int? ?? 0,
      questionId: json['questionId'] as int? ?? 0,
      selectedOptions: (json['selectedOptions'] as List<dynamic>?)
          ?.map((option) => option as int)
          .toList() ?? [],
      selectChoices: json['selectChoices'] as String? ?? '',
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

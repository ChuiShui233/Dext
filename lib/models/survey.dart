class Survey {
  final int id;
  final String surveyUid; // 新增唯一标识符字段
  final String surveyName;
  final String description;
  final int surveyType;
  final int surveyStatus;
  final int totalTimes;
  final int? perUserLimit; // 单用户提交上限（空/0 为不限）
  final int projectId; // 关键字段：问卷所属项目ID
  final String? deadline;
  final String createTime;
  final String updateTime;
  final bool autoSubmit; // 自动提交
  final bool allowAnonymous; // 允许匿名提交

  Survey({
    required this.id,
    required this.surveyUid,
    required this.surveyName,
    required this.description,
    required this.surveyType,
    required this.surveyStatus,
    required this.totalTimes,
    this.perUserLimit,
    required this.projectId,
    this.deadline,
    required this.createTime,
    required this.updateTime,
    this.autoSubmit = false,
    this.allowAnonymous = false,
  });

  Survey copyWith({
    int? id,
    String? surveyUid,
    String? surveyName,
    String? description,
    int? surveyType,
    int? surveyStatus,
    int? totalTimes,
    int? perUserLimit,
    int? projectId,
    String? deadline,
    String? createTime,
    String? updateTime,
    bool? autoSubmit,
    bool? allowAnonymous,
  }) {
    return Survey(
      id: id ?? this.id,
      surveyUid: surveyUid ?? this.surveyUid,
      surveyName: surveyName ?? this.surveyName,
      description: description ?? this.description,
      surveyType: surveyType ?? this.surveyType,
      surveyStatus: surveyStatus ?? this.surveyStatus,
      totalTimes: totalTimes ?? this.totalTimes,
      perUserLimit: perUserLimit ?? this.perUserLimit,
      projectId: projectId ?? this.projectId, // 包含项目ID
      deadline: deadline ?? this.deadline,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
      autoSubmit: autoSubmit ?? this.autoSubmit,
      allowAnonymous: allowAnonymous ?? this.allowAnonymous,
    );
  }

  factory Survey.fromJson(Map<String, dynamic> json) {
    return Survey(
      id: json['id'] as int? ?? 0,
      surveyUid: json['survey_uid'] ?? json['surveyUid'] ?? '',
      surveyName: json['surveyName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      surveyType: json['surveyType'] as int? ?? 0,
      surveyStatus: json['surveyStatus'] as int? ?? 0,
      totalTimes: json['totalTimes'] as int? ?? 0,
      perUserLimit: json['per_user_limit'] as int? ?? json['perUserLimit'] as int?,
      projectId: json['projectId'] as int? ?? json['project_id'] as int? ?? 0,
      deadline: json['deadline'] as String?,
      createTime: json['createTime'] as String? ?? '',
      updateTime: json['updateTime'] as String? ?? '',
      autoSubmit: json['autoSubmit'] as bool? ?? json['auto_submit'] as bool? ?? false,
      allowAnonymous: json['allowAnonymous'] as bool? ?? json['allow_anonymous'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'surveyUid': surveyUid,
      'surveyName': surveyName,
      'description': description,
      'surveyType': surveyType,
      'surveyStatus': surveyStatus,
      'totalTimes': totalTimes,
      'per_user_limit': perUserLimit,
      'project_id': projectId, // 修改为 project_id
      'deadline': deadline,
      'createTime': createTime,
      'updateTime': updateTime,
      'auto_submit': autoSubmit,
      'allow_anonymous': allowAnonymous,
    };
  }
}
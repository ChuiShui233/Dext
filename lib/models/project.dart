class Project {
  final int id;
  final String projectName;
  final String projectDescription;
  final String userId;
  final String createBy;
  final String createTime;
  final String updateTime;
  final String updateBy;

  Project({
    required this.id,
    required this.projectName,
    required this.projectDescription,
    required this.userId,
    required this.createBy,
    required this.createTime,
    required this.updateTime,
    required this.updateBy,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as int,
      projectName: json['projectName'] as String,
      projectDescription: json['projectDescription'] as String,
      userId: json['userId'] as String,
      createBy: json['createBy'] as String,
      createTime: json['createTime'] as String,
      updateTime: json['updateTime'] as String,
      updateBy: json['updateBy'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectName': projectName,
      'projectDescription': projectDescription,
      'userId': userId,
      'createBy': createBy,
      'createTime': createTime,
      'updateTime': updateTime,
      'updateBy': updateBy,
    };
  }

  Project copyWith({
    int? id,
    String? projectName,
    String? projectDescription,
    String? userId,
    String? createBy,
    String? createTime,
    String? updateTime,
    String? updateBy,
  }) {
    return Project(
      id: id ?? this.id,
      projectName: projectName ?? this.projectName,
      projectDescription: projectDescription ?? this.projectDescription,
      userId: userId ?? this.userId,
      createBy: createBy ?? this.createBy,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
      updateBy: updateBy ?? this.updateBy,
    );
  }
} 
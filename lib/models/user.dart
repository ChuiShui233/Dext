// 用户结构体 - 参考Java端完善字段
class User {
  final String id;                  // 用户ID
  final String username;            // 昵称
  final String? password;           // 密码（注册时使用）
  final String userAccount;         // 登录账号
  final String? avatarUrl;          // 头像(可选)
  final int gender;                 // 性别 0-男 1-女
  final String email;               // 邮箱
  final int userStatus;             // 用户状态 0-正常
  final int userRole;               // 用户角色 0-普通用户
  final String createdAt;           // 创建时间
  final String updatedAt;           // 更新时间
  final int isDelete;               // 逻辑删除 0-未删除

  User({
    required this.id,
    required this.username,
    this.password,
    required this.userAccount,
    this.avatarUrl,
    required this.gender,
    required this.email,
    required this.userStatus,
    required this.userRole,
    required this.createdAt,
    required this.updatedAt,
    required this.isDelete,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString(),
      userAccount: json['userAccount']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString(),
      gender: json['gender'] as int? ?? 0,
      email: json['email']?.toString() ?? '',
      userStatus: json['userStatus'] as int? ?? 0,
      userRole: json['userRole'] as int? ?? 0,
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      isDelete: json['isDelete'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'username': username,
      'userAccount': userAccount,
      'gender': gender,
      'email': email,
      'userStatus': userStatus,
      'userRole': userRole,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isDelete': isDelete,
    };

    // 可选字段处理
    if (password != null) {
      json['password'] = password;
    }
    if (avatarUrl != null) {
      json['avatarUrl'] = avatarUrl;
    }

    return json;
  }

  User copyWith({
    String? id,
    String? username,
    String? password,
    String? userAccount,
    String? avatarUrl,
    int? gender,
    String? email,
    int? userStatus,
    int? userRole,
    String? createdAt,
    String? updatedAt,
    int? isDelete,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      userAccount: userAccount ?? this.userAccount,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
      email: email ?? this.email,
      userStatus: userStatus ?? this.userStatus,
      userRole: userRole ?? this.userRole,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDelete: isDelete ?? this.isDelete,
    );
  }
}
class CaptchaSession {
  final String token;
  final String originalImageBase64;
  final String jigsawImageBase64;
  final String secretKey;
  final DateTime createdAt;
  final DateTime expiresAt;

  CaptchaSession({
    required this.token,
    required this.originalImageBase64,
    required this.jigsawImageBase64,
    required this.secretKey,
    required this.createdAt,
    required this.expiresAt,
  });

  factory CaptchaSession.fromJson(Map<String, dynamic> json) {
    return CaptchaSession(
      token: json['token'] as String? ?? '',
      originalImageBase64: json['originalImageBase64'] as String? ?? '',
      jigsawImageBase64: json['jigsawImageBase64'] as String? ?? '',
      secretKey: json['secretKey'] as String? ?? '',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'originalImageBase64': originalImageBase64,
      'jigsawImageBase64': jigsawImageBase64,
      'secretKey': secretKey,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }
}

class CaptchaVerifyRequest {
  final String token;
  final String pointJson;
  final String captchaType;

  CaptchaVerifyRequest({
    required this.token,
    required this.pointJson,
    required this.captchaType,
  });

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'pointJson': pointJson,
      'captchaType': captchaType,
    };
  }
}

class CaptchaVerifyResponse {
  final bool success;
  final String message;

  CaptchaVerifyResponse({
    required this.success,
    required this.message,
  });

  factory CaptchaVerifyResponse.fromJson(Map<String, dynamic> json) {
    return CaptchaVerifyResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '验证失败',
    );
  }
}

// 点击文字验证码模型
class ClickWordCaptchaSession {
  final String token;
  final String originalImageBase64;
  final List<ClickWordPoint> wordList;
  final DateTime createdAt;
  final DateTime expiresAt;

  ClickWordCaptchaSession({
    required this.token,
    required this.originalImageBase64,
    required this.wordList,
    required this.createdAt,
    required this.expiresAt,
  });

  factory ClickWordCaptchaSession.fromJson(Map<String, dynamic> json) {
    List<ClickWordPoint> words = [];
    if (json['wordList'] != null) {
      words = (json['wordList'] as List)
          .map((item) => ClickWordPoint.fromJson(item))
          .toList();
    }

    return ClickWordCaptchaSession(
      token: json['token'] as String? ?? '',
      originalImageBase64: json['originalImageBase64'] as String? ?? '',
      wordList: words,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
  }
}

class ClickWordPoint {
  final String word;
  final int x;
  final int y;

  ClickWordPoint({
    required this.word,
    required this.x,
    required this.y,
  });

  factory ClickWordPoint.fromJson(Map<String, dynamic> json) {
    return ClickWordPoint(
      word: json['word'] as String? ?? '',
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'x': x,
      'y': y,
    };
  }
} 
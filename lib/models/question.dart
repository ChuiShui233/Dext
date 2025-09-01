enum QuestionType {
  singleChoice,    // 单选题
  multipleChoice,  // 多选题
  slider,         // 滑块题
  matrix,         // 矩阵题
}

class Question {
  final int id;
  final String title;
  final QuestionType type;
  final List<QuestionOption> options;
  final List<String> mediaUrls;  // 媒体文件URL列表
  final Map<int, int> jumpLogic; // 跳题逻辑，key为选项ID，value为目标问题ID
  final bool required;           // 是否必答
  final int order;              // 问题顺序

  Question({
    required this.id,
    required this.title,
    required this.type,
    required this.options,
    this.mediaUrls = const [],
    this.jumpLogic = const {},
    this.required = true,
    required this.order,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] ?? 0,
      title: json['title'] ?? json['questionDescription'] ?? '',
      type: _parseQuestionType(json['questionType'] ?? json['type'] ?? 1),
      options: (json['options'] as List?)
          ?.map((o) => QuestionOption.fromJson(o))
          .toList() ?? [],
      mediaUrls: List<String>.from(json['mediaURLs'] ?? []),
      jumpLogic: Map<int, int>.from(json['jumpLogic'] ?? {}),
      required: json['required'] ?? true,
      order: json['order'] ?? 0,
    );
  }

  // 解析问题类型
  static QuestionType _parseQuestionType(dynamic type) {
    if (type is int) {
      switch (type) {
        case 1:
          return QuestionType.singleChoice;
        case 2:
          return QuestionType.multipleChoice;
        case 3:
          return QuestionType.slider;
        case 4:
          return QuestionType.matrix;
        default:
          return QuestionType.singleChoice;
      }
    } else if (type is String) {
      switch (type.toLowerCase()) {
        case 'singlechoice':
          return QuestionType.singleChoice;
        case 'multiplechoice':
          return QuestionType.multipleChoice;
        case 'slider':
          return QuestionType.slider;
        case 'matrix':
          return QuestionType.matrix;
        default:
          return QuestionType.singleChoice;
      }
    }
    return QuestionType.singleChoice;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type.toString().split('.').last,
      'options': options.map((o) => o.toJson()).toList(),
      'mediaUrls': mediaUrls,
      'jumpLogic': jumpLogic,
      'required': required,
      'order': order,
    };
  }

  Question copyWith({
    int? id,
    String? title,
    QuestionType? type,
    List<QuestionOption>? options,
    List<String>? mediaUrls,
    Map<int, int>? jumpLogic,
    bool? required,
    int? order,
  }) {
    return Question(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      options: options ?? this.options,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      jumpLogic: jumpLogic ?? this.jumpLogic,
      required: required ?? this.required,
      order: order ?? this.order,
    );
  }
}

class QuestionOption {
  final int id;
  final String text;
  final String? mediaUrl;  // 选项的媒体文件URL

  QuestionOption({
    required this.id,
    required this.text,
    this.mediaUrl,
  });

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      id: json['id'] ?? 0,
      text: json['text'] ?? json['optionText'] ?? '',
      mediaUrl: json['mediaURL'] ?? json['mediaUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'mediaUrl': mediaUrl,
    };
  }

  QuestionOption copyWith({
    int? id,
    String? text,
    String? mediaUrl,
  }) {
    return QuestionOption(
      id: id ?? this.id,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
    );
  }
} 
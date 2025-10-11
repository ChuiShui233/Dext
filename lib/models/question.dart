import 'dart:convert';

enum QuestionType {
  singleChoice,    // 单选题
  multipleChoice,  // 多选题
  slider,          // 滑块题
  textInput,       // 填写题
}

class Question {
  final int id;
  final String title;
  final QuestionType type;
  final List<QuestionOption> options;
  final List<String> mediaUrls;  // 媒体文件URL列表
  final Map<int, int> jumpLogic; // 跳题逻辑，key为选项ID，value为目标问题ID
  final bool required;           // 是否必答
  final int order;               // 问题顺序
  final double imageScale;       // 图片显示比例 (0.5-2.0)

  Question({
    required this.id,
    required this.title,
    required this.type,
    required this.options,
    this.mediaUrls = const [],
    this.jumpLogic = const {},
    this.required = true,
    required this.order,
    this.imageScale = 1.0,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final title = json['title'] ?? json['questionDescription'] ?? '';
    final safeTitle = (title is String && title.trim().isEmpty)
        ? '未命名问题'
        : title == null
            ? '未命名问题'
            : title.toString();

    // 兼容多种 jumpLogic 结构的解析（字符串或数字作为键）
    Map<int, int> parsedJumpLogic = {};
    final jl = json['jumpLogic'];
    if (jl is Map) {
      jl.forEach((k, v) {
        try {
          final keyInt = k is int ? k : int.parse(k.toString());
          final valInt = v is int ? v : int.parse(v.toString());
          parsedJumpLogic[keyInt] = valInt;
        } catch (_) {
          // 忽略无法解析的键值对
        }
      });
    }

    return Question(
      id: json['id'] ?? 0,
      title: safeTitle,
      type: _parseQuestionType(json['questionType'] ?? json['type'] ?? 1),
      options: (json['options'] as List?)
              ?.map((o) => QuestionOption.fromJson(o))
              .toList() ??
          [],
      mediaUrls: List<String>.from(json['mediaURLs'] ?? json['mediaUrls'] ?? []),
      jumpLogic: parsedJumpLogic,
      required: json['required'] ?? true,
      order: json['order'] ?? 0,
      imageScale: (json['imageScale'] as num?)?.toDouble() ?? 1.0,
    );
  }

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
          return QuestionType.textInput;
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
        case 'textinput':
          return QuestionType.textInput;
        default:
          return QuestionType.singleChoice;
      }
    }
    return QuestionType.singleChoice;
  }

  // 修改后的 toJson 与后端字段完全匹配
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'questionType': type.index + 1, // 对应后端枚举 (1~4)
      'questionDescription': title,   // 可选
      'options': options.map((o) => o.toJson()).toList(),
      'mediaURLs': mediaUrls,
      // JSON 仅支持字符串键，这里将 int 键转换为字符串
      'jumpLogic': { for (final e in jumpLogic.entries) e.key.toString(): e.value },
      'required': required,
      'order': order,
      'imageScale': imageScale,
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
    double? imageScale,
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
      imageScale: imageScale ?? this.imageScale,
    );
  }

  // ---------------- Rating (Slider) Helpers ----------------
  // 对于评级题（原滑块题，QuestionType.slider），我们把配置编码在 options 前 10 项里。
  // 若缺失则提供安全的默认值，保证老数据兼容。
  double get ratingMin {
    if (type != QuestionType.slider || options.isEmpty) return 0.0;
    return double.tryParse(options.elementAt(0).text) ?? 0.0;
  }

  double get ratingMax {
    if (type != QuestionType.slider || options.length < 2) return 100.0;
    return double.tryParse(options.elementAt(1).text) ?? 100.0;
  }

  double get ratingInitial {
    if (type != QuestionType.slider || options.length < 3) return 50.0;
    return double.tryParse(options.elementAt(2).text) ?? 50.0;
  }

  String get ratingMinLabel {
    if (type != QuestionType.slider || options.length < 4) return '最小值';
    final t = options.elementAt(3).text;
    return t.isNotEmpty ? t : '最小值';
  }

  String get ratingMaxLabel {
    if (type != QuestionType.slider || options.length < 5) return '最大值';
    final t = options.elementAt(4).text;
    return t.isNotEmpty ? t : '最大值';
  }

  String get ratingMidLabel {
    if (type != QuestionType.slider || options.length < 6) return '一般';
    final t = options.elementAt(5).text;
    return t.isNotEmpty ? t : '一般';
  }

  String get ratingStyle {
    if (type != QuestionType.slider || options.length < 7) return 'star';
    final t = options.elementAt(6).text;
    return (t == 'crumb' || t == 'star') ? t : 'star';
  }

  String get ratingIcon {
    if (type != QuestionType.slider || options.length < 8) return 'star';
    final t = options.elementAt(7).text;
    return t.isNotEmpty ? t : 'star';
  }

  bool get ratingAllowHalf {
    if (type != QuestionType.slider || options.length < 9) return true;
    return options.elementAt(8).text.toLowerCase() == 'true';
  }

  int get ratingStars {
    if (type != QuestionType.slider || options.length < 10) return 5;
    final n = int.tryParse(options.elementAt(9).text) ?? 5;
    if (n < 1) return 1;
    if (n > 10) return 10;
    return n;
  }

  // 自定义评级标签映射（key: 分值字符串，如 "0.5","1","2.5"；value: 标签）
  Map<double, String> get ratingLabels {
    if (type != QuestionType.slider || options.length < 11) return const {};
    final raw = options.elementAt(10).text;
    if (raw.isEmpty) return const {};
    try {
      final Map<String, dynamic> m = json.decode(raw);
      final Map<double, String> out = {};
      for (final entry in m.entries) {
        final k = double.tryParse(entry.key);
        final v = entry.value?.toString() ?? '';
        if (k != null && v.isNotEmpty) out[k] = v;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }
}

class QuestionOption {
  final int id;
  final String text;
  final String? mediaUrl; // 选项的媒体文件URL
  final int? destination; // 跳题目标问题ID（可为空）

  QuestionOption({
    required this.id,
    required this.text,
    this.mediaUrl,
    this.destination,
  });

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    final text = json['text'] ?? json['optionText'] ?? '';
    final safeText = (text is String && text.trim().isEmpty)
        ? '未命名选项'
        : (text == null)
            ? '未命名选项'
            : text.toString().trim().isEmpty
                ? '未命名选项'
                : text.toString();

    return QuestionOption(
      id: json['id'] ?? 0,
      text: safeText,
      mediaUrl: json['mediaURL'] ?? json['mediaUrl'] ?? json['mediaURL'],
      // 支持多种字段名：destination, destinationQuestionId, destination_question_id
      destination: (json['destination'] ?? json['destinationQuestionId'] ?? json['destination_question_id']) as int?,
    );
  }

  // 修改后的 toJson 与后端字段完全匹配
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'optionText': text,       // 后端需要的字段
      'mediaURL': mediaUrl,
      if (destination != null) 'destination': destination,
    };
  }

  QuestionOption copyWith({
    int? id,
    String? text,
    String? mediaUrl,
    int? destination,
  }) {
    return QuestionOption(
      id: id ?? this.id,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      destination: destination ?? this.destination,
    );
  }
}

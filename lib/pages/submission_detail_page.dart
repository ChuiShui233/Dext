import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../components/glass_card.dart';
import '../widgets/question_display_widget.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import 'fullscreen_media_viewer.dart';

class SubmissionDetailPage extends StatefulWidget {
  final ApiService apiService;
  final int answerId;
  const SubmissionDetailPage({super.key, required this.apiService, required this.answerId});

  @override
  State<SubmissionDetailPage> createState() => _SubmissionDetailPageState();
}

class _SubmissionDetailPageState extends State<SubmissionDetailPage> {
  bool _loading = true;
  String? _error;
  late Map<String, dynamic> _data;
  final Map<String, bool> _optionStates = {}; // 与 public_survey_page 一致的选项状态键

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final d = await widget.apiService.getSubmissionDetail(widget.answerId);
      // 初始化只读选中状态
      final questions = (d['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final myAnswers = (d['myAnswers'] as Map?)?.map((k, v) => MapEntry(int.parse(k.toString()), (v as List).cast<String>())) ?? <int, List<String>>{};
      final myAnswerIndices = (d['myAnswerIndices'] as Map?)?.map((k, v) => MapEntry(int.parse(k.toString()), (v as List).map((e) => (e as num).toInt()).toList())) ?? <int, List<int>>{};

      for (final q in questions) {
        final qid = (q['id'] ?? 0) as int;
        final opts = (q['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        // 首选：后端提供的精确下标（可处理相同文本选项）
        if (myAnswerIndices.containsKey(qid)) {
          final idxList = myAnswerIndices[qid]!;
          for (int i = 0; i < opts.length; i++) {
            _optionStates[_getOptionKey(qid, i)] = idxList.contains(i);
          }
          continue;
        }
        // 兼容回退：基于文本的多重计数（避免全部命中同名）
        final mine = List<String>.from(myAnswers[qid] ?? const <String>[]);
        final Map<String, int> counts = {};
        for (final t in mine) {
          counts[t] = (counts[t] ?? 0) + 1;
        }
        for (int i = 0; i < opts.length; i++) {
          final text = (opts[i]['text'] ?? '') as String;
          final key = _getOptionKey(qid, i);
          final c = counts[text] ?? 0;
          if (c > 0) {
            _optionStates[key] = true;
            counts[text] = c - 1;
          } else {
            _optionStates[key] = false;
          }
        }
      }
      setState(() { _data = d; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = '加载失败: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          // 背景（轻量渐变，避免重图）
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [Colors.grey[900]!, Colors.grey[800]!]
                      : [Colors.blue[50]!, Colors.indigo[100]!],
                ),
              ),
              child: isDark ? Container(color: Colors.black.withValues(alpha: 0.35)) : null,
            ),
          ),
          Column(
            children: [
              SizedBox(height: isDesktop ? 38 : 24),
              FHeader.nested(
                title: Text('提交详情'),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.chevron_left, size: 32),
                    onPress: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _buildError(_error!)
                        : _buildContent(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError(String err) {
    return Center(
      child: _glass(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(err, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FButton(onPress: _load, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final questions = (_data['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final myAnswers = (_data['myAnswers'] as Map?)?.map((k, v) => MapEntry(int.parse(k.toString()), (v as List).cast<String>())) ?? <int, List<String>>{};
    final surveyName = (_data['surveyName'] ?? '') as String;
    final creator = (_data['creator'] ?? '') as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _glass(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(surveyName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    _kv('创建人', creator),
                    _kv('答卷ID', widget.answerId.toString()),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...questions.map((q) => _buildQuestionCard(q, myAnswers[q['id'] as int] ?? const <String>[])),
      ],
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> q, List<String> my) {
    // 将Map数据转换为Question对象
    final question = _mapToQuestion(q);
    
    return _glass(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: QuestionDisplayWidget(
          question: question,
          mode: QuestionDisplayMode.readonly,
          optionStates: _optionStates,
          selectedAnswers: my,
          onMediaOpen: (url, all, index) => _openFullscreenViewer(url, all, index),
        ),
      ),
    );
  }

  // 将Map数据转换为Question对象的辅助方法
  Question _mapToQuestion(Map<String, dynamic> q) {
    final options = (q['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final mediaUrls = (q['mediaUrls'] as List?)?.cast<String>() ?? const <String>[];
    final int qType = (q['questionType'] ?? 1) as int;

    // 解析选项
    List<QuestionOption> questionOptions = [];
    try {
      questionOptions = options.asMap().entries.map((entry) => QuestionOption(
        id: entry.key,
        text: (entry.value['text'] ?? '') as String,
        mediaUrl: (entry.value['mediaUrl'] ?? '') as String,
      )).toList();
    } catch (e) {
      // 解析失败时使用空列表
    }

    // 解析问题类型
    QuestionType questionType;
    switch (qType) {
      case 1:
        questionType = QuestionType.singleChoice;
        break;
      case 2:
        questionType = QuestionType.multipleChoice;
        break;
      case 3:
        questionType = QuestionType.slider;
        break;
      case 4:
        questionType = QuestionType.matrix;
        break;
      default:
        questionType = QuestionType.singleChoice;
    }

    return Question(
      id: (q['id'] ?? 0) as int,
      title: (q['title'] ?? '') as String,
      type: questionType,
      options: questionOptions,
      required: (q['required'] ?? false) as bool,
      order: (q['order'] ?? 0) as int,
      mediaUrls: mediaUrls,
    );
  }



  // 兼容旧调用
  Widget _glass({required Widget child}) => GlassCard(child: child);

  // 打开全屏媒体查看器
  void _openFullscreenViewer(String mediaUrl, List<String> allMediaUrls, int currentIndex) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false, // 允许下层页面透出
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) => FullscreenMediaViewer(
          mediaUrl: mediaUrl,
          title: '问卷媒体',
          allMediaUrls: allMediaUrls,
          currentIndex: currentIndex,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  // 小键值对展示
  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v),
      ],
    );
  }

  // 与 public_survey_page 一致的选项键
  String _getOptionKey(int questionId, int optionIndex) {
    return 'q${questionId}_opt$optionIndex';
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../widgets/top_safe_spacer.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../controllers/survey_runtime.dart';
import '../components/glass_card.dart';
import '../widgets/question_display_widget.dart';
import 'fullscreen_media_viewer.dart';
import '../widgets/frosted_glass_background.dart';

class SurveyPreviewPage extends StatefulWidget {
  final Survey survey;
  final String token;
  final List<Question> questions;

  const SurveyPreviewPage({
    super.key,
    required this.survey,
    required this.token,
    required this.questions,
  });

  @override
  State<SurveyPreviewPage> createState() => _SurveyPreviewPageState();
}

class _SurveyPreviewPageState extends State<SurveyPreviewPage> {
  late final ApiService _apiService;
  String? _desktopBackground;
  String? _mobileBackground;
  // 共享控制器
  late final SurveyRuntimeController _runtime;
  // 选项状态：按题目+索引管理，避免相同文本冲突
  final Map<String, bool> _optionStates = {};
  // 悬停评分值（按题目ID记录），用于展示 Hover 标签
  final Map<int, double?> _hoverRatings = {};

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadBackground();
    // 初始化共享控制器（默认 first 策略）并计算可见题
    _runtime = SurveyRuntimeController(
      questions: widget.questions,
      multiJumpStrategy: MultiJumpStrategy.first,
    );
    _runtime.recomputeVisible();
  }

  Future<void> _loadBackground() async {
    try {
      final backgroundData =
          await _apiService.getSurveyBackground(widget.survey.id);
      setState(() {
        _desktopBackground = backgroundData['desktopBackground'] as String?;
        _mobileBackground = backgroundData['mobileBackground'] as String?;
      });
    } catch (e) {
      debugPrint('获取问卷背景失败: $e');
      setState(() {
        _desktopBackground = null;
        _mobileBackground = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // 背景层
          Positioned.fill(
            child: (_desktopBackground != null && _desktopBackground!.isNotEmpty) ||
                   (_mobileBackground != null && _mobileBackground!.isNotEmpty)
                ? Container(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: NetworkImage(isWide
                            ? (_desktopBackground ?? '')
                            : (_mobileBackground ?? '')),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      ),
                    ),
                    child: isDark
                        ? Container(
                            color: Colors.black.withValues(alpha: 0.4),
                          )
                        : null,
                  )
                : const FrostedGlassBackground(),
          ),

          // 内容层
          Column(
            children: [
              const TopSafeSpacer(),
              FHeader.nested(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('问卷预览 - ${widget.survey.surveyName}'),
                  ],
                ),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.close, size: 20),
                    onPress: () => Navigator.pop(context),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 问卷信息卡片
                    _buildGlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.survey.surveyName,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.survey.description,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 问题列表（仅渲染可见题，且支持点击模拟）
                    ...widget.questions
                        .where((q) => _runtime.visibleQuestionIds.contains(q.id) || _runtime.visibleQuestionIds.isEmpty && q.order == 0)
                        .map((q) => _buildGlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: QuestionDisplayWidget(
                                  question: q,
                                  mode: QuestionDisplayMode.preview,
                                  optionStates: _optionStates,
                                  selectedAnswers: _runtime.answers[q.id] ?? [],
                                  hoverRatings: _hoverRatings,
                                  onSingleChoiceChanged: (questionId, selectedOption, optionIndex) {
                                    // 单选：先清空该题的其他选项状态
                                    for (int i = 0; i < q.options.length; i++) {
                                      _optionStates[_getOptionKey(questionId, i)] = false;
                                    }
                                    // 设置选中的选项状态
                                    _optionStates[_getOptionKey(questionId, optionIndex)] = true;
                                    // 同步 runtime 的文本答案
                                    _runtime.setAnswerSingle(questionId, selectedOption);
                                    _runtime.recomputeVisible();
                                    setState(() {});
                                  },
                                  onMultipleChoiceChanged: (questionId, option, optionIndex, isSelected) {
                                    // 多选：仅切换当前索引
                                    _optionStates[_getOptionKey(questionId, optionIndex)] = !isSelected;
                                    // 将被选中的索引转换为文本
                                    final texts = <String>[];
                                    for (int i = 0; i < q.options.length; i++) {
                                      if (_optionStates[_getOptionKey(questionId, i)] ?? false) {
                                        texts.add(q.options[i].text);
                                      }
                                    }
                                    _runtime.setAnswerMultiple(questionId, texts);
                                    _runtime.recomputeVisible();
                                    setState(() {});
                                  },
                                  onRatingChanged: (questionId, value) {
                                    _runtime.setAnswerSingle(questionId, value);
                                    _runtime.recomputeVisible();
                                    setState(() {});
                                  },
                                  onMediaOpen: (url, all, index) => _openFullscreenViewer(url, all, index),
                                ),
                              ),
                            )),

                    if (_runtime.ended)
                      _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('问卷已结束', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              Text('根据当前选择，问卷在此结束。'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 玻璃卡片封装
  Widget _buildGlassCard({required Widget child}) {
    // 委托到通用 GlassCard 以实现模块化
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      backgroundColor: CupertinoColors.white.withAlpha(51),
      borderColor: CupertinoColors.white.withAlpha(51),
      blurSigma: 12,
      child: child,
    );
  }


  // 打开全屏媒体查看器
  void _openFullscreenViewer(String mediaUrl, List<String> allMediaUrls, int currentIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false, // 允许下层页面透出
        barrierColor: Colors.black54, // 半透明黑色背景
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => FullscreenMediaViewer(
          mediaUrl: mediaUrl,
          title: '问卷媒体',
          allMediaUrls: allMediaUrls,
          currentIndex: currentIndex,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 组合动画：缩放 + 淡入 + 轻微位移
          final scaleAnimation = Tween<double>(
            begin: 0.8,
            end: 1.0,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));

          final fadeAnimation = Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
          ));

          final slideAnimation = Tween<Offset>(
            begin: const Offset(0.0, 0.1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));

          return SlideTransition(
            position: slideAnimation,
            child: ScaleTransition(
              scale: scaleAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }


  // 选项键：题目ID + 索引
  String _getOptionKey(int questionId, int optionIndex) => 'q${questionId}_opt$optionIndex';
}

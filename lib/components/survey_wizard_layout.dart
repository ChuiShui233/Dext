import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:video_player/video_player.dart';

import '../controllers/survey_runtime.dart';
import '../models/question.dart';
import '../widgets/question_display_widget.dart';
import 'glass_card.dart';

/// 问卷 Wizard 布局组件
///
/// 一次只显示一个问题，带上一题/下一题导航与进度指示。
/// 同时支持预览模式（preview）和交互模式（interactive）。
class SurveyWizardLayout extends StatefulWidget {
  final String surveyName;
  final String description;
  final List<Question> questions;
  final SurveyRuntimeController runtime;
  final Map<String, bool> optionStates;
  final Map<int, double?> hoverRatings;
  final String authToken;
  final bool isDark;

  // 显示模式：preview 仅用于预览；interactive 可交互（公开填写页使用）
  final QuestionDisplayMode mode;

  // 自定义填写选项的输入内容
  final Map<String, String> customInputValues;

  final void Function(int questionId, String selectedOption, int optionIndex)?
      onSingleChoiceChanged;
  final void Function(
          int questionId, String option, int optionIndex, bool isSelected)?
      onMultipleChoiceChanged;
  final void Function(int questionId, String value)? onRatingChanged;
  final void Function(int questionId, String value)? onTextInputChanged;
  final void Function(int questionId, int optionIndex, String value)?
      onCustomInputChanged;
  final void Function(String mediaUrl, List<String> allMediaUrls, int currentIndex,
      {VideoPlayerController? controller}) onMediaOpen;

  // 底部插槽（提交按钮等），显示在导航按钮下方
  final Widget? footer;

  const SurveyWizardLayout({
    super.key,
    required this.surveyName,
    required this.description,
    required this.questions,
    required this.runtime,
    required this.optionStates,
    required this.hoverRatings,
    required this.authToken,
    required this.isDark,
    required this.onMediaOpen,
    this.mode = QuestionDisplayMode.preview,
    this.customInputValues = const {},
    this.onSingleChoiceChanged,
    this.onMultipleChoiceChanged,
    this.onRatingChanged,
    this.onTextInputChanged,
    this.onCustomInputChanged,
    this.footer,
  });

  @override
  State<SurveyWizardLayout> createState() => _SurveyWizardLayoutState();
}

class _SurveyWizardLayoutState extends State<SurveyWizardLayout>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  // 导航方向：1 前进，-1 后退，用于过渡动画
  int _direction = 1;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// 当前可见问题列表（按 order 排序）
  List<Question> get _visibleQuestions {
    final visible = widget.questions.where((q) =>
        widget.runtime.visibleQuestionIds.contains(q.id) ||
        (widget.runtime.visibleQuestionIds.isEmpty && q.order == 0));
    final list = visible.toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  void _goNext() {
    final visible = _visibleQuestions;
    if (_currentIndex < visible.length - 1) {
      setState(() {
        _direction = 1;
        _currentIndex++;
      });
      _animController.forward(from: 0);
    }
  }

  void _goPrev() {
    if (_currentIndex > 0) {
      setState(() {
        _direction = -1;
        _currentIndex--;
      });
      _animController.forward(from: 0);
    }
  }

  /// 玻璃卡片封装
  Widget _buildGlassCard({required Widget child}) {
    return GlassCard(
      margin: EdgeInsets.zero,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      backgroundColor: CupertinoColors.white.withAlpha(51),
      borderColor: CupertinoColors.white.withAlpha(51),
      blurSigma: 12,
      child: child,
    );
  }

  Widget _buildProgress(int total) {
    final theme = Theme.of(context);
    final progress = total > 0 ? (_currentIndex + 1) / total : 0.0;
    final primary = theme.colorScheme.primary;
    final secondary = widget.isDark ? Colors.white70 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 文字数字过渡
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                key: ValueKey('progress_text_$_currentIndex'),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset((1 - value) * (_direction > 0 ? 12 : -12), 0),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  '第 ${_currentIndex + 1} / $total 题',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ),
              if (widget.runtime.ended)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '问卷在此结束',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 进度条数值平滑过渡
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: progress),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    // 轨道
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // 填充
                    FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              primary.withValues(alpha: 0.7),
                              primary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.35),
                              blurRadius: 6,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons(int total) {
    final isLast = _currentIndex >= total - 1;
    final isFirst = _currentIndex <= 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 上一题按钮：首题时禁用
          FButton(
            style: context.theme.buttonStyles.ghost.call,
            onPress: isFirst ? null : _goPrev,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_back, size: 16),
                SizedBox(width: 6),
                Text('上一题'),
              ],
            ),
          ),
          // 末题：显示提交按钮（footer）；否则显示下一题按钮
          if (isLast)
            widget.footer ?? const SizedBox.shrink()
          else
            FButton(
              style: context.theme.buttonStyles.primary.call,
              onPress: _goNext,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('下一题'),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleQuestions;
    final total = visible.length;

    // 越界保护：可见问题变化时夹紧索引
    if (_currentIndex >= total) {
      _currentIndex = (total - 1).clamp(0, total > 0 ? total - 1 : 0);
    }

    // 空状态
    if (total == 0 || widget.runtime.ended && _currentIndex >= total) {
      return _buildEndedView();
    }

    final q = visible[_currentIndex.clamp(0, total - 1)];

    final curved = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    final slideAnimation = Tween<Offset>(
      begin: Offset(_direction > 0 ? 0.12 : -0.12, 0),
      end: Offset.zero,
    ).animate(curved);

    return Column(
      children: [
        _buildProgress(total),
        Expanded(
          child: SingleChildScrollView(
            physics:
                const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SlideTransition(
              position: slideAnimation,
              child: FadeTransition(
                opacity: curved,
                child: _buildGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: QuestionDisplayWidget(
                      question: q,
                      mode: widget.mode,
                      optionStates: widget.optionStates,
                      selectedAnswers:
                          widget.runtime.answers[q.id] ?? [],
                      hoverRatings: widget.hoverRatings,
                      authToken: widget.authToken,
                      customInputValues: widget.customInputValues,
                      onSingleChoiceChanged: (questionId, selectedOption,
                          optionIndex) {
                        widget.onSingleChoiceChanged
                            ?.call(questionId, selectedOption, optionIndex);
                      },
                      onMultipleChoiceChanged: (questionId, option,
                          optionIndex, isSelected) {
                        widget.onMultipleChoiceChanged?.call(
                            questionId, option, optionIndex, isSelected);
                      },
                      onRatingChanged: (questionId, value) {
                        widget.onRatingChanged?.call(questionId, value);
                      },
                      onTextInputChanged: (questionId, value) {
                        widget.onTextInputChanged?.call(questionId, value);
                      },
                      onCustomInputChanged: widget.onCustomInputChanged,
                      onMediaOpen: (url, all, index) =>
                          widget.onMediaOpen(url, all, index),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildNavButtons(total),
      ],
    );
  }

  /// 问卷结束视图
  Widget _buildEndedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 56,
                  color: widget.isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(height: 16),
                const Text(
                  '问卷已结束',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '根据当前选择，问卷在此结束。',
                  style: TextStyle(
                    color: widget.isDark ? Colors.white70 : Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FButton(
                  style: context.theme.buttonStyles.ghost.call,
                  onPress: _goPrev,
                  child: const Text('返回上一题'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

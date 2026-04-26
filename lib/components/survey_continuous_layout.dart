import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../controllers/survey_runtime.dart';
import '../models/question.dart';
import '../services/config.dart';
import '../widgets/question_display_widget.dart';
import 'glass_card.dart';

/// 问卷连续布局组件
///
/// 所有可见问题在同一可滚动页面中依次显示（原始布局）。
/// 同时支持预览模式（preview）和交互模式（interactive）。
class SurveyContinuousLayout extends StatelessWidget {
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

  // 作者信息
  final String? authorName;
  final String? authorAvatar;

  // 自定义填写选项的输入内容
  final Map<String, String> customInputValues;

  // 答案变更回调（由宿主页面处理 runtime/optionStates 更新）
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

  // 滚动控制器（可选，公开填写页用于自动滚动到底部）
  final ScrollController? scrollController;

  // 底部插槽（提交按钮等）
  final Widget? footer;

  const SurveyContinuousLayout({
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
    this.authorName,
    this.authorAvatar,
    this.customInputValues = const {},
    this.onSingleChoiceChanged,
    this.onMultipleChoiceChanged,
    this.onRatingChanged,
    this.onTextInputChanged,
    this.onCustomInputChanged,
    this.scrollController,
    this.footer,
  });

  /// 玻璃卡片封装
  Widget _buildGlassCard({required Widget child}) {
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

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      cacheExtent: 800.0,
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                if (description.isNotEmpty)
                  _buildGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (authorName != null &&
                              authorName!.isNotEmpty &&
                              authorAvatar != null &&
                              authorAvatar!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Column(
                                children: [
                                  ClipOval(
                                    child: Image.network(
                                      toAbsoluteUrl(authorAvatar!),
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.person,
                                        size: 36,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    authorName!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  surveyName,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white70 : Colors.black54,
                                  ),
                                ),
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                ],
                                if ((authorAvatar == null ||
                                    authorAvatar!.isEmpty) &&
                                    authorName != null &&
                                    authorName!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.edit,
                                        size: 14,
                                        color: isDark ? Colors.white54 : Colors.black38,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        authorName!,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (description.isNotEmpty) const SizedBox(height: 16),
                ...questions
                    .where((q) =>
                        runtime.visibleQuestionIds.contains(q.id) ||
                        runtime.visibleQuestionIds.isEmpty && q.order == 0)
                    .map((q) => _buildGlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: QuestionDisplayWidget(
                              question: q,
                              mode: mode,
                              optionStates: optionStates,
                              selectedAnswers:
                                  runtime.answers[q.id] ?? [],
                              hoverRatings: hoverRatings,
                              authToken: authToken,
                              customInputValues: customInputValues,
                              onSingleChoiceChanged: (questionId,
                                  selectedOption, optionIndex) {
                                onSingleChoiceChanged?.call(
                                    questionId, selectedOption, optionIndex);
                              },
                              onMultipleChoiceChanged: (questionId, option,
                                  optionIndex, isSelected) {
                                onMultipleChoiceChanged?.call(questionId,
                                    option, optionIndex, isSelected);
                              },
                              onRatingChanged: (questionId, value) {
                                onRatingChanged?.call(questionId, value);
                              },
                              onTextInputChanged: (questionId, value) {
                                onTextInputChanged?.call(questionId, value);
                              },
                              onCustomInputChanged: onCustomInputChanged,
                              onMediaOpen: (url, all, index) =>
                                  onMediaOpen(url, all, index),
                            ),
                          ),
                        )),
                if (runtime.ended)
                  _buildGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('问卷已结束',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 8),
                          Text('根据当前选择，问卷在此结束。'),
                        ],
                      ),
                    ),
                  ),
                if (footer != null) footer!,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

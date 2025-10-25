// file: lib/controllers/survey_runtime.dart

import '../models/question.dart';

/// 多选题跳转策略
/// - first: 采用第一个被选中的选项
/// - last: 采用最后一个被选中的选项
/// - none: 多选不触发跳转（始终顺序下一题）
enum MultiJumpStrategy { first, last, none }

class SurveyRuntimeController {
  final List<Question> questions;
  final MultiJumpStrategy multiJumpStrategy;
  final Map<int, List<String>> answers = {};
  final Set<int> visibleQuestionIds = <int>{};

  bool ended = false;

  SurveyRuntimeController({
    required this.questions,
    this.multiJumpStrategy = MultiJumpStrategy.first,
  });

  void clear() {
    answers.clear();
    visibleQuestionIds.clear();
    ended = false;
  }

  void setAnswerSingle(int questionId, String value) {
    answers[questionId] = [value];
  }

  void setAnswerMultiple(int questionId, List<String> values) {
    answers[questionId] = values;
  }

  void removeAnswerValue(int questionId, String value) {
    final list = answers[questionId];
    if (list == null) return;
    list.remove(value);
    if (list.isEmpty) answers.remove(questionId);
  }

  void toggleMultiple(int questionId, String value, bool isOn) {
    final list = [...(answers[questionId] ?? const <String>[])];
    if (isOn) {
      if (!list.contains(value)) list.add(value);
    } else {
      list.remove(value);
    }
    if (list.isEmpty) {
      answers.remove(questionId);
    } else {
      answers[questionId] = list;
    }
  }

  void recomputeVisible() {
    final ordered = [...questions]..sort((a, b) => a.order.compareTo(b.order));
    visibleQuestionIds.clear();
    ended = false;
    if (ordered.isEmpty) return;

    // questionId -> index
    final Map<int, int> idToIndex = {
      for (int i = 0; i < ordered.length; i++) ordered[i].id: i
    };

    int idx = 0;
    int safety = 0;
    while (idx >= 0 && idx < ordered.length && safety < ordered.length + 5) {
      final q = ordered[idx];
      visibleQuestionIds.add(q.id);

      int? nextIdx;
      final selected = answers[q.id];
      if (selected != null && selected.isNotEmpty) {
        // 只有选择题才处理跳题逻辑
        if (q.options.isNotEmpty) {
          // 选择 pivot 用于跳题
          String pivot = selected.first;
          switch (multiJumpStrategy) {
            case MultiJumpStrategy.last:
              pivot = selected.last;
              break;
            case MultiJumpStrategy.none:
              if (selected.length > 1) pivot = '';
              break;
            case MultiJumpStrategy.first:
              // 已默认 first
              break;
          }

          final opt = q.options.firstWhere(
            (o) => o.text == pivot,
            orElse: () => q.options.first,
          );

          if (opt.destination == -1) {
            ended = true;
            break;
          }
          if (opt.destination != null && idToIndex.containsKey(opt.destination)) {
            nextIdx = idToIndex[opt.destination!];
          }
        }
        // 文本题/评分题已作答，继续下一题
      } else {
        // 未作答：必答题停止，非必答题继续
        if (q.required) {
          break;
        }
      }

      nextIdx ??= idx + 1;
      if (nextIdx == idx) nextIdx = idx + 1; // 防环
      idx = nextIdx;
      safety++;
    }
  }
}

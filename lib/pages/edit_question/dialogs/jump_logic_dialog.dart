import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../../../models/question.dart';

class JumpLogicDialog extends StatefulWidget {
  final int currentQuestionId;
  final List<Question> questions;
  final int currentOptionId;
  final int? currentJumpTo;

  const JumpLogicDialog({
    super.key,
    required this.currentQuestionId,
    required this.questions,
    required this.currentOptionId,
    this.currentJumpTo,
  });

  @override
  State<JumpLogicDialog> createState() => _JumpLogicDialogState();
}

class _JumpLogicDialogState extends State<JumpLogicDialog> {
  int? _selectedQuestionId;

  @override
  void initState() {
    super.initState();
    _selectedQuestionId = widget.currentJumpTo;
  }

  String _getQuestionTypeLabel(QuestionType type) {
    switch (type) {
      case QuestionType.singleChoice: return '单选';
      case QuestionType.multipleChoice: return '多选';
      case QuestionType.slider: return '评级';
      case QuestionType.textInput: return '填写';
    }
  }

  /// 截断过长的文本，避免 UI 溢出
  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    // 找到当前问题的 order
    final currentQuestion = widget.questions.firstWhere(
      (q) => q.id == widget.currentQuestionId,
      orElse: () => widget.questions.first,
    );
    
    // 只显示当前问题之后的问题（order 大于当前问题）
    final availableQuestions = widget.questions
        .where((q) => q.order > currentQuestion.order)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return FDialog(
      direction: Axis.horizontal,
      title: const Text('设置跳题逻辑'),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选择此选项后，跳转到的问题：'),
          const SizedBox(height: 16),
          FSelect<int>(
            hint: '默认（下一题）',
            initialValue: _selectedQuestionId,
            onChange: (value) => setState(() => _selectedQuestionId = value),
            items: {
              for (final q in availableQuestions)
                '第${q.order + 1}题：${_truncateText(q.title, 18)} (${_getQuestionTypeLabel(q.type)})': q.id,
              '结束问卷': -1,
            },
          ),
        ],
      ),
      actions: [
        FButton(
          style: context.theme.buttonStyles.outline.call,
          child: const Text('取消'),
          onPress: () => Navigator.pop(context),
        ),
        FButton(
          child: const Text('确定'),
          onPress: () => Navigator.pop(context, _selectedQuestionId),
        ),
      ],
    );
  }
}

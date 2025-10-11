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

  @override
  Widget build(BuildContext context) {
    final availableQuestions = widget.questions
        .where((q) => q.id != widget.currentQuestionId)
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
            format: (value) {
              if (value == -1) return '结束问卷';
              final idx = availableQuestions.indexWhere((q) => q.id == value);
              if (idx == -1) return '默认（下一题）';
              final question = availableQuestions[idx];
              return '第${question.order + 1}题：${question.title} (${_getQuestionTypeLabel(question.type)})';
            },
            initialValue: _selectedQuestionId,
            onChange: (value) => setState(() => _selectedQuestionId = value),
            children: [
              ...availableQuestions.map((q) => 
                FSelectItem('第${q.order + 1}题：${q.title} (${_getQuestionTypeLabel(q.type)})', q.id)
              ),
              FSelectItem('结束问卷', -1),
            ],
          ),
        ],
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline,
          intrinsicWidth: true,
          child: const Text('取消'),
          onPress: () => Navigator.pop(context),
        ),
        FButton(
          intrinsicWidth: true,
          child: const Text('确定'),
          onPress: () => Navigator.pop(context, _selectedQuestionId),
        ),
      ],
    );
  }
}

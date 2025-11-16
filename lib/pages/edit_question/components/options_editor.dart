import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/question.dart';
import '../../../services/config.dart';
import '../../../components/glass_card.dart';

class OptionsEditor extends StatefulWidget {
  final List<QuestionOption> options;
  final QuestionType selectedType;
  final List<Question> allQuestions;
  final Map<int, int> jumpLogic;
  final int currentQuestionId;
  final Function() onAddOption;
  final Function() onAddCustomOption;
  final Function(QuestionOption) onEditOption;
  final Function(QuestionOption) onDeleteOption;
  final Function(QuestionOption) onSetJumpLogic;
  final Function() onBatchSetJump;

  const OptionsEditor({
    super.key,
    required this.options,
    required this.selectedType,
    required this.allQuestions,
    required this.jumpLogic,
    required this.currentQuestionId,
    required this.onAddOption,
    required this.onAddCustomOption,
    required this.onEditOption,
    required this.onDeleteOption,
    required this.onSetJumpLogic,
    required this.onBatchSetJump,
  });

  @override
  State<OptionsEditor> createState() => _OptionsEditorState();
}

class _OptionsEditorState extends State<OptionsEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('选项列表'),
            Row(children: [
              if (widget.selectedType == QuestionType.singleChoice)
                FButton(
                  style: context.theme.buttonStyles.outline.call,
                  onPress: widget.onBatchSetJump,
                  child: const Text('批量设置跳转'),
                ),
            ]),
          ],
        ),
        const SizedBox(height: 8),
        ...widget.options.map((option) {
          // 计算跳转有效性：-1 表示结束问卷；或目标题存在
          final int? targetId = widget.jumpLogic[option.id];
          final bool hasValidJump = targetId != null && (targetId == -1 || widget.allQuestions.any((q) => q.id == targetId));
          Question? targetQ;
          if (targetId != null && targetId > 0) {
            final idx = widget.allQuestions.indexWhere((q) => q.id == targetId);
            targetQ = idx != -1 ? widget.allQuestions[idx] : null;
          } else {
            targetQ = null;
          }

          return GlassCard(
            margin: const EdgeInsets.only(bottom: 8),
            borderRadius: 12,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.text == '__custom_input__' ? '自定义填写（填写者可输入）' : option.text,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.selectedType == QuestionType.singleChoice && option.text != '__custom_input__')
                            IconButton(
                              tooltip: "设置跳题逻辑",
                              icon: Icon(
                                Icons.call_split,
                                size: 20,
                                color: hasValidJump
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              onPressed: () => widget.onSetJumpLogic(option),
                            ),
                          IconButton(
                            tooltip: "编辑选项",
                            icon: Icon(
                              Icons.edit,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: () => widget.onEditOption(option),
                          ),
                          IconButton(
                            tooltip: "删除选项",
                            icon: Icon(
                              Icons.delete,
                              size: 20,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () => widget.onDeleteOption(option),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (option.text != '__custom_input__' && option.mediaUrl != null && option.mediaUrl!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: toAbsoluteUrl(option.mediaUrl!),
                        height: 80,
                        width: 120,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade200,
                          height: 80,
                          width: 120,
                          child: const Icon(Icons.error, size: 30),
                        ),
                      ),
                    ),
                  ],
                  if (hasValidJump) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        targetId == -1
                            ? '跳转至：结束问卷'
                            : (targetQ != null
                                ? '跳转至：第${targetQ.order + 1}题 ${targetQ.title}'
                                : '跳转：默认（下一题）'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        FButton(
          style: context.theme.buttonStyles.outline.call,
          onPress: widget.onAddOption,
          child: const Text('添加选项'),
        ),
        if (widget.selectedType == QuestionType.singleChoice || widget.selectedType == QuestionType.multipleChoice) ...[
          const SizedBox(height: 8),
          FButton(
            style: context.theme.buttonStyles.outline.call,
            onPress: widget.onAddCustomOption,
            child: const Text('添加自定义填写选项'),
          ),
        ],
      ],
    );
  }
}

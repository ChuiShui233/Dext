import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/question.dart';
import '../../../services/config.dart';

class OptionsEditor extends StatefulWidget {
  final List<QuestionOption> options;
  final QuestionType selectedType;
  final List<Question> allQuestions;
  final Map<int, int> jumpLogic;
  final int currentQuestionId;
  final Function() onAddOption;
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
                  style: FButtonStyle.outline,
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

          return ListTile(
            title: Text(option.text),
            subtitle: ((option.mediaUrl != null && option.mediaUrl!.isNotEmpty) || hasValidJump)
                ? Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (option.mediaUrl != null && option.mediaUrl!.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: toAbsoluteUrl(option.mediaUrl!),
                              height: 100,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              alignment: Alignment.centerLeft,
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey.shade200,
                                height: 100,
                                child: const Icon(Icons.error),
                              ),
                            ),
                          ),
                        if (hasValidJump)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              targetId == -1
                                  ? '跳转至：结束问卷'
                                  : (targetQ != null
                                      ? '跳转至：第${targetQ.order + 1}题 ${targetQ.title}'
                                      : '跳转：默认（下一题）'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.selectedType == QuestionType.singleChoice)
                  IconButton(
                    tooltip: "设置跳题逻辑",
                    icon: Icon(
                      Icons.call_split,
                      color: hasValidJump
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    onPressed: () => widget.onSetJumpLogic(option),
                  ),
                if (widget.selectedType == QuestionType.singleChoice)
                  IconButton(
                    tooltip: "清除跳转",
                    icon: Icon(
                      Icons.clear_all,
                      color: hasValidJump
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    onPressed: hasValidJump
                        ? () {
                            // 这里需要通过回调来处理清除跳转逻辑
                            // 暂时禁用，需要在主页面中实现
                          }
                        : null,
                  ),
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () => widget.onEditOption(option),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => widget.onDeleteOption(option),
                ),
              ],
            ),
          );
        }),
        FButton(
          style: FButtonStyle.outline,
          onPress: widget.onAddOption,
          child: const Text('添加选项'),
        ),
      ],
    );
  }
}

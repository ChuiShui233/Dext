import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class RatingEditor extends StatefulWidget {
  final bool enableRatingLabels;
  final Function(bool) onEnableRatingLabelsChanged;
  final List<TextEditingController> perStarLabelCtrls;
  final TextEditingController minLabelController;
  final TextEditingController midLabelController;
  final TextEditingController maxLabelController;
  final TextEditingController starsCountController;
  final String ratingStyle;
  final String ratingIcon;
  final bool allowHalf;
  final int starsCount;
  final Function(String) onRatingStyleChanged;
  final Function(String) onRatingIconChanged;
  final Function(bool) onAllowHalfChanged;
  final Function(int) onStarsCountChanged;
  final Function(int) onEnsurePerStarLabelCtrls;

  const RatingEditor({
    super.key,
    required this.enableRatingLabels,
    required this.onEnableRatingLabelsChanged,
    required this.perStarLabelCtrls,
    required this.minLabelController,
    required this.midLabelController,
    required this.maxLabelController,
    required this.starsCountController,
    required this.ratingStyle,
    required this.ratingIcon,
    required this.allowHalf,
    required this.starsCount,
    required this.onRatingStyleChanged,
    required this.onRatingIconChanged,
    required this.onAllowHalfChanged,
    required this.onStarsCountChanged,
    required this.onEnsurePerStarLabelCtrls,
  });

  @override
  State<RatingEditor> createState() => _RatingEditorState();
}

class _RatingEditorState extends State<RatingEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 数值区间固定为 0..10，初始值固定为 5（中间），这里移除数值编辑项
        Row(children: [
          Expanded(
            child: FTextFormField(
              label: const Text('左侧标签'),
              hint: '如 不推荐',
              controller: widget.minLabelController,
              onEditingComplete: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FTextFormField(
              label: const Text('中间标签'),
              hint: '如 一般',
              controller: widget.midLabelController,
              onEditingComplete: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FTextFormField(
              label: const Text('右侧标签'),
              hint: '如 强烈推荐',
              controller: widget.maxLabelController,
              onEditingComplete: () => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FSelect<String>(
              label: const Text('表现样式'),
              hint: '选择评级的可视样式',
              initialValue: widget.ratingStyle,
              format: (v) => v == 'star' ? '星星 (建议)' : '面包屑',
              onChange: (v) => widget.onRatingStyleChanged(v ?? 'star'),
              children: [
                FSelectItem('星星 (建议)', 'star'),
                FSelectItem('面包屑', 'crumb'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FSelect<String>(
              label: const Text('图标（星星样式）'),
              hint: '仅当样式为星星时生效',
              initialValue: widget.ratingIcon,
              format: (v) => v,
              onChange: (v) => widget.onRatingIconChanged(v ?? 'star'),
              children: [
                FSelectItem('star', 'star'),
                FSelectItem('favorite', 'favorite'),
                FSelectItem('circle', 'circle'),
                FSelectItem('heart_broken', 'heart_broken'),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FTextFormField(
              label: const Text('星星数量'),
              hint: '1-10，默认 5',
              controller: widget.starsCountController,
              keyboardType: TextInputType.number,
              onEditingComplete: () {
                final n = int.tryParse(widget.starsCountController.text.trim()) ?? widget.starsCount;
                widget.onStarsCountChanged(n.clamp(1, 10));
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FSwitch(
              label: const Text('允许半星'),
              value: widget.allowHalf,
              onChange: widget.onAllowHalfChanged,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        FSwitch(
          label: const Text('启用自定义评级文本'),
          description: const Text('为 0.5 步进的分值定义显示文本；未设置的分值将使用默认数值'),
          value: widget.enableRatingLabels,
          onChange: widget.onEnableRatingLabelsChanged,
        ),
        if (widget.enableRatingLabels) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: widget.allowHalf 
              ? List.generate(widget.starsCount * 2, (i) {
                  final value = (i + 1) * 0.5;
                  final labelText = value % 1 == 0 ? value.toInt().toString() : value.toString();
                  widget.onEnsurePerStarLabelCtrls(widget.starsCount * 2);
                  return SizedBox(
                    width: 220,
                    child: FTextFormField(
                      label: Text('分值 $labelText 文本'),
                      controller: widget.perStarLabelCtrls[i],
                    ),
                  );
                })
              : List.generate(widget.starsCount, (i) {
                  final idx = i + 1;
                  widget.onEnsurePerStarLabelCtrls(widget.starsCount);
                  return SizedBox(
                    width: 220,
                    child: FTextFormField(
                      label: Text('分值 $idx 文本'),
                      controller: widget.perStarLabelCtrls[i],
                    ),
                  );
                }),
          ),
          const SizedBox(height: 4),
          Text(widget.allowHalf 
            ? '说明：根据半星步进(0.5, 1, 1.5...)提供对应的文本输入，留空则使用默认数值。'
            : '说明：根据星星数量(1..N)提供对应的文本输入，留空则使用默认数值。'),
        ],
      ],
    );
  }
}

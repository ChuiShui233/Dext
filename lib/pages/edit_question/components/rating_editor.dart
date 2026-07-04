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
  late FDiscreteSliderController _starsController;

  double _toNormalized(int stars) => (stars - 1) / 9.0;
  int _fromNormalized(double val) => (val * 9).round() + 1;

  @override
  void initState() {
    super.initState();
    _starsController = FDiscreteSliderController(
      selection: FSliderSelection(max: _toNormalized(widget.starsCount)),
    );
  }

  @override
  void didUpdateWidget(covariant RatingEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.starsCount != oldWidget.starsCount) {
      _starsController.selection = FSliderSelection(max: _toNormalized(widget.starsCount));
    }
  }

  @override
  void dispose() {
    _starsController.dispose();
    super.dispose();
  }

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
        // 更现代化的可视控件：SegmentedButton + ChoiceChip
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Text('表现样式'),
                ),
                FSelect<String>(
                  hint: '选择表现样式',
                  initialValue: widget.ratingStyle,
                  items: const {
                    '星星 (Star)': 'star',
                    '条形 (Crumb)': 'crumb',
                  },
                  onChange: (val) {
                    if (val != null) {
                      widget.onRatingStyleChanged(val);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Text('图标（星星样式）'),
                ),
                FSelect<String>(
                  hint: '选择图标样式',
                  initialValue: widget.ratingIcon,
                  items: const {
                    '星星 (Star)': 'star',
                    '心形 (Favorite)': 'favorite',
                    '圆形 (Circle)': 'circle',
                    '破碎的心 (Broken)': 'heart_broken',
                  },
                  onChange: (val) {
                    if (val != null) {
                      widget.onRatingIconChanged(val);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('星星数量'),
                    Text('${widget.starsCount}')
                  ],
                ),
                FSlider(
                  controller: _starsController,
                  marks: List.generate(10, (i) {
                    final val = i + 1;
                    return FSliderMark(
                      value: _toNormalized(val),
                      label: Text('$val'),
                    );
                  }),
                  onChange: (selection) {
                    final n = _fromNormalized(_starsController.selection.offset.max).clamp(1, 10);
                    widget.starsCountController.text = n.toString();
                    widget.onStarsCountChanged(n);
                    setState(() {});
                  },
                ),
              ],
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
            ? '留空则使用默认数值。'
            : '说明：根据星星数量提供对应的文本输入，留空则使用默认数值。'),
        ],
      ],
    );
  }
}

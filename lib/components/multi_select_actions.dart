import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class MultiSelectActions extends StatefulWidget {
  final List<int> selectedIds;
  final Function(List<int>) onSelectionChanged;
  final Function()? onSelectAll;
  final Function()? onClearSelection;
  final List<Widget>? customActions;
  final bool showSelectAll;
  final bool showClearSelection;
  final String? selectAllText;
  final String? clearSelectionText;

  const MultiSelectActions({
    super.key,
    required this.selectedIds,
    required this.onSelectionChanged,
    this.onSelectAll,
    this.onClearSelection,
    this.customActions,
    this.showSelectAll = true,
    this.showClearSelection = true,
    this.selectAllText,
    this.clearSelectionText,
  });

  @override
  State<MultiSelectActions> createState() => _MultiSelectActionsState();
}

class _MultiSelectActionsState extends State<MultiSelectActions> {
  bool _isMultiSelectMode = false;

  @override
  void initState() {
    super.initState();
    _isMultiSelectMode = widget.selectedIds.isNotEmpty;
  }

  @override
  void didUpdateWidget(MultiSelectActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIds.isNotEmpty != oldWidget.selectedIds.isNotEmpty) {
      setState(() {
        _isMultiSelectMode = widget.selectedIds.isNotEmpty;
      });
    }
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        widget.onSelectionChanged([]);
      }
    });
  }

  void _handleSelectAll() {
    if (widget.onSelectAll != null) {
      widget.onSelectAll!();
    }
  }

  void _handleClearSelection() {
    if (widget.onClearSelection != null) {
      widget.onClearSelection!();
    } else {
      widget.onSelectionChanged([]);
    }
    // 清除选择后退出多选模式
    setState(() {
      _isMultiSelectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有选择任何项目，不显示任何内容
    if (widget.selectedIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 46,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 选择状态显示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '已选择 ${widget.selectedIds.length} 项',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            
            // 全选按钮
            if (widget.showSelectAll)
              FButton(
                style: FButtonStyle.ghost,
                onPress: _handleSelectAll,
                child: Text(
                  widget.selectAllText ?? '全选',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            
            // 清除选择按钮
            if (widget.showClearSelection)
              FButton(
                style: FButtonStyle.ghost,
                onPress: _handleClearSelection,
                child: Text(
                  widget.clearSelectionText ?? '清除',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            
            // 自定义操作按钮
            if (widget.customActions != null) ...[
              const SizedBox(width: 8),
              ...widget.customActions!,
            ],
            
            const SizedBox(width: 8),
            
            // 退出多选模式按钮
            FButton(
              style: FButtonStyle.ghost,
              onPress: _toggleMultiSelectMode,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.close,
                    size: 16,
                    color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.white.withValues(alpha: 0.7)
                      : Colors.black.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '退出',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            // 添加尾部间距，提升滑动体验
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

// 多选项目组件
class MultiSelectItem extends StatelessWidget {
  final int id;
  final bool isSelected;
  final Function(int, bool) onSelectionChanged;
  final Widget child;
  final bool enabled;

  const MultiSelectItem({
    super.key,
    required this.id,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 为卡片添加左侧内边距，为多选按钮留出空间
        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: child,
        ),
        if (enabled)
          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => onSelectionChanged(id, !isSelected),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected 
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected 
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: Theme.of(context).colorScheme.onPrimary,
                        )
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
} 
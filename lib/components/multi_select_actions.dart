import 'package:flutter/material.dart';

class MultiSelectActions extends StatefulWidget {
  final List<int> selectedIds;
  final Function(List<int>) onSelectionChanged;
  final Function()? onSelectAll;
  final Function()? onClearSelection;
  final VoidCallback? onExitMultiSelectMode;
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
    this.onExitMultiSelectMode,
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
    if (widget.onExitMultiSelectMode != null) {
      widget.onExitMultiSelectMode!();
    } else {
      setState(() {
        _isMultiSelectMode = !_isMultiSelectMode;
        if (!_isMultiSelectMode) {
          widget.onSelectionChanged([]);
        }
      });
    }
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
    // 清除选择但保持多选模式
  }

  @override
  Widget build(BuildContext context) {
    // 进入多选模式后即显示操作栏，即使当前未选择任何项目
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark 
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 选择状态显示 - 更现代的徽章样式
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withValues(alpha: 0.15),
                    primaryColor.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${widget.selectedIds.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.black87 : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '项已选',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            
            // 全选按钮 - 圆角胶囊样式
            if (widget.showSelectAll)
              _buildModernButton(
                context: context,
                label: widget.selectAllText ?? '全选',
                icon: Icons.done_all,
                onPressed: _handleSelectAll,
              ),
            
            // 清除选择按钮
            if (widget.showClearSelection)
              _buildModernButton(
                context: context,
                label: widget.clearSelectionText ?? '清除',
                icon: Icons.clear_all,
                onPressed: _handleClearSelection,
              ),
            
            // 自定义操作按钮
            if (widget.customActions != null) ...
              widget.customActions!.map((action) => 
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: action,
                ),
              ),
            
            const SizedBox(width: 4),
            
            // 退出多选模式按钮 - 更现代的关闭按钮
            _buildModernButton(
              context: context,
              label: '退出',
              icon: Icons.close_rounded,
              onPressed: _toggleMultiSelectMode,
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool isClose = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isClose
                ? (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05))
                : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: isClose ? null : Border.all(
                color: isDark 
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isDark 
                    ? Colors.white.withValues(alpha: 0.95)
                    : Colors.black.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark 
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.black.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MultiSelectItem extends StatefulWidget {
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
  State<MultiSelectItem> createState() => _MultiSelectItemState();
}

class _MultiSelectItemState extends State<MultiSelectItem> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    
    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(MultiSelectItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [

        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: widget.child,
        ),
        if (widget.enabled)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 60,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelectionChanged(widget.id, !widget.isSelected),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  width: 24,
                  height: 24,
                    decoration: BoxDecoration(
                      color: widget.isSelected 
                        ? primaryColor
                        : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isSelected 
                          ? primaryColor
                          : isDark
                            ? Colors.white
                            : Colors.black.withValues(alpha: 0.25),
                        width: 2,
                      ),
                      boxShadow: widget.isSelected
                        ? [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ]
                        : null,
                    ),
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: widget.isSelected
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: isDark ? Colors.black87 : Colors.white,
                            )
                          : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
} 
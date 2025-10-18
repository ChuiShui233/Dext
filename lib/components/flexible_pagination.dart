import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 通用分页组件：统一三处页面的分页 UI 与逻辑
/// - 使用 FPagination + 信息文本（共 N 条记录，第 P / T 页）
class FlexiblePagination extends StatelessWidget {
  final FPaginationController controller;
  final int currentPage; // 1-based
  final int totalPages; // >= 1
  final int totalItems; // >= 0
  final ValueChanged<int> onPageChange; // 0-based page index from FPagination
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const FlexiblePagination({
    super.key,
    required this.controller,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.onPageChange,
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 800;

    final containerMargin = margin ?? EdgeInsets.only(
      left: 20,
      right: 20,
      bottom: isMobile ? 46 : 20,
      top: 16,
    );
    final containerPadding = padding ?? const EdgeInsets.all(20);

    final decoration = BoxDecoration(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
      ),
    );

    final infoText = Text(
      '共 $totalItems 条记录，第 $currentPage / $totalPages 页',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white70 : Colors.black54,
      ),
    );

    final pager = FPagination(
      controller: controller,
      onChange: onPageChange,
    );

    return Container(
      margin: containerMargin,
      padding: containerPadding,
      decoration: decoration,
      child: isMobile
          ? Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: pager,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: infoText,
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: pager,
                ),
              ],
            ),
    );
  }
}

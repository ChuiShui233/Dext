import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 自适应消息卡片布局组件
/// 
/// 提供响应式布局，根据屏幕尺寸自动调整卡片宽度和内边距
/// 适用于成功/失败/提示等各类消息展示场景
class AdaptiveMessageCard extends StatelessWidget {
  /// 卡片内容
  final Widget child;
  
  /// 外层包装器（可选），用于添加毛玻璃效果等装饰
  /// 如果不提供，将使用默认的 Card 样式
  final Widget Function(Widget child)? cardWrapper;

  const AdaptiveMessageCard({
    super.key,
    required this.child,
    this.cardWrapper,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final vw = size.width;
    final vh = size.height;
    
    // 自适应内边距：根据屏幕尺寸动态计算
    final EdgeInsets adaptivePadding = EdgeInsets.symmetric(
      horizontal: (vw * 0.08).clamp(16.0, 48.0),
      vertical: (vh * 0.04).clamp(12.0, 40.0),
    );
    
    // 响应式宽度因子：不同屏幕尺寸使用不同比例
    final double widthFactor = vw < 380
        ? 0.86
        : (vw < 480
            ? 0.82
            : (vw < 800 ? 0.66 : 0.5));
    
    // 最大宽度限制：避免在大屏上过宽
    final double maxWidth = math.min(520.0, vw * 0.84);
    
    final contentWidget = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: adaptivePadding,
        child: child,
      ),
    );

    // 使用自定义包装器或默认卡片样式
    final wrappedContent = cardWrapper != null
        ? cardWrapper!(contentWidget)
        : Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: contentWidget,
          );

    return Center(
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: wrappedContent,
      ),
    );
  }
}

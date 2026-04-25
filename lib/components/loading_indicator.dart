import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class LoadingIndicator extends StatelessWidget {
  final LoadingSize size;
  final String? message;
  final bool centered;
  final Color? color;

  const LoadingIndicator({
    super.key,
    this.size = LoadingSize.medium,
    this.message,
    this.centered = false,
    this.color,
  });

  /// 大
  const LoadingIndicator.page({
    super.key,
    this.message,
  })  : size = LoadingSize.large,
        centered = true,
        color = null;

  /// 小
  const LoadingIndicator.button({
    super.key,
    this.color,
  })  : size = LoadingSize.small,
        message = null,
        centered = false;

  /// 内联
  const LoadingIndicator.inline({
    super.key,
    this.message,
  })  : size = LoadingSize.small,
        centered = false,
        color = null;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final indicatorColor = color ?? theme.colors.primary;
    
    final double indicatorSize;
    final double strokeWidth;
    
    switch (size) {
      case LoadingSize.small:
        indicatorSize = 16.0;
        strokeWidth = 2.0;
        break;
      case LoadingSize.medium:
        indicatorSize = 24.0;
        strokeWidth = 2.5;
        break;
      case LoadingSize.large:
        indicatorSize = 32.0;
        strokeWidth = 3.0;
        break;
    }

    final indicator = SizedBox(
      width: indicatorSize,
      height: indicatorSize,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
      ),
    );

    Widget content;
    if (message != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              message!,
              style: theme.typography.base.copyWith(
                color: theme.colors.foreground,
              ),
            ),
          ),
        ],
      );
    } else {
      content = indicator;
    }

    if (centered) {
      return Center(child: content);
    }
    return content;
  }
}

enum LoadingSize {
  small,
  medium,
  large,
}

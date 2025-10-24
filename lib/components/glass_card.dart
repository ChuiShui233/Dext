import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final ShapeBorder? shape;
  final double borderRadius;
  final double blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;
  /// 可选覆盖是否启用毛玻璃
  final bool? frosted;

  const GlassCard({
    super.key,
    required this.child,
    this.shape,
    this.borderRadius = 12,
    this.blurSigma = 12,
    this.backgroundColor,
    this.borderColor,
    this.margin,
    this.frosted,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = backgroundColor ?? (isDark 
        ? Colors.black.withAlpha(102) // ~40% 深色模式使用更深的黑色
        : CupertinoColors.white.withAlpha(51)); // ~20% 浅色模式保持原样
    final Color bd = borderColor ?? (isDark
        ? Colors.white.withAlpha(38) // ~15% 深色模式边框稍微淡一些
        : CupertinoColors.white.withAlpha(51));
    final ShapeBorder effectiveShape = shape ?? RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    );

    final bool useFrost = frosted ?? SettingsService().glassCardEnabled;
    late final ShapeBorder paintShape;
    if (effectiveShape is OutlinedBorder) {
      if (useFrost) {
        // 毛玻璃开启：添加边框
        paintShape = effectiveShape.copyWith(side: BorderSide(color: bd, width: 0.8));
      } else {
        // 毛玻璃关闭：显式移除边框
        paintShape = effectiveShape.copyWith(side: BorderSide.none);
      }
    } else {
      paintShape = effectiveShape;
    }

    Widget baseChild;
    
    if (useFrost) {
      // 毛玻璃模式：使用 BackdropFilter
      baseChild = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: ShapeDecoration(
            color: bg,
            shape: paintShape,
            shadows: const [],
          ),
          child: child,
        ),
      );
    } else {
      // 非毛玻璃模式：叠加遮罩提高不透明度
      baseChild = Stack(
        children: [
          // 底层：基础背景
          Positioned.fill(
            child: Container(
              decoration: ShapeDecoration(
                color: bg,
                shape: paintShape,
              ),
            ),
          ),
          // 中层：遮罩层
          Positioned.fill(
            child: Container(
              decoration: ShapeDecoration(
                color: isDark 
                    ? Colors.black.withAlpha(128) // 深色模式叠加黑色遮罩
                    : Colors.white.withAlpha(179), // 浅色模式叠加白色遮罩
                shape: paintShape,
              ),
            ),
          ),
          // 顶层：内容
          child,
        ],
      );
    }

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        shape: effectiveShape,
        clipBehavior: Clip.antiAlias,
        child: baseChild,
      ),
    );
  }
}

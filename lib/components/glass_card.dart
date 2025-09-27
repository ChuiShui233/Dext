import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 通用“玻璃”卡片容器
/// 可在桌面与移动端复用，支持自定义形状与样式
class GlassCard extends StatelessWidget {
  final Widget child;
  final ShapeBorder? shape;
  final double borderRadius;
  final double blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    this.shape,
    this.borderRadius = 12,
    this.blurSigma = 12,
    this.backgroundColor,
    this.borderColor,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = backgroundColor ?? CupertinoColors.white.withAlpha(51); // ~20%
    final Color bd = borderColor ?? CupertinoColors.white.withAlpha(51);
    final ShapeBorder effectiveShape = shape ?? RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    );

    // 若传入的 shape 支持边框（OutlinedBorder），则克隆并附加边框；否则直接使用原 shape
    late final ShapeBorder paintShape;
    if (effectiveShape is OutlinedBorder) {
      paintShape = effectiveShape.copyWith(side: BorderSide(color: bd, width: 0.8));
    } else {
      paintShape = effectiveShape;
    }

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        shape: effectiveShape,
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            decoration: ShapeDecoration(
              color: bg,
              shape: paintShape,
              shadows: const [],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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

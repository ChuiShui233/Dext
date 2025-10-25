import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../widgets/downscaled_blur.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final ShapeBorder? shape;
  final double borderRadius;
  final double blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;
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
        ? Colors.black.withAlpha(102)
        : CupertinoColors.white.withAlpha(51));
    final Color bd = borderColor ?? (isDark
        ? Colors.white.withAlpha(38)
        : CupertinoColors.white.withAlpha(51));
    final ShapeBorder effectiveShape = shape ?? RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    );

    final bool useFrost = frosted ?? SettingsService().glassCardEnabled;
    late final ShapeBorder paintShape;
    if (effectiveShape is OutlinedBorder) {
      if (useFrost) {
        paintShape = effectiveShape.copyWith(side: BorderSide(color: bd, width: 0.8));
      } else {
        paintShape = effectiveShape.copyWith(side: BorderSide.none);
      }
    } else {
      paintShape = effectiveShape;
    }

    Widget baseChild;
    
    if (useFrost) {
      baseChild = DownscaledBackdropBlur(
        sigma: blurSigma,
        downscale: 0.3,
        clipRadius: effectiveShape is RoundedRectangleBorder 
            ? effectiveShape.borderRadius.resolve(TextDirection.ltr)
            : null,
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
      baseChild = Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: ShapeDecoration(
                color: bg,
                shape: paintShape,
              ),
            ),
          ),
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

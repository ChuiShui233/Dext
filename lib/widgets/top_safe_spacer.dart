import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../main.dart' show isDesktop;

class TopSafeSpacer extends StatelessWidget {
  final double desktop;
  final double web;
  final double mobile;
  final bool enableBlur;
  final double blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool showBackground;

  const TopSafeSpacer({
    super.key,
    this.desktop = 40,
    this.web = 20,
    this.mobile = 0,
    this.enableBlur = true,
    this.blurSigma = 12,
    this.backgroundColor,
    this.borderColor,
    this.showBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final double height = isDesktop ? desktop : (kIsWeb ? web : mobile);
    
    if (!enableBlur || height == 0 || !showBackground) {
      return SizedBox(height: height);
    }
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = backgroundColor ?? (isDark 
        ? Colors.black.withAlpha(102) 
        : Colors.white.withAlpha(102)); // 浅色主题下调暗
    
    // 使用纯色背景，避免渐变和模糊效果
    return Container(
      height: height,
      color: bg.withAlpha(120), // 使用适中的不透明度
    );
  }
}

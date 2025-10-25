import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 半透明毛玻璃风格按钮（Material Design + Blur）
class GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? color;

  const GlassButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = color ?? Colors.blue;
    final bg = base.withValues(alpha: isDark ? 0.22 : 0.18);
    final fg = Colors.white;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: bg,
              ),
            ),

            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.22),
                    width: 0.9,
                  ),
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                splashColor: base.withValues(alpha: 0.2),
                highlightColor: base.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Center(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

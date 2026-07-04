import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A reusable glass-style sidebar card container used for the mobile sidebar.
///
/// Features:
/// - Backdrop blur with subtle tint and gradient
/// - Rounded corners and thin border
/// - Optional shadow
/// - Adaptive colors for light/dark themes
class GlassSidebarCard extends StatelessWidget {
  final double width;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double blurSigma;
  final Widget child;
  final bool showShadow;

  const GlassSidebarCard({
    super.key,
    required this.width,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    this.borderRadius = 16,
    this.blurSigma = 20,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Base surface with slight opacity
    final Color surface = theme.colorScheme.surface.withValues(alpha: isDark ? 0.55 : 0.65);
    final Color border = (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.12 : 0.08);

    return Container(
      width: width,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            // Backdrop blur
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: const SizedBox.shrink(),
              ),
            ),
            // Tinted glass layer with subtle diagonal gradient
            Container(
              decoration: BoxDecoration(
                color: surface,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    surface.withValues(alpha: 0.9),
                    surface.withValues(alpha: 0.7),
                  ],
                ),
                border: Border.all(color: border, width: 1),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
              padding: padding,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/widgets.dart';

/// DownscaledBlur
///
/// Renders [child] at a lower resolution (by [downscale]) to greatly reduce
/// the cost of gaussian blur, then scales back up to original size.
///
/// - downscale: 0.25~1.0. Smaller = better performance, softer result.
/// - sigma: gaussian blur sigma to apply at the downscaled resolution.
/// - clipRadius: optional rounded clipping applied after blur (hard edge).
/// - opacity: optional opacity for this layer.
class DownscaledBlur extends StatelessWidget {
  final Widget child;
  final double sigma;
  final double downscale; // e.g. 0.5 means render at 50% then scale back
  final BorderRadius? clipRadius;
  final double? opacity;
  final FilterQuality filterQuality;

  const DownscaledBlur({
    super.key,
    required this.child,
    required this.sigma,
    this.downscale = 0.4,
    this.clipRadius,
    this.opacity,
    this.filterQuality = FilterQuality.low,
  }) : assert(downscale > 0 && downscale <= 1.0);

  @override
  Widget build(BuildContext context) {
    Widget content = child;

    // Render child smaller to reduce pixel cost for blur
    content = Transform.scale(
      scale: downscale,
      alignment: Alignment.center,
      child: content,
    );

    // Apply blur on downscaled content
    content = ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: content,
    );

    // Restore to original logical size
    content = Transform.scale(
      scale: 1.0 / downscale,
      alignment: Alignment.center,
      child: content,
    );

    // Optional rounded clipping at the end (hard edge avoids glow seams)
    if (clipRadius != null) {
      content = ClipRRect(
        borderRadius: clipRadius!,
        clipBehavior: Clip.hardEdge,
        child: content,
      );
    }

    // Optional opacity
    if (opacity != null) {
      content = Opacity(opacity: opacity!.clamp(0.0, 1.0), child: content);
    }

    return RepaintBoundary(
      // Help isolate render cost
      child: content,
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted glass style gradient background with multiple random polygon blobs
/// overlaid by a heavy BackdropFilter blur to achieve a frosted/"毛玻璃" effect.
///
/// Cross-platform (Mobile/Desktop/Web) without relying on CSS; mimics
/// `background + backdrop-filter: blur()` from the web reference.
class FrostedGlassBackground extends StatelessWidget {
  /// Number of gradient blobs to paint.
  final int count;

  /// Blur intensity for the frosted overlay.
  final double blurSigma;

  /// Opacity of each blob.
  final double blobOpacity;

  /// Whether to enable subtle animation on blobs.
  final bool animated;

  /// Color palette to sample for blob gradients.
  final List<Color> palette;

  /// Optional seed to make the layout deterministic.
  final int? seed;

  /// Optional: places a very subtle dark/bright vignette gradient on top to
  /// improve contrast for foreground content.
  final bool vignette;

  const FrostedGlassBackground({
    super.key,
    this.count = 8,
    this.blurSigma = 80,
    this.blobOpacity = 0.55,
    this.animated = true,
    this.seed,
    this.vignette = true,
    this.palette = const [
      Color(0xFFF44336),
      Color(0xFFE91E63),
      Color(0xFF9C27B0),
      Color(0xFF673AB7),
      Color(0xFF3F51B5),
      Color(0xFF60569E),
      Color(0xFFE6437D),
      Color(0xFFEBBF4D),
      Color(0xFF00BCD4),
      Color(0xFF03A9F4),
      Color(0xFF2196F3),
      Color(0xFF009688),
      Color(0xFF5EE463),
      Color(0xFFF8E645),
      Color(0xFFFFC107),
      Color(0xFFFF5722),
      Color(0xFF43F8BF),
    ],
  });

  @override
  Widget build(BuildContext context) {

    return IgnorePointer(
      child: Stack(
        children: [
          // Colorful polygon blobs (behind)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final blobs = List.generate(count, (i) {
                  final localRand = math.Random((seed ?? 0) + i);

                  // Random size within a range relative to viewport
                  final w = _randDouble(localRand, 0.35, 0.65) * math.min(width, height);
                  final h = _randDouble(localRand, 0.35, 0.65) * math.min(width, height);

                  // Random position with overflow allowance for nicer edges
                  final left = _randDouble(localRand, -0.2, 0.8) * width;
                  final top = _randDouble(localRand, -0.2, 0.8) * height;

                  // Pick two colors to make a gradient
                  final c1 = palette[localRand.nextInt(palette.length)];
                  final c2 = palette[localRand.nextInt(palette.length)];

                  // Random rotation
                  final rot = _randDouble(localRand, -math.pi, math.pi);

                  // Random polygon points
                  final pts = _randomPolygon(localRand);

                  final durationMs = 6000 + localRand.nextInt(8000);

                  final child = _PolygonBlob(
                    width: w,
                    height: h,
                    rotation: rot,
                    points: pts,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        c1.withValues(alpha: blobOpacity),
                        c2.withValues(alpha: blobOpacity * 0.9),
                      ],
                    ),
                    animated: animated,
                    durationMs: durationMs,
                    initialOffset: Offset(
                      _randDouble(localRand, -0.25, 0.25) * w,
                      _randDouble(localRand, -0.25, 0.25) * h,
                    ),
                  );

                  return Positioned(
                    left: left,
                    top: top,
                    child: child,
                  );
                });

                return Stack(children: blobs);
              },
            ),
          ),

          // Frosted overlay using BackdropFilter (the key step)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: const SizedBox.expand(),
            ),
          ),

          // Optional vignette overlay to improve contrast under content
          if (vignette)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 2.0,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.04),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static double _randDouble(math.Random r, double min, double max) => min + r.nextDouble() * (max - min);

  static List<Offset> _randomPolygon(math.Random r) {
    // 5~7 vertices polygon around unit square, similar to CSS clip-path polygon randomness
    final count = 5 + r.nextInt(3);
    return List.generate(count, (_) => Offset(r.nextDouble(), r.nextDouble()));
  }
}

class _PolygonBlob extends StatefulWidget {
  final double width;
  final double height;
  final double rotation;
  final List<Offset> points; // normalized 0..1
  final Gradient gradient;
  final bool animated;
  final int durationMs;
  final Offset initialOffset;

  const _PolygonBlob({
    required this.width,
    required this.height,
    required this.rotation,
    required this.points,
    required this.gradient,
    required this.animated,
    required this.durationMs,
    required this.initialOffset,
  });

  @override
  State<_PolygonBlob> createState() => _PolygonBlobState();
}

class _PolygonBlobState extends State<_PolygonBlob> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );

    final dx = widget.initialOffset.dx;
    final dy = widget.initialOffset.dy;

    _offsetAnim = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: Offset.zero, end: Offset(dx, dy)).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Offset(dx, dy), end: Offset.zero).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_controller);

    if (widget.animated) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final polygon = _PolygonClipper(widget.points);

    return AnimatedBuilder(
      animation: _offsetAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: _offsetAnim.value,
          child: Transform.rotate(
            angle: widget.rotation,
            child: ClipPath(
              clipper: polygon,
              child: Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  gradient: widget.gradient,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PolygonClipper extends CustomClipper<Path> {
  final List<Offset> points; // normalized points 0..1
  const _PolygonClipper(this.points);

  @override
  Path getClip(Size size) {
    if (points.isEmpty) return Path();
    final path = Path();
    final first = points.first;
    path.moveTo(first.dx * size.width, first.dy * size.height);
    for (int i = 1; i < points.length; i++) {
      final p = points[i];
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _PolygonClipper oldClipper) {
    return oldClipper.points != points;
  }
}

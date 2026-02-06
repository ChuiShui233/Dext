//绘制渐变色背景 不好看（
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class FrostedGlassBackground extends StatefulWidget {
  final int count;
  final double blurSigma;
  final double blobOpacity;
  final bool animated;
  final List<Color> palette;
  final int? seed;
  final bool vignette;
  final Duration colorTransitionDuration;
  final Curve colorTransitionCurve;

  const FrostedGlassBackground({
    super.key,
    this.count = 7,
    this.blurSigma = 150,
    this.blobOpacity = 0.5,
    this.animated = false,
    this.seed,
    this.vignette = true,
    this.colorTransitionDuration = const Duration(milliseconds: 350),
    this.colorTransitionCurve = Curves.easeInOut,
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
  State<FrostedGlassBackground> createState() => _FrostedGlassBackgroundState();
}

class _FrostedGlassBackgroundState extends State<FrostedGlassBackground>
    with AutomaticKeepAliveClientMixin {
  late final int _seed;

  @override
  void initState() {
    super.initState();
    // 固定随机种子，避免快速切换页面时重建导致的图形与模糊层不同步
    _seed = widget.seed ?? DateTime.now().millisecondsSinceEpoch;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 底层背景色：在主题切换时平滑过渡
    final Color baseBackgroundColor = isDark
        ? const Color(0xFF0A0A0A) // 深色模式：深黑背景
        : Colors.white; // 浅色模式：纯白背景

    return IgnorePointer(
      child: Stack(
        children: [
          // 最底层：主题背景色，切换时带动画
          Positioned.fill(
            child: AnimatedContainer(
              duration: widget.colorTransitionDuration,
              curve: widget.colorTransitionCurve,
              color: baseBackgroundColor,
            ),
          ),
          // 彩色壁纸blob层（使用稳定的种子）
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final blobs = List.generate(widget.count, (i) {
                  final localRand = math.Random(_seed + i);

                  final w = _randDouble(localRand, 0.5, 0.8) * math.min(width, height);
                  final h = _randDouble(localRand, 0.5, 0.8) * math.min(width, height);
                  final centerX = width * 0.5;
                  final centerY = height * 0.5;
                  final offsetX = _randDouble(localRand, -0.3, 0.3) * width;
                  final offsetY = _randDouble(localRand, -0.3, 0.3) * height;
                  final left = centerX + offsetX - w * 0.5;
                  final top = centerY + offsetY - h * 0.5;
                  final c1 = widget.palette[localRand.nextInt(widget.palette.length)];
                  final c2 = widget.palette[localRand.nextInt(widget.palette.length)];
                  final c3 = widget.palette[localRand.nextInt(widget.palette.length)];
                  final rot = _randDouble(localRand, -math.pi * 0.25, math.pi * 0.25);
                  final pts = _randomPolygon(localRand);
                  final durationMs = 8000 + localRand.nextInt(4000);
                  final gradientType = localRand.nextInt(2);
                  Gradient gradient;
                  switch (gradientType) {
                    case 0:
                      gradient = LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          c1.withValues(alpha: widget.blobOpacity),
                          c2.withValues(alpha: widget.blobOpacity * 0.8),
                          c3.withValues(alpha: widget.blobOpacity * 0.6),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      );
                      break;
                    default:
                      gradient = RadialGradient(
                        center: Alignment.center,
                        radius: 0.8,
                        colors: [
                          c1.withValues(alpha: widget.blobOpacity),
                          c2.withValues(alpha: widget.blobOpacity * 0.7),
                        ],
                        stops: const [0.0, 1.0],
                      );
                  }

                  final child = _PolygonBlob(
                    width: w,
                    height: h,
                    rotation: rot,
                    points: pts,
                    gradient: gradient,
                    animated: widget.animated,
                    durationMs: durationMs,
                    initialOffset: Offset.zero,
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
          // 将模糊层与其重绘隔离，避免在快速切换页面时被频繁重置
          Positioned.fill(
            child: RepaintBoundary(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: widget.blurSigma, sigmaY: widget.blurSigma),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (widget.vignette)
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
    final count = 5 + r.nextInt(2);
    final points = <Offset>[];
    
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi;
      final radius = _randDouble(r, 0.4, 0.7);
      final x = 0.5 + radius * math.cos(angle) * 0.4;
      final y = 0.5 + radius * math.sin(angle) * 0.4;
      points.add(Offset(x.clamp(0.1, 0.9), y.clamp(0.1, 0.9)));
    }
    
    return points;
  }
}

class _PolygonBlob extends StatefulWidget {
  final double width;
  final double height;
  final double rotation;
  final List<Offset> points;
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
  final List<Offset> points;
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

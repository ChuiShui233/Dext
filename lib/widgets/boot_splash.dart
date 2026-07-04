import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';

import 'package:dext/providers/theme_provider.dart';
import 'package:dext/theme/zincx_theme.dart';

class BootSplash extends StatefulWidget {
  final VoidCallback onReady;

  const BootSplash({
    super.key,
    required this.onReady,
  });

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _run();
    });
  }

  Future<void> _run() async {
    final startedAt = DateTime.now();
    final ctx = context;
    await Future.wait([
      _precache(ctx, const AssetImage('assets/images/p.jpg')),
      _precache(ctx, const AssetImage('assets/images/m.png')),
    ]);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < const Duration(milliseconds: 800)) {
      await Future<void>.delayed(const Duration(milliseconds: 800) - elapsed);
    }
    if (!mounted) return;
    widget.onReady();
  }

  Future<void> _precache(BuildContext ctx, ImageProvider provider) async {
    try {
      await precacheImage(provider, ctx);
    } catch (e) {
      debugPrint('预解码图片失败: $e');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: FTheme(
            data: theme.isDark ? zincDark : zincLight,
            child: ColoredBox(
              color: const Color(0xFF0F1115),
              child: Center(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(_ctrl.value);
                    final scale = 0.88 + 0.18 * t;
                    final opacity = 0.55 + 0.45 * t;
                    return Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: const Text(
                          'DEXT',
                          style: TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 10,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

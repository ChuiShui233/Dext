import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 自定义页面过渡构建器
class _FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.fastOutSlowIn.flipped,
    );
    return FadeTransition(opacity: curvedAnimation, child: child);
  }
}

// 统一过渡效果
final pageTransitionsTheme = const PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _FadePageTransitionsBuilder(),
    TargetPlatform.iOS: _FadePageTransitionsBuilder(),
    TargetPlatform.windows: _FadePageTransitionsBuilder(),
    TargetPlatform.macOS: _FadePageTransitionsBuilder(),
    TargetPlatform.linux: _FadePageTransitionsBuilder(),
  },
);

// Light Theme
final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'PingFangSC',
  brightness: Brightness.light,
  scaffoldBackgroundColor: const Color.fromARGB(248, 255, 255, 255),
  pageTransitionsTheme: pageTransitionsTheme,
  colorScheme: ColorScheme.light(
    surface: const Color.fromARGB(248, 255, 255, 255),
    primary: Colors.black.withOpacity(0.87),
    secondary: Colors.black.withOpacity(0.6),
    onPrimary: Colors.white,
    onSecondary: Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.dark, // 状态栏图标
  ),
  navigationRailTheme: NavigationRailThemeData(
    backgroundColor: Colors.transparent,
    indicatorColor: Colors.black.withOpacity(0.87),
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(15)),
    ),
  ),
  dividerTheme: DividerThemeData(
    color: Colors.black.withOpacity(0.12),
  ),
);

// Dark Theme
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'PingFangSC',
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF121212),
  pageTransitionsTheme: pageTransitionsTheme,
  colorScheme: ColorScheme.dark(
    surface: const Color(0xFF121212),
    primary: Colors.white.withOpacity(0.87),
    secondary: Colors.white.withOpacity(0.6),
    onPrimary: Colors.black,
    onSecondary: Colors.black,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.light, // 状态栏图标
  ),
  navigationRailTheme: NavigationRailThemeData(
    backgroundColor: Colors.transparent,
    indicatorColor: Colors.white.withOpacity(0.87),
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(15)),
    ),
  ),
  dividerTheme: DividerThemeData(
    color: Colors.white.withOpacity(0.12),
  ),
);

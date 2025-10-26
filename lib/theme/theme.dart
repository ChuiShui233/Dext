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
  fontFamily: 'PingFangSuper',
  brightness: Brightness.light,
  scaffoldBackgroundColor: const Color.fromARGB(248, 255, 255, 255),
  pageTransitionsTheme: pageTransitionsTheme,
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
  splashFactory: NoSplash.splashFactory,
  checkboxTheme: const CheckboxThemeData(
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
    splashRadius: 0,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    ),
  ),
  colorScheme: ColorScheme.light(
    surface: const Color.fromARGB(248, 255, 255, 255),
    primary: Colors.black.withValues(alpha: 0.87),
    secondary: Colors.black.withValues(alpha: 0.6),
    onPrimary: Colors.white,
    onSecondary: Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
  ),
  navigationRailTheme: NavigationRailThemeData(
    backgroundColor: Colors.transparent,
    indicatorColor: Colors.black.withValues(alpha: 0.87),
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(15)),
    ),
  ),
  dividerTheme: DividerThemeData(
    color: Colors.black.withValues(alpha: 0.12),
  ),
);

// Dark Theme
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'PingFangSuper',
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF121212),
  pageTransitionsTheme: pageTransitionsTheme,
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
  splashFactory: NoSplash.splashFactory,
  checkboxTheme: const CheckboxThemeData(
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
    splashRadius: 0,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: ButtonStyle(
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    ),
  ),
  colorScheme: ColorScheme.dark(
    surface: const Color(0xFF121212),
    primary: Colors.white.withValues(alpha: 0.87),
    secondary: Colors.white.withValues(alpha: 0.6),
    onPrimary: Colors.black,
    onSecondary: Colors.black,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.light,
  ),
  navigationRailTheme: NavigationRailThemeData(
    backgroundColor: Colors.transparent,
    indicatorColor: Colors.white.withValues(alpha: 0.87),
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(15)),
    ),
  ),
  dividerTheme: DividerThemeData(
    color: Colors.white.withValues(alpha: 0.12),
  ),
);

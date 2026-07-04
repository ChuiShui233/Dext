library;

import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'theme/theme.dart';
import 'theme/zincx_theme.dart';
import 'pages/lite/login_page_lite.dart';
import 'pages/lite/survey_entry_page.dart';
import 'pages/public_survey_page.dart';
import 'services/api_service.dart';
import 'services/lite_token_storage.dart';
import 'services/settings_service.dart';
import 'widgets/frosted_glass_background.dart';
import 'widgets/app_navigator.dart';
import 'widgets/survey_preview_card.dart';

class _FetchedSurveyInfo {
  final bool allowAnonymous;
  final SurveyPreview? preview;
  const _FetchedSurveyInfo({required this.allowAnonymous, this.preview});
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  ApiService.onUnauthorized = _handleUnauthorized;

  SettingsService().initialize();

  runApp(const DextLiteWebApp());
}

void _handleUnauthorized() {
  LiteTokenStorage.instance.clear();
  final ctx = appNavigatorKey.currentContext;
  if (ctx != null && ctx.mounted) {
    showFToast(
      context: ctx,
      title: const Text('登录已过期，请重新登录'),
    );
  }
}

class DextLiteWebApp extends StatefulWidget {
  const DextLiteWebApp({super.key});

  @override
  State<DextLiteWebApp> createState() => _DextLiteWebAppState();
}

class _DextLiteWebAppState extends State<DextLiteWebApp>
    with WidgetsBindingObserver {

  bool _loading = true;
  bool _signedIn = false;
  String? _pendingSurveyId;
  bool _allowAnonymous = false;
  SurveyPreview? _surveyPreview;
  ThemeMode _themeMode = ThemeMode.system;
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == ThemeMode.system && mounted) {
      setState(() {
        _isDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
      });
    }
  }

  Future<void> _bootstrap() async {
    _pendingSurveyId = _readIdFromUrl();
    _setThemeMode(_themeModeFromString(SettingsService().themeMode));
    final results = await Future.wait<Object?>([
      LiteTokenStorage.instance.isValid(),
      if (_pendingSurveyId != null) _fetchSurveyInfo(_pendingSurveyId!),
    ]);
    final valid = results[0] as bool;
    final fetched = results.length > 1 ? results[1] as _FetchedSurveyInfo? : null;
    if (!mounted) return;
    setState(() {
      _signedIn = valid;
      _allowAnonymous = fetched?.allowAnonymous ?? false;
      _surveyPreview = fetched?.preview;
      _loading = false;
    });
  }

  Future<void> _toggleTheme() async {
    setState(() {
      _isDark = !_isDark;
      _themeMode = _isDark ? ThemeMode.dark : ThemeMode.light;
    });
    await SettingsService().setThemeMode(_themeModeToString(_themeMode));
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
      if (mode == ThemeMode.system) {
        _isDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
      } else {
        _isDark = mode == ThemeMode.dark;
      }
    });
  }

  static ThemeMode _themeModeFromString(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static String _themeModeToString(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  /// 拉取 `?id=` 对应问卷的元信息。失败时返回 null。
  /// 失败（含 404 / 网络错误）时一律视为不可匿名，避免错误地把用户引向匿名入口。
  Future<_FetchedSurveyInfo?> _fetchSurveyInfo(String surveyUID) async {
    try {
      final data = await ApiService().getPublicSurvey(surveyUID);
      final allowAnonymous =
          data['allowAnonymous'] == true || data['allow_anonymous'] == true;
      final preview = SurveyPreview.tryFrom(data);
      return _FetchedSurveyInfo(allowAnonymous: allowAnonymous, preview: preview);
    } catch (_) {
      return null;
    }
  }

  String? _readIdFromUrl() {
    if (!kIsWeb) return null;
    try {
      final id = Uri.base.queryParameters['id'];
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return null;
  }

  Future<void> _onLoginSuccess(String token, DateTime expires) async {
    await LiteTokenStorage.instance.save(token: token, expires: expires);
    if (!mounted) return;
    setState(() => _signedIn = true);
  }

  Future<void> _onLogout() async {
    try {
      await ApiService().logout();
    } catch (_) {
    }
    await LiteTokenStorage.instance.clear();
    if (!mounted) return;
    setState(() {
      _signedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'DEXT Lite',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      themeAnimationDuration: Duration.zero,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _LiteScrollBehavior(),
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => _resolveEntryPage(),
          );
        }
        return null;
      },
      builder: (context, child) {
        return FToaster(
          child: FTheme(
            data: _isDark ? zincDark : zincLight,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: _resolveHome(),
    );
  }

  Widget _resolveHome() {
    if (_loading) return const _SplashPage();
    if (_signedIn) {
      return SurveyEntryPage(
        initialSurveyId: _pendingSurveyId,
        onLogout: _onLogout,
        onToggleTheme: _toggleTheme,
        surveyPreview: _surveyPreview,
      );
    }
    if (_pendingSurveyId != null && _allowAnonymous) {
      return PublicSurveyPage(
        surveyUID: _pendingSurveyId!,
        surveyPreview: _surveyPreview,
      );
    }
    return LoginPageLite(
      onToggleTheme: _toggleTheme,
      onLoginSuccess: _onLoginSuccess,
      surveyPreview: _surveyPreview,
    );
  }

  Widget _resolveEntryPage() {
    if (_loading) return const _SplashPage();
    if (_signedIn) {
      return SurveyEntryPage(
        initialSurveyId: _pendingSurveyId,
        onLogout: _onLogout,
        onToggleTheme: _toggleTheme,
        surveyPreview: _surveyPreview,
      );
    }
    return LoginPageLite(
      onToggleTheme: _toggleTheme,
      onLoginSuccess: _onLoginSuccess,
      surveyPreview: _surveyPreview,
    );
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF09090B) : const Color(0xFFF7F7F8),
      body: Stack(
        children: const [
          FrostedGlassBackground(
            count: 6,
            blurSigma: 100,
            blobOpacity: 0.2,
            animated: true,
            vignette: true,
          ),
          Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiteScrollBehavior extends MaterialScrollBehavior {
  const _LiteScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

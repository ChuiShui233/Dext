import 'dart:io';
import 'dart:ui';
import 'package:dext/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaption;
import 'package:tray_manager/tray_manager.dart';

import 'services/url_handler.dart';
import 'services/clipboard_service.dart';

import 'models/project.dart';
import 'pages/login_page.dart';
import 'pages/create_survey_page.dart';
import 'pages/frame_page.dart';
import 'pages/public_survey_page.dart';
import 'pages/public_access_page.dart';
import 'services/api_service.dart';
import 'widgets/window_caption.dart';

import 'theme/zincx_theme.dart';
import 'theme/theme.dart';

// Web 平台不支持 window_manager
bool get isDesktop {
  if (kIsWeb) return false;
  try {
    return const bool.fromEnvironment('dart.library.io') &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  } catch (_) {
    return false;
  }
}

class _AppWindowListener with WindowListener {
  @override
  void onWindowClose() async {
    // 拦截关闭，隐藏到托盘
    final isPrevent = await windowManager.isPreventClose();
    if (isPrevent) {
      await windowManager.hide();
    }
  }
}

class _AppTrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() async {
    // 单击切换显示/隐藏
    final visible = await windowManager.isVisible();
    if (visible) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键弹出菜单
    TrayManager.instance.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'hide':
        await windowManager.hide();
        break;
      case 'exit':
        await windowManager.setPreventClose(false);
        await windowManager.close();
        break;
    }
  }
}

Future<void> _initDesktopWindowAndTray() async {
  // 窗口初始化
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1500, 880),
    center: true,
    minimumSize: Size(600, 329),
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);
  windowManager.addListener(_AppWindowListener());

  // 托盘初始化
  await TrayManager.instance.setIcon('assets/images/Dext.ico');
  final menu = Menu(items: [
    MenuItem(key: 'show', label: '显示窗口'),
    MenuItem(key: 'hide', label: '隐藏到托盘'),
    MenuItem.separator(),
    MenuItem(key: 'exit', label: '退出'),
  ]);
  await TrayManager.instance.setContextMenu(menu);
  TrayManager.instance.addListener(_AppTrayListener());
}

void main() async {
  if (kDebugMode) {
    
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('SocketException') ||
          details.exception.toString().contains('Connection refused')) {
        return;
      }
      FlutterError.presentError(details);
    };
    
    PlatformDispatcher.instance.onError = (error, stack) {
      if (error.toString().contains('SocketException') ||
          error.toString().contains('Connection refused')) {
        return true;
      }
      return false;
    };
  }
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面窗口管理
  if (isDesktop) {
    await _initDesktopWindowAndTray();
  }

  // Android 状态栏透明
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));

  runApp(const YuMeng233App());
}

class YuMeng233App extends StatefulWidget {
  const YuMeng233App({super.key});

  @override
  State<YuMeng233App> createState() => _YuMeng233AppState();
}

class _YuMeng233AppState extends State<YuMeng233App>
    with WidgetsBindingObserver {
  final _storage = const FlutterSecureStorage();
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ThemeMode _themeMode = ThemeMode.system;
  bool _isDark = false;
  final ValueNotifier<User?> userNotifier = ValueNotifier<User?>(null);

  String? _token;
  DateTime? _tokenExpiry;
  int _selectedIndex = 0;
  bool _isRefreshingToken = false;
  String? _pendingSurveyId;
  

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
    WidgetsBinding.instance.addObserver(this);
    _updateThemeMode();
    _handleInitialUrl();
    _startClipboardListening();
    // 注册全局 401 处理：自动跳转登录并提示“登录已过期”
    ApiService.onUnauthorized = _handleUnauthorized401;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ClipboardService.instance.stopListening();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _updateThemeMode();
  }

  void _updateThemeMode() {
    if (_themeMode == ThemeMode.system) {
      final brightness = PlatformDispatcher.instance.platformBrightness;
      setState(() {
        _isDark = brightness == Brightness.dark;
      });
    }
  }

  void _toggleTheme() {
    setState(() {
      _isDark = !_isDark;
      _themeMode = _isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
      if (mode == ThemeMode.system) {
        _updateThemeMode();
      } else {
        _isDark = mode == ThemeMode.dark;
      }
    });
  }

  // 全局401处理：防抖，清理并回到登录
  bool _handlingUnauthorized = false;
  Future<void> _handleUnauthorized401() async {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      // 只有在用户已经登录的情况下才处理401（登录过期）
      final hasToken = _token != null && _tokenExpiry != null;
      
      // 清理本地令牌
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'token_expiry');
      if (!mounted) return;
      setState(() {
        _token = null;
        _tokenExpiry = null;
      });

      // 只有在之前已登录的情况下才显示登录过期提示
      if (hasToken) {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          showFToast(
            context: ctx,
            title: const Text('登录已过期，请重新登录'),
          );
        }
      }

      // 只有在已登录状态下才导航回登录页面
      if (hasToken) {
        final nav = _navigatorKey.currentState;
        nav?.pushNamedAndRemoveUntil('/', (route) => false);
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 800), () {
        _handlingUnauthorized = false;
      });
    }
  }

  Future<void> _checkAuthStatus() async {
    final token = await _storage.read(key: 'auth_token');
    final expiry = await _storage.read(key: 'token_expiry');

    if (token != null && expiry != null) {
      final expiryDate = DateTime.parse(expiry);
      if (expiryDate.isAfter(DateTime.now())) {
        setState(() {
          _token = token;
          _tokenExpiry = expiryDate;
        });
      } else {
        if (!_isRefreshingToken) {
          try {
            _isRefreshingToken = true;
            final newToken = await ApiService().refreshToken();
            await _storage.write(key: 'auth_token', value: newToken);
            await _checkAuthStatus();
          } catch (e) {
            _handleLogout();
          } finally {
            _isRefreshingToken = false;
          }
        }
      }
    }
  }

  Future<void> _handleLogout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'token_expiry');
    setState(() {
      _token = null;
      _tokenExpiry = null;
    });
    // 显式导航到登录页面
    final nav = _navigatorKey.currentState;
    nav?.pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    // 处理待处理的surveyId导航
    if (_pendingSurveyId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final surveyId = _pendingSurveyId!;
        _pendingSurveyId = null; // 清除待处理状态
        _navigateToPublicSurvey(surveyId);
      });
    }
    
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FToaster(
        child: Layout(
          child: FTheme(
            data: _isDark ? zincDark : zincLight, // Forui 主题
            child: MaterialApp(
              navigatorKey: _navigatorKey,
              title: '问卷调查系统',
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: _themeMode,
              themeAnimationDuration: Duration.zero,
              debugShowCheckedModeBanner: false,
              initialRoute: '/',
              onGenerateRoute: _onGenerateRoute,
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              builder: (context, child) {
                return ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Stack(
                    children: [
                      child!,
                      if (isDesktop)
                        const Align(
                          alignment: Alignment.topRight,
                          child: WindowCaption(),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    if (settings.name == '/') {
      return MaterialPageRoute(
        builder: (context) => _token != null && _tokenExpiry != null
            ? FramePage(
                bucket: _pageStorageBucket,
                selectedIndex: _selectedIndex,
                onIndexChanged: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                onLogout: _handleLogout,
                onThemeModeChange: _setThemeMode,
                apiService: ApiService(authToken: _token!),
                userNotifier: userNotifier,
              )
            : LoginPage(
                onToggleTheme: _toggleTheme,
                onLoginSuccess: (token, expiry) async {
                  await _storage.write(key: 'auth_token', value: token);
                  await _storage.write(
                    key: 'token_expiry',
                    value: expiry.toIso8601String(),
                  );
                  _checkAuthStatus();
                },
              ),
      );
    } else if (settings.name == '/projects') {
      return MaterialPageRoute(
        builder: (context) => FramePage(
          bucket: _pageStorageBucket,
          selectedIndex: 3,
          onIndexChanged: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          onLogout: _handleLogout,
          onThemeModeChange: _setThemeMode,
          apiService: ApiService(authToken: _token ?? ''),
          userNotifier: userNotifier,
        ),
      );
    } else if (settings.name == '/surveys') {
      return MaterialPageRoute(
        builder: (context) => FramePage(
          bucket: _pageStorageBucket,
          selectedIndex: 4,
          onIndexChanged: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          onLogout: _handleLogout,
          onThemeModeChange: _setThemeMode,
          apiService: ApiService(authToken: _token ?? ''),
          userNotifier: userNotifier,
        ),
      );
    } else if (settings.name == '/survey/create') {
      return MaterialPageRoute(
        builder: (context) => FutureBuilder<List<Project>>(
          future: _fetchProjects(_token ?? ''),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                extendBodyBehindAppBar: true,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  toolbarHeight: 0,
                ),
                body: const Center(child: CircularProgressIndicator()),
              );
            } else if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  toolbarHeight: 0,
                  systemOverlayStyle: _isDark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark,
                  title: const Text('错误'),
                ),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('加载项目失败: ${snapshot.error}'),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            } else if (snapshot.hasData) {
              return CreateSurveyPage(
                token: _token ?? '',
                projects: snapshot.data!,
              );
            } else {
              return const Scaffold(
                body: Center(child: Text('没有可用的项目')),
              );
            }
          },
        ),
      );
    } else if (settings.name?.startsWith('/public/survey/') == true) {
      // 处理公开问卷访问路由 /public/survey/{uid}
      final uri = Uri.parse(settings.name!);
      final pathSegments = uri.pathSegments;
      
      if (pathSegments.length >= 3 && pathSegments[0] == 'public' && pathSegments[1] == 'survey') {
        final surveyUID = pathSegments[2];
        return MaterialPageRoute(
          builder: (context) => PublicSurveyPage(surveyUID: surveyUID),
        );
      }
    } else if (settings.name == '/public/access') {
      // 公开问卷访问入口页面
      return MaterialPageRoute(
        builder: (context) => const PublicAccessPage(),
      );
    }
    
    // 默认404页面
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 0,
          systemOverlayStyle: _isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          title: const Text('页面未找到'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('页面不存在: ${settings.name}'),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                },
                child: const Text('返回首页'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Project>> _fetchProjects(String token) async {
    try {
      final apiService = ApiService(authToken: token);
      return await apiService.getProjects();
    } catch (e) {
      if (e.toString().contains('Socket') || e.toString().contains('网络')) {
        throw '网络连接失败，请检查网络设置';
      } else if (e.toString().contains('Http') || e.toString().contains('HTTP')) {
        throw '服务器连接失败，请稍后重试';
      } else {
        throw '获取项目失败: $e';
      }
    }
  }
  /// 处理初始URL和深度链接
  void _handleInitialUrl() async {
    try {
      if (kIsWeb) {
        // Web平台：从浏览器URL获取参数
        _handleWebUrl();
      } else {
        // 移动平台：处理深度链接
        _handleMobileDeepLink();
      }
    } catch (e) {
      debugPrint('处理初始URL失败: $e');
    }
  }

  /// Web平台URL处理
  void _handleWebUrl() {
    if (kIsWeb) {
      try {
        final surveyId = UrlHandler.instance.getWebUrlParameter('id');

        
        if (surveyId != null && surveyId.isNotEmpty) {
          // 保存surveyId，在build完成后处理
          _pendingSurveyId = surveyId;
        } else {

        }
      } catch (e) {
        debugPrint('Web URL解析失败: $e');
      }
    }
  }

  /// 移动平台深度链接处理
  void _handleMobileDeepLink() async {
    if (!kIsWeb) {
      try {
        // 获取初始链接
        final initialLink = await UrlHandler.instance.getInitialDeepLink();
        if (initialLink != null) {
          _processDeepLink(initialLink);
        }

        // 监听后续链接
        final linkStream = UrlHandler.instance.getDeepLinkStream();
        linkStream?.listen((String link) {
          _processDeepLink(link);
        }, onError: (err) {
          debugPrint('深度链接监听错误: $err');
        });
      } catch (e) {
        debugPrint('深度链接处理失败: $e');
      }
    }
  }

  /// 处理深度链接
  void _processDeepLink(String link) {
    try {
      final surveyId = UrlHandler.instance.extractSurveyId(link);
      
      if (surveyId != null && surveyId.isNotEmpty) {
        // 导航到公开问卷页面
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigateToPublicSurvey(surveyId);
        });
      }
    } catch (e) {
      debugPrint('深度链接解析失败: $e');
    }
  }

  /// 启动剪切板监听
  void _startClipboardListening() {
    ClipboardService.instance.startListening(
      onSurveyIdDetected: (surveyId) {
        // 确保在主线程中显示Toast
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = _navigatorKey.currentContext;
          if (context != null && mounted) {
            ClipboardService.showSurveyToast(
              context,
              surveyId,
              () => _navigateToPublicSurvey(surveyId),
            );
          }
        });
      },
    );
  }

  /// 导航到公开问卷页面
  void _navigateToPublicSurvey(String surveyId) {
    final navigatorState = _navigatorKey.currentState;
    if (navigatorState != null) {
      // 在Web平台直接使用MaterialPageRoute避免URL历史记录问题
      if (kIsWeb) {
        navigatorState.push(
          MaterialPageRoute(
            builder: (context) => PublicSurveyPage(surveyUID: surveyId),
            settings: RouteSettings(name: '/public/survey/$surveyId'),
          ),
        );
      } else {
        navigatorState.pushNamed('/public/survey/$surveyId');
      }
    }
  }
}

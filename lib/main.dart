import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:dext/widgets/app_navigator.dart';
import 'package:dext/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaption;
import 'package:tray_manager/tray_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'services/url_handler.dart';
import 'services/clipboard_service.dart';
import 'services/uri_handler_service.dart';
import 'services/settings_service.dart';
import 'services/push_service.dart';
import 'services/config.dart';
import 'utils/network_reachability.dart';
import 'utils/error_filter.dart';

import 'models/project.dart';
import 'pages/login_page.dart';
import 'pages/create_survey_page.dart';
import 'pages/frame_page.dart';
import 'pages/public_survey_page.dart';
import 'services/api_service.dart';
import 'widgets/window_caption.dart';

import 'theme/zincx_theme.dart';
import 'theme/theme.dart';
import 'package:provider/provider.dart';
import 'providers/user_info_provider.dart';

bool get isDesktop {
  if (kIsWeb) return false;
  try {
    return const bool.fromEnvironment('dart.library.io') &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  } catch (_) {
    return false;
  }
}

// 全局滚动行为：隐藏滚动条，同时支持多输入设备拖动
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // 返回原始child，不包裹Scrollbar，从而隐藏滚动条
    return child;
  }
}


class _AppWindowListener with WindowListener {
  @override
  void onWindowClose() async {
    final isPrevent = await windowManager.isPreventClose();
    if (isPrevent) {
      await windowManager.hide();
    }
  }
}

class _AppTrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() async {
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

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1500, 880),
    center: true,
    minimumSize: Size(400, 329),
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);
  windowManager.addListener(_AppWindowListener());

  await UriHandlerService.initialize();
  
  await TrayManager.instance.setIcon('assets/images/favicon.ico');
  final menu = Menu(items: [
    MenuItem(key: 'show', label: '显示窗口'),
    MenuItem(key: 'hide', label: '隐藏到托盘'),
    MenuItem.separator(),
    MenuItem(key: 'exit', label: '退出'),
  ]);
  await TrayManager.instance.setContextMenu(menu);
  TrayManager.instance.addListener(_AppTrayListener());
}

void main(List<String> args) async {
  // Run inside a zone to catch any uncaught async errors and print stacks
  runZonedGuarded(() async {
  if (kDebugMode) {
    // 设置日志过滤器
    debugPrint = (String? message, {int? wrapWidth}) {
    // 使用 ErrorFilter 来过滤日志
    if (ErrorFilter.shouldFilter(message!)) {
      return;
    }
  };
    
    FlutterError.onError = (FlutterErrorDetails details) {
      // 使用 ErrorFilter 来过滤异常
      if (ErrorFilter.shouldFilterException(details.exception)) {
        return;
      }
      
      FlutterError.presentError(details);
    };
    
    PlatformDispatcher.instance.onError = (error, stack) {
      // 使用 ErrorFilter 来过滤错误
      if (ErrorFilter.shouldFilterError(error)) {
        return true;
      }

      return false;
    };
  }
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args, 
      "dext_survey_app",
      onSecondWindow: (args) async {
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
        await windowManager.show();
        await windowManager.focus();
        
        if (args.isNotEmpty) {
          final uriString = args.join(' ');
          debugPrint('📨 第二实例收到参数: $uriString');
          
          try {
            if (uriString.startsWith('dext://')) {
              final uri = Uri.parse(uriString);
              UriHandlerService.handleIncomingUri(uri);
            }
          } catch (e) {
            debugPrint('❌ 解析URI失败: $e');
          }
        }
      },
    );
  }

  if (isDesktop) {
    try {
      await _initDesktopWindowAndTray();
    } catch (e) {
      // 啥玩意
    }
  }

  // Android 状态栏透明
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));

  // 初始化设置服务（防御性处理，避免异常导致启动中断）
  try {
    await SettingsService().initialize();
  } catch (e, st) {
    debugPrint('SettingsService.initialize() 失败: $e');
    debugPrint('$st');
  }

  if (!kIsWeb && !isDesktop) {
    try {
      final pushService = PushService();
      final initialized = await pushService.initialize(
        appId: getuiAppId,
        appKey: getuiAppKey,
        appSecret: getuiAppSecret,
      );
      
      if (initialized) {
        debugPrint('[个推] SDK初始化成功');
        // 启动推送服务
        await pushService.startPush();
      } else {
        debugPrint('[个推] SDK初始化失败');
      }
    } catch (e, st) {
      debugPrint('[个推] 初始化异常: $e');
      debugPrint('$st');
    }
  }

  runApp(const YuMeng233App());
  }, (error, stack) {
    // 打印未捕获异常，避免静默失败
    // 不做过滤，完整输出便于定位
    // 注意：仍然会在控制台可见
    // 如果需要上报，可在此处集成上报逻辑
    // ignore: avoid_print
    debugPrint('未捕获异常: $error');
    debugPrint('$stack');
  });
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
  final GlobalKey<FramePageState> _framePageKey = GlobalKey<FramePageState>();
  ThemeMode _themeMode = ThemeMode.system;
  bool _isDark = false;
  double _dpiScale = 1.0;
  final ValueNotifier<User?> userNotifier = ValueNotifier<User?>(null);

  String? _token;
  DateTime? _tokenExpiry;
  int _selectedIndex = 0;
  bool _isRefreshingToken = false;
  String? _pendingSurveyId;
  // 记录上一次网络状态：'connected' | 'none' | null
  String? _lastNetworkStatus;
  // 缓存项目列表，避免重复请求
  List<Project>? _cachedProjects;
  bool _isLoadingProjects = false;
  // 定期刷新令牌的定时器
  Timer? _tokenRefreshTimer;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
    _applySettingsFromStore();
    WidgetsBinding.instance.addObserver(this);
    _updateThemeMode();
    _handleInitialUrl();
    _startClipboardListening();
    // 注册全局 401 处理：自动跳转登录并提示“登录已过期”
    ApiService.onUnauthorized = _handleUnauthorized401;
    // 监听网络状态：每次从“有网/未知”切换到“无网”时提示一次
    NetworkReachability().connectNetworkFunc(connectNetWorkBlock: (status) {
      final prev = _lastNetworkStatus;
      _lastNetworkStatus = status;
      if (status == 'none' && prev != 'none') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = appNavigatorKey.currentContext ?? context;
          if (ctx.mounted) {
            showFToast(
              context: ctx,
              title: const Text('当前无网络连接'),
              description: const Text('部分功能将不可用，请检查网络设置。'),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ClipboardService.instance.stopListening();
    _tokenRefreshTimer?.cancel();
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
  
  // 从 SettingsService 读取持久化设置并应用（不依赖设置页面）
  void _applySettingsFromStore() {
    try {
      final settings = SettingsService();
      final mode = settings.themeMode; // 'system' | 'light' | 'dark'
      ThemeMode resolved;
      switch (mode) {
        case 'light':
          resolved = ThemeMode.light;
          break;
        case 'dark':
          resolved = ThemeMode.dark;
          break;
        default:
          resolved = ThemeMode.system;
      }
      _setThemeMode(resolved);
      
      // 加载 DPI 缩放设置
      _dpiScale = settings.dpiScale;
    } catch (_) {
      // 忽略设置加载异常，保持默认值
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
  
  void _setDpiScale(double scale) {
    setState(() {
      _dpiScale = scale;
    });
  }

  // 全局401处理：防抖，清理并回到登录
  bool _isHandlingUnauthorized = false;
  Future<void> _handleUnauthorized401() async {
    if (_isHandlingUnauthorized) return;
    _isHandlingUnauthorized = true;
    try {
      // 只有在用户已经登录的情况下才处理401（登录过期）
      final hasToken = _token != null && _tokenExpiry != null;
      
      // 清理本地令牌
      // 清理本地数据和缓存
      try {
        await ApiService().clearAllLocalData();
      } catch (e) {
        debugPrint('清理缓存失败: $e');
      }
      
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
        _isHandlingUnauthorized = false;
      });
    }
  }

  Future<void> _checkAuthStatus() async {
    final token = await _storage.read(key: 'auth_token');
    final expiry = await _storage.read(key: 'token_expiry');

    if (token != null && expiry != null) {
      DateTime? expiryDate;
      try {
        expiryDate = DateTime.tryParse(expiry);
      } catch (_) {
        expiryDate = null;
      }

      if (expiryDate == null) {
        // 存储中的过期时间异常，清理并回到登录
        try {
          await ApiService().clearAllLocalData();
        } catch (_) {}
        await _storage.delete(key: 'auth_token');
        await _storage.delete(key: 'token_expiry');
        setState(() {
          _token = null;
          _tokenExpiry = null;
        });
        return;
      }

      if (expiryDate.isAfter(DateTime.now())) {
        setState(() {
          _token = token;
          _tokenExpiry = expiryDate;
        });
        // 启动定时刷新令牌（仅在已登录状态下）
        _startTokenRefreshTimer();
      } else {
        if (!_isRefreshingToken) {
          try {
            _isRefreshingToken = true;
            // 使用从storage读取的token，而不是状态变量_token（可能是null或旧值）
            final newToken = await ApiService(authToken: token).refreshToken();
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

  // 启动定时刷新令牌（每10分钟）
  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (_token != null && _tokenExpiry != null) {
        _refreshToken();
      } else {
        // 如果已登出，停止定时器
        timer.cancel();
      }
    });
  }

  // 定期刷新令牌
  Future<void> _refreshToken() async {
    if (_isRefreshingToken) return;
    
    try {
      _isRefreshingToken = true;
      final newToken = await ApiService(authToken: _token).refreshToken();
      await _storage.write(key: 'auth_token', value: newToken);
      // 更新令牌后重新检查状态
      await _checkAuthStatus();
    } catch (e) {
      // 刷新失败时不显示错误，由401处理程序处理
      debugPrint('定时刷新令牌失败: $e');
    } finally {
      _isRefreshingToken = false;
    }
  }

  Future<void> _handleLogout() async {
    // 停止定时刷新
    _tokenRefreshTimer?.cancel();
    
    // 清理本地存储 (SharedPreferences 缓存)
    try {
      await ApiService().clearAllLocalData();
    } catch (e) {
      debugPrint('清理缓存失败: $e');
    }

    // 清理安全存储 (Tokens)
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'token_expiry');
    
    // 更新状态
    setState(() {
      _token = null;
      _tokenExpiry = null;
    });
    
    // 显式导航到登录页面
    final nav = _navigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 处理待处理的surveyId导航
    if (_pendingSurveyId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final surveyId = _pendingSurveyId!;
        _pendingSurveyId = null;
        _navigateToPublicSurvey(surveyId);
      });
    }
    
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FToaster(
        child: Layout(
          child: FTheme(
            data: _isDark ? zincDark : zincLight,
            child: ChangeNotifierProvider<UserInfoProvider>(
              create: (_) => UserInfoProvider(),
              child: MaterialApp(
              navigatorKey: appNavigatorKey,
              title: 'DEXT',
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: _themeMode,
              themeAnimationDuration: Duration.zero,
              debugShowCheckedModeBanner: false,
              initialRoute: '/',
              onGenerateRoute: _onGenerateRoute,
              scrollBehavior: const _NoScrollbarBehavior(),
              builder: (context, child) {
                // 应用 DPI 缩放设置
                return ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Stack(
                    children: [
                      // 使用 MediaQuery 设置文本缩放
                      MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(_dpiScale),
                        ),
                        child: child!,
                      ),
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
      ),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    if (settings.name == '/') {
      return MaterialPageRoute(
        builder: (context) => _token != null && _tokenExpiry != null
            ? FramePage(
                key: _framePageKey,
                bucket: _pageStorageBucket,
                selectedIndex: _selectedIndex,
                onIndexChanged: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                onLogout: _handleLogout,
                onThemeModeChange: _setThemeMode,
                onDpiScaleChange: _setDpiScale,
                apiService: ApiService(authToken: _token!),
                userNotifier: userNotifier,
              )
            : LoginPage(
                onToggleTheme: _toggleTheme,
                onLoginSuccess: (token, expiry) async {
                  debugPrint('👉 main.dart onLoginSuccess 被调用');
                  debugPrint('Token: ${token.substring(0, 20)}...');
                  debugPrint('Expiry: $expiry');
                  
                  await _storage.write(key: 'auth_token', value: token);
                  debugPrint('✅ Token已保存到storage');
                  
                  await _storage.write(
                    key: 'token_expiry',
                    value: expiry.toIso8601String(),
                  );
                  debugPrint('✅ Expiry已保存到storage');
                  
                  debugPrint('🔄 调用 _checkAuthStatus()');
                  await _checkAuthStatus();
                  debugPrint('✅ _checkAuthStatus() 完成');
                  debugPrint('📊 当前状态: _token=${_token?.substring(0, 20)}, _tokenExpiry=$_tokenExpiry');
                  
                  // 登录成功后启动定时刷新
                  _startTokenRefreshTimer();
                  debugPrint('✅ onLoginSuccess 完成');
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
          onDpiScaleChange: _setDpiScale,
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
          onDpiScaleChange: _setDpiScale,
          apiService: ApiService(authToken: _token ?? ''),
          userNotifier: userNotifier,
        ),
      );
    } else if (settings.name == '/survey/create') {
      return MaterialPageRoute(
        builder: (context) => _CreateSurveyPageWrapper(
          token: _token ?? '',
          fetchProjects: () => _fetchProjects(_token ?? ''),
          isDark: _isDark,
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
    }
    
    return MaterialPageRoute(
      builder: (context) => _NotFoundPage(
        routeName: settings.name ?? 'unknown',
        isDark: _isDark,
      ),
    );
  }

  Future<List<Project>> _fetchProjects(String token) async {
    if (_cachedProjects != null) return _cachedProjects!;
    if (_isLoadingProjects) {
      // 等待正在进行的请求完成
      while (_isLoadingProjects) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _cachedProjects ?? [];
    }
    
    _isLoadingProjects = true;
    try {
      final apiService = ApiService(authToken: token);
      final projects = await apiService.getProjects();
      _cachedProjects = projects;
      return projects;
    } catch (e) {
      throw Exception('获取项目列表失败: $e');
    } finally {
      _isLoadingProjects = false;
    }
  }
  void _handleInitialUrl() async {
    try {
      if (kIsWeb) {
        _handleWebUrl();
      } else {
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

          final hash = Uri.base.fragment;
          
          // 如果 hash 已经包含问卷路由，说明Flutter已经处理了，不再重复导航
          if (hash.isNotEmpty && hash.contains('/public/survey/')) {
            return;
          }

          _pendingSurveyId = surveyId;
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
        final context = appNavigatorKey.currentContext ?? _navigatorKey.currentContext;
        if (context != null && mounted) {
          ClipboardService.showSurveyToast(
            context,
            surveyId,
            () => _navigateToPublicSurvey(surveyId),
          );
        }
      },
    );
  }

  /// 导航到公开问卷页面
  void _navigateToPublicSurvey(String surveyId) {
    // 如果用户已登录且在FramePage中，使用FramePage的嵌套导航
    if (_framePageKey.currentState != null) {
      _framePageKey.currentState!.navigateToPublicSurvey(surveyId);
    } else {
      // 否则使用全局导航
      final navigatorState = appNavigatorKey.currentState ?? _navigatorKey.currentState;
      if (navigatorState != null) {
        navigatorState.pushNamed('/public/survey/$surveyId');
      }
    }
  }
}

class _CreateSurveyPageWrapper extends StatefulWidget {
  final String token;
  final Future<List<Project>> Function() fetchProjects;
  final bool isDark;

  const _CreateSurveyPageWrapper({
    required this.token,
    required this.fetchProjects,
    required this.isDark,
  });

  @override
  State<_CreateSurveyPageWrapper> createState() => _CreateSurveyPageWrapperState();
}

class _CreateSurveyPageWrapperState extends State<_CreateSurveyPageWrapper> {
  List<Project>? _projects;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await widget.fetchProjects();
      if (mounted) {
        setState(() {
          _projects = projects;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 0,
          systemOverlayStyle: widget.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          title: const Text('错误'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载项目失败: $_error'),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadProjects();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (_projects != null) {
      return CreateSurveyPage(
        token: widget.token,
        projects: _projects!,
      );
    } else {
      return const Scaffold(
        body: Center(child: Text('没有可用的项目')),
      );
    }
  }
}

// 404页面 - 自动返回主页
class _NotFoundPage extends StatefulWidget {
  final String routeName;
  final bool isDark;

  const _NotFoundPage({
    required this.routeName,
    required this.isDark,
  });

  @override
  State<_NotFoundPage> createState() => _NotFoundPageState();
}

class _NotFoundPageState extends State<_NotFoundPage> {
  int _countdown = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0,
        systemOverlayStyle: widget.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '页面不存在',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '$_countdown 秒后自动返回首页...',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _timer?.cancel();
                Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
              },
              child: const Text('立即返回'),
            ),
          ],
        ),
      ),
    );
  }
}

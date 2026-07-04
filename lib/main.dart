import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher, PointerDeviceKind;
import 'package:dext/widgets/app_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart';
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
import 'widgets/boot_splash.dart';

import 'theme/zincx_theme.dart';
import 'theme/theme.dart';
import 'package:provider/provider.dart';
import 'providers/user_info_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/project_provider.dart';

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

late final _AppTrayListener _trayListener;

Future<void> _exitApp() async {
  TrayManager.instance.removeListener(_trayListener);
  await TrayManager.instance.destroy();
  windowManager.removeListener(_windowListener);
  await windowManager.setPreventClose(false);
  await windowManager.destroy();
  await Future.delayed(const Duration(milliseconds: 100));
  exit(0);
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
        await _exitApp();
    }
  }
}

late final _AppWindowListener _windowListener;

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
  _windowListener = _AppWindowListener();
  windowManager.addListener(_windowListener);

  await UriHandlerService.initialize();
  
  await TrayManager.instance.setIcon('assets/images/favicon.ico');
  await TrayManager.instance.setToolTip('Dext'); 
  final menu = Menu(items: [
    MenuItem(key: 'show', label: '显示窗口'),
    MenuItem(key: 'hide', label: '隐藏到托盘'),
    MenuItem.separator(),
    MenuItem(key: 'exit', label: '退出'),
  ]);
  await TrayManager.instance.setContextMenu(menu);
  _trayListener = _AppTrayListener();
  TrayManager.instance.addListener(_trayListener);
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

  // Android 边缘到边缘渲染 + 状态栏/导航栏透明
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

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

  runApp(const DextApp());
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

class DextApp extends StatefulWidget {
  const DextApp({super.key});

  @override
  State<DextApp> createState() => _DextAppState();
}

class _DextAppState extends State<DextApp>
    with WidgetsBindingObserver {
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<FramePageState> _framePageKey = GlobalKey<FramePageState>();

  final AuthProvider _auth = AuthProvider();
  final ThemeProvider _theme = ThemeProvider();
  final UserInfoProvider _userInfo = UserInfoProvider();
  late final ProjectProvider _projects = ProjectProvider(
    apiServiceBuilder: _auth.buildApiService,
  );

  int _selectedIndex = 0;
  bool _isHandlingUnauthorized = false;
  final List<String> _pendingSurveyIds = [];
  // 记录上一次网络状态：'connected' | 'none' | null
  String? _lastNetworkStatus;
  // 定期刷新令牌的定时器
  Timer? _tokenRefreshTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    WidgetsBinding.instance.addObserver(this);
    _handleInitialUrl();
    _startClipboardListening();
    // 注册全局 401 处理：自动跳转登录并提示“登录已过期”
    ApiService.onUnauthorized = _handleUnauthorized401;
    // 监听 AuthProvider：登录态变化时刷新根路由
    _auth.addListener(_onAuthChanged);
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
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _theme.dispose();
    _userInfo.dispose();
    _projects.dispose();
    super.dispose();
  }

  bool? _lastIsLoggedIn;

  void _onAuthChanged() {
    if (!mounted) return;
    if (_lastIsLoggedIn == _auth.isLoggedIn) return;
    _lastIsLoggedIn = _auth.isLoggedIn;
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  void didChangePlatformBrightness() {
    // 主题模式变更由 ThemeProvider 监听
  }

  bool _authReady = false;

  void _onBootReady() {
    if (!mounted) return;
    setState(() {
      _authReady = true;
    });
    if (_auth.isLoggedIn) {
      _startTokenRefreshTimer();
    }
  }

  Future<void> _bootstrap() async {
    try {
      await _auth.initialize();
    } catch (e) {
      debugPrint('AuthProvider.initialize() 失败: $e');
    }
  }

  // 启动定时刷新令牌（每10分钟）
  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (_auth.isLoggedIn) {
        _refreshToken();
      } else {
        timer.cancel();
      }
    });
  }

  // 定期刷新令牌
  Future<void> _refreshToken() async {
    if (_auth.isRefreshing) return;
    try {
      await _auth.refreshToken();
    } catch (e) {
      debugPrint('定时刷新令牌失败: $e');
    }
  }

  Future<void> _handleLogout() async {
    _tokenRefreshTimer?.cancel();
    try {
      await ApiService().clearAllLocalData();
    } catch (e) {
      debugPrint('清理缓存失败: $e');
    }
    await _auth.logout();
    _userInfo.clear();
    _projects.clear();
    if (mounted) setState(() {});
  }

  // 全局401处理：防抖，清理并回到登录
  Future<void> _handleUnauthorized401() async {
    if (_isHandlingUnauthorized) return;
    _isHandlingUnauthorized = true;
    try {
      final hasToken = _auth.isLoggedIn;
      try {
        await ApiService().clearAllLocalData();
      } catch (e) {
        debugPrint('清理缓存失败: $e');
      }
      await _auth.logout();
      _userInfo.clear();
      _projects.clear();
      if (mounted) setState(() {});

      if (hasToken) {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          showFToast(
            context: ctx,
            title: const Text('登录已过期，请重新登录'),
          );
        }
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 800), () {
        _isHandlingUnauthorized = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _processPendingSurveys();
    if (!_authReady) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: _auth),
          ChangeNotifierProvider<ThemeProvider>.value(value: _theme),
          ChangeNotifierProvider<UserInfoProvider>.value(value: _userInfo),
          ChangeNotifierProvider<ProjectProvider>.value(value: _projects),
        ],
        child: BootSplash(
          onReady: _onBootReady,
        ),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: _theme),
        ChangeNotifierProvider<UserInfoProvider>.value(value: _userInfo),
        ChangeNotifierProvider<ProjectProvider>.value(value: _projects),
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FToaster(
          child: Layout(
            child: Consumer2<ThemeProvider, AuthProvider>(
              builder: (context, theme, auth, _) {
                return FTheme(
                  data: theme.isDark ? zincDark : zincLight,
                  child: MaterialApp(
                    navigatorKey: appNavigatorKey,
                    title: 'DEXT',
                    theme: lightTheme,
                    darkTheme: darkTheme,
                    themeMode: theme.themeMode,
                    themeAnimationDuration: Duration.zero,
                    debugShowCheckedModeBanner: false,
                    initialRoute: '/',
                    onGenerateRoute: _onGenerateRoute,
                    scrollBehavior: const _NoScrollbarBehavior(),
                    builder: (context, child) {
                      return ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Stack(
                          children: [
                            MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                textScaler: TextScaler.linear(theme.dpiScale),
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final auth = _auth;
    final theme = _theme;
    if (settings.name == '/') {
      return MaterialPageRoute(
        builder: (context) => auth.isLoggedIn
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
                apiService: auth.buildApiService(),
              )
            : LoginPage(
                onToggleTheme: theme.toggle,
                onLoginSuccess: (token, expiry) async {
                  await auth.login(token, expiry);
                  _userInfo.clear();
                  _projects.clear();
                  if (mounted) setState(() {});
                  _startTokenRefreshTimer();
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
          apiService: auth.buildApiService(),
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
          apiService: auth.buildApiService(),
        ),
      );
    } else if (settings.name == '/survey/create') {
      return MaterialPageRoute(
        builder: (context) => _CreateSurveyPageWrapper(
          isDark: theme.isDark,
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
        isDark: theme.isDark,
      ),
    );
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

          _pendingSurveyIds.add(surveyId);
          _processPendingSurveys();
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

  /// 处理待处理的问卷导航
  void _processPendingSurveys() {
    if (_pendingSurveyIds.isEmpty) return;
    if (_framePageKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _processPendingSurveys());
      return;
    }

    final pending = List<String>.from(_pendingSurveyIds);
    _pendingSurveyIds.clear();
    for (final surveyId in pending) {
      _framePageKey.currentState!.navigateToPublicSurvey(surveyId);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = appNavigatorKey.currentState ?? _navigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((route) => route.isFirst);
      }
    });
  }

  /// 处理深度链接
  void _processDeepLink(String link) {
    try {
      final surveyId = UrlHandler.instance.extractSurveyId(link);
      
      if (surveyId != null && surveyId.isNotEmpty) {
        _pendingSurveyIds.add(surveyId);
        _processPendingSurveys();
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
    _pendingSurveyIds.add(surveyId);
    _processPendingSurveys();
  }
}

class _CreateSurveyPageWrapper extends StatefulWidget {
  final bool isDark;

  const _CreateSurveyPageWrapper({
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
    final provider = context.read<ProjectProvider>();
    try {
      final projects = await provider.ensureLoaded();
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
      return Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return CreateSurveyPage(
            token: auth.token ?? '',
            projects: _projects!,
          );
        },
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


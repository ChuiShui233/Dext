import 'dart:io';
import 'package:dext/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaption;

import 'models/project.dart';
import 'pages/login_page.dart';
import 'pages/create_survey_page.dart';
import 'pages/frame_page.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面窗口管理
  if (isDesktop) {
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
  ThemeMode _themeMode = ThemeMode.system;
  bool _isDark = false;
  final ValueNotifier<User?> userNotifier = ValueNotifier<User?>(null);

  String? _token;
  DateTime? _tokenExpiry;
  int _selectedIndex = 0;
  bool _isRefreshingToken = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
    WidgetsBinding.instance.addObserver(this);
    _updateThemeMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FToaster(
        child: Layout(
          child: FTheme(
            data: _isDark ? zincDark : zincLight, // Forui 主题
            child: MaterialApp(
              title: '问卷调查系统',
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: _themeMode,
              themeAnimationDuration: Duration.zero,
              debugShowCheckedModeBanner: false,
              initialRoute: '/',
              onGenerateRoute: _onGenerateRoute,
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
    } else {
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
  }

  Future<List<Project>> _fetchProjects(String token) async {
    try {
      final apiService = ApiService(authToken: token);
      return await apiService.getProjects();
    } catch (e) {
      if (e is SocketException) {
        throw Exception('网络连接失败，请检查网络设置');
      } else if (e is HttpException) {
        throw Exception('服务器连接失败，请稍后重试');
      } else {
        throw Exception('获取项目失败: $e');
      }
    }
  }
}

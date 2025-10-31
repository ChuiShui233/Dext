import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置服务，管理所有持久化设置
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  SharedPreferences? _prefs;
  bool _isInitialized = false;

  // 内存缓存，在初始化时加载
  late bool _windowCloseDontAsk;
  late String _windowCloseDefaultAction;
  late String _themeMode;
  late bool _glassCardEnabled;
  late double _edgeDragWidth;

  // 设置键名常量
  static const String keyWindowCloseDontAsk = 'window_close_dont_ask';
  static const String keyWindowCloseDefaultAction = 'window_close_default_action';
  static const String keyThemeMode = 'theme_mode';
  static const String keyGlassCardEnabled = 'glass_card_enabled';
  static const String keyEdgeDragWidth = 'edge_drag_width';

  /// 初始化设置服务（在 main 函数中调用）
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      // 可能是首行字符错误/JSON损坏导致的 FormatException
      // 回退到内存默认值，允许应用继续运行
      _prefs = null;
    }

    // 预加载所有设置到内存（当 _prefs 为空时使用默认值）
    _windowCloseDontAsk = _prefs?.getBool(keyWindowCloseDontAsk) ?? false;
    _windowCloseDefaultAction = _prefs?.getString(keyWindowCloseDefaultAction) ?? 'ask';
    _themeMode = _prefs?.getString(keyThemeMode) ?? 'system';
    _glassCardEnabled = _prefs?.getBool(keyGlassCardEnabled) ?? true;
    _edgeDragWidth = _prefs?.getDouble(keyEdgeDragWidth) ?? 24.0;

    _isInitialized = true;
  }

  /// 确保已初始化
  void _ensureInitialized() {
    if (!_isInitialized) {
      // 懒加载：提供安全默认值，避免在构建早期抛异常
      _windowCloseDontAsk = false;
      _windowCloseDefaultAction = 'ask';
      _themeMode = 'system';
      _glassCardEnabled = true;
      _edgeDragWidth = 24.0;
      _isInitialized = true;
      // 异步尝试真正初始化（不阻塞当前读取）
      // ignore: discarded_futures
      initialize();
    }
    // 当 _prefs == null 时也允许读取内存中的默认值；写入时将被忽略
  }

  // === 窗口关闭设置 ===
  
  bool get windowCloseDontAsk {
    _ensureInitialized();
    return _windowCloseDontAsk;
  }

  Future<void> setWindowCloseDontAsk(bool value) async {
    _ensureInitialized();
    _windowCloseDontAsk = value;
    if (_prefs != null) {
      await _prefs!.setBool(keyWindowCloseDontAsk, value);
    }
  }

  String get windowCloseDefaultAction {
    _ensureInitialized();
    return _windowCloseDefaultAction;
  }

  Future<void> setWindowCloseDefaultAction(String value) async {
    _ensureInitialized();
    _windowCloseDefaultAction = value;
    if (_prefs != null) {
      await _prefs!.setString(keyWindowCloseDefaultAction, value);
    }
  }

  // === 主题设置 ===
  
  String get themeMode {
    _ensureInitialized();
    return _themeMode;
  }

  Future<void> setThemeMode(String value) async {
    _ensureInitialized();
    _themeMode = value;
    if (_prefs != null) {
      await _prefs!.setString(keyThemeMode, value);
    }
  }

  // === 界面效果设置：毛玻璃卡片 ===
  bool get glassCardEnabled {
    _ensureInitialized();
    return _glassCardEnabled;
  }

  Future<void> setGlassCardEnabled(bool value) async {
    _ensureInitialized();
    _glassCardEnabled = value;
    if (_prefs != null) {
      await _prefs!.setBool(keyGlassCardEnabled, value);
    }
  }

  // === 侧滑触发范围设置 ===
  double get edgeDragWidth {
    _ensureInitialized();
    return _edgeDragWidth;
  }

  Future<void> setEdgeDragWidth(double value) async {
    _ensureInitialized();
    _edgeDragWidth = value;
    if (_prefs != null) {
      await _prefs!.setDouble(keyEdgeDragWidth, value);
    }
  }

  // === 通用方法 ===
  
  Future<void> clear() async {
    _ensureInitialized();
    if (_prefs != null) {
      await _prefs!.clear();
    }
    // 同时重置内存值
    _windowCloseDontAsk = false;
    _windowCloseDefaultAction = 'ask';
    _themeMode = 'system';
    _glassCardEnabled = true;
    _edgeDragWidth = 24.0;
  }

  Future<void> reload() async {
    _ensureInitialized();
    if (_prefs != null) {
      await _prefs!.reload();
      // 重新加载所有设置到内存
      _windowCloseDontAsk = _prefs!.getBool(keyWindowCloseDontAsk) ?? false;
      _windowCloseDefaultAction = _prefs!.getString(keyWindowCloseDefaultAction) ?? 'ask';
      _themeMode = _prefs!.getString(keyThemeMode) ?? 'system';
      _glassCardEnabled = _prefs!.getBool(keyGlassCardEnabled) ?? true;
      _edgeDragWidth = _prefs!.getDouble(keyEdgeDragWidth) ?? 24.0;
    }
  }
}


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isDark = false;
  double _dpiScale = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS ? 0.85 : 1.0;
  final bool _platformBrightnessBound = true;

  ThemeProvider() {
    _loadFromSettings();
    if (_platformBrightnessBound) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _isDark;
  double get dpiScale => _dpiScale;

  void _loadFromSettings() {
    try {
      final mode = SettingsService().themeMode;
      switch (mode) {
        case 'light':
          _themeMode = ThemeMode.light;
          _isDark = false;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          _isDark = true;
          break;
        default:
          _themeMode = ThemeMode.system;
          _isDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
      }
      _dpiScale = SettingsService().dpiScale;
    } catch (_) {
      // 保留默认
    }
  }

  void reload() {
    _loadFromSettings();
    notifyListeners();
  }

  void refresh() {
    reload();
  }

  void toggle() {
    _isDark = !_isDark;
    _themeMode = _isDark ? ThemeMode.dark : ThemeMode.light;
    _persist();
    notifyListeners();
  }

  void setMode(ThemeMode mode) {
    _themeMode = mode;
    if (mode == ThemeMode.system) {
      _isDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    } else {
      _isDark = mode == ThemeMode.dark;
    }
    _persist();
    notifyListeners();
  }

  void setDpiScale(double scale) {
    if ((scale - _dpiScale).abs() < 0.001) return;
    _dpiScale = scale;
    _persistDpi();
    notifyListeners();
  }

  void _persist() {
    try {
      SettingsService().setThemeMode(_themeModeToString(_themeMode));
    } catch (_) {}
  }

  void _persistDpi() {
    try {
      SettingsService().setDpiScale(_dpiScale);
    } catch (_) {}
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode != ThemeMode.system) return;
    _isDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    notifyListeners();
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  @override
  void dispose() {
    if (_platformBrightnessBound) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}

import 'dart:io';

import 'package:flutter/services.dart';

/// 电源/后台相关能力封装（仅 Android 有效）
class PowerService {
  static const MethodChannel _channel = MethodChannel('com.chuishui.Dext/power');

  /// 是否已忽略电池优化（Android Doze）
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 请求忽略电池优化授权（会唤起系统授权界面）
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 打开电池优化设置列表（用户可手动搜索应用授权）
  static Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }
}

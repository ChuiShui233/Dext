import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 通用缓存服务，用于管理页面数据的本地缓存
class CacheService {
  static const String _prefix = 'cache_';
  static const Duration _defaultExpiry = Duration(hours: 24);

  /// 保存缓存数据
  static Future<void> set(String key, dynamic data, {Duration? expiry}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_prefix$key';
      final expiryTime = DateTime.now().add(expiry ?? _defaultExpiry).millisecondsSinceEpoch;
      
      final cacheData = {
        'data': data,
        'expiry': expiryTime,
      };
      
      await prefs.setString(cacheKey, jsonEncode(cacheData));
    } catch (e) {
      if (kDebugMode) {
        print('缓存保存失败: $e');
      }
    }
  }

  /// 获取缓存数据
  /// 返回 null 表示缓存不存在或已过期
  static Future<dynamic> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_prefix$key';
      final cacheString = prefs.getString(cacheKey);
      
      if (cacheString == null) {
        return null;
      }
      
      final cacheData = jsonDecode(cacheString);
      final expiryTime = cacheData['expiry'] as int;
      
      // 检查是否过期
      if (DateTime.now().millisecondsSinceEpoch > expiryTime) {
        // 过期，删除缓存
        await remove(key);
        return null;
      }
      
      return cacheData['data'];
    } catch (e) {
      if (kDebugMode) {
        print('缓存读取失败: $e');
      }
      return null;
    }
  }

  /// 删除指定缓存
  static Future<void> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_prefix$key';
      await prefs.remove(cacheKey);
    } catch (e) {
      if (kDebugMode) {
        print('缓存删除失败: $e');
      }
    }
  }

  /// 清除所有缓存
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      if (kDebugMode) {
        print('清除所有缓存失败: $e');
      }
    }
  }

  /// 检查缓存是否存在且未过期
  static Future<bool> has(String key) async {
    final data = await get(key);
    return data != null;
  }
}

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

/// Web端OAuth窗口处理器
/// 解决用户主动关闭OAuth弹窗时页面永远等待的问题
class WebOAuthHandler {
  static const int _defaultTimeoutSeconds = 300; // 5分钟超时
  static const int _checkIntervalMs = 1000; // 每秒检查一次窗口状态

  /// 处理OAuth认证流程
  /// 
  /// [authUrl] OAuth认证URL
  /// [redirectUrl] 重定向URL
  /// [windowOptions] 弹窗选项
  /// [timeoutSeconds] 超时时间（秒）
  static Future<String> authenticate({
    required String authUrl,
    required String redirectUrl,
    Map<String, dynamic>? windowOptions,
    int timeoutSeconds = _defaultTimeoutSeconds,
  }) async {
    if (!kIsWeb) {
      throw UnsupportedError('WebOAuthHandler只能在Web平台使用');
    }

    // 构建窗口选项
    final options = _buildWindowOptions(windowOptions);
    
    // 打开OAuth弹窗
    final popup = web.window.open(authUrl, 'oauth_popup', options);
    
    if (popup == null) {
      throw Exception('无法打开OAuth弹窗，可能被浏览器阻止');
    }

    try {
      // 创建多个并发的Future来处理不同情况
      final result = await Future.any([
        _waitForMessage(redirectUrl),           // 等待OAuth回调消息
        _waitForWindowClose(popup),            // 检测窗口关闭
        _waitForTimeout(timeoutSeconds),       // 超时处理
      ]);

      // 确保弹窗被关闭
      if (!popup.closed) {
        popup.close();
      }

      return result;
    } catch (e) {
      // 确保弹窗被关闭
      if (!popup.closed) {
        popup.close();
      }
      rethrow;
    }
  }

  /// 等待OAuth回调消息
  static Future<String> _waitForMessage(String redirectUrl) async {
    final completer = Completer<String>();
    late StreamSubscription subscription;

    subscription = web.window.onMessage.listen((event) {
      try {
        final data = event.data;
        
        // 检查是否是OAuth回调消息
        if (data != null) {
          final dataMap = data.dartify() as Map?;
          if (dataMap != null) {
            if (dataMap['type'] == 'oauth_success') {
              subscription.cancel();
              if (!completer.isCompleted) {
                completer.complete(dataMap['callback_url']?.toString() ?? '');
              }
            } else if (dataMap['type'] == 'oauth_error') {
              subscription.cancel();
              if (!completer.isCompleted) {
                final error = dataMap['error_description']?.toString() ?? 
                             dataMap['error']?.toString() ?? '未知错误';
                completer.completeError(Exception('OAuth错误: $error'));
              }
            }
          }
        }
      } catch (e) {
        // 忽略无效消息
      }
    });

    return completer.future;
  }

  /// 检测窗口关闭
  static Future<String> _waitForWindowClose(web.Window popup) async {
    final completer = Completer<String>();
    
    Timer.periodic(Duration(milliseconds: _checkIntervalMs), (timer) {
      if (popup.closed) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            OAuthWindowClosedException('用户关闭了OAuth登录窗口')
          );
        }
      }
    });

    return completer.future;
  }

  /// 超时处理
  static Future<String> _waitForTimeout(int timeoutSeconds) async {
    await Future.delayed(Duration(seconds: timeoutSeconds));
    throw OAuthTimeoutException('OAuth登录超时（$timeoutSeconds秒）');
  }

  /// 构建窗口选项字符串
  static String _buildWindowOptions(Map<String, dynamic>? options) {
    final defaultOptions = {
      'menubar': 'no',
      'status': 'no',
      'scrollbars': 'yes',
      'resizable': 'yes',
      'width': '500',
      'height': '700',
      'left': '${(web.window.screen.width - 500) ~/ 2}',
      'top': '${(web.window.screen.height - 700) ~/ 2}',
    };

    // 合并用户选项
    if (options != null) {
      defaultOptions.addAll(options.map((k, v) => MapEntry(k, v.toString())));
    }

    return defaultOptions.entries
        .map((e) => '${e.key}=${e.value}')
        .join(',');
  }
}

/// OAuth窗口关闭异常
class OAuthWindowClosedException implements Exception {
  final String message;
  const OAuthWindowClosedException(this.message);
  
  @override
  String toString() => 'OAuthWindowClosedException: $message';
}

/// OAuth超时异常
class OAuthTimeoutException implements Exception {
  final String message;
  const OAuthTimeoutException(this.message);
  
  @override
  String toString() => 'OAuthTimeoutException: $message';
}

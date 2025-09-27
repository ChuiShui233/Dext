import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as flutter_services;
import 'package:forui/forui.dart';
import 'package:clipboard_watcher/clipboard_watcher.dart' if (dart.library.io) 'package:clipboard_watcher/clipboard_watcher.dart';
import 'url_handler.dart';

// Web 平台剪切板权限处理 - 使用 Flutter 的 Clipboard API

/// 剪切板监听服务
class ClipboardService with ClipboardListener {
  static ClipboardService? _instance;
  static ClipboardService get instance => _instance ??= ClipboardService._();
  
  ClipboardService._();
  
  bool _isListening = false;
  String? _lastClipboardContent;
  Function(String)? _onSurveyIdDetected;
  Timer? _webClipboardTimer;
  bool _webClipboardPermissionGranted = false;
  
  /// 开始监听剪切板
  Future<void> startListening({Function(String)? onSurveyIdDetected}) async {
    if (_isListening) return;
    
    _onSurveyIdDetected = onSurveyIdDetected;
    
    if (kIsWeb) {
      await _startWebClipboardListening();
    } else {
      await _startNativeClipboardListening();
    }
  }
  
  /// 启动原生平台剪切板监听
  Future<void> _startNativeClipboardListening() async {
    try {
      await clipboardWatcher.start();
      clipboardWatcher.addListener(this);
      _isListening = true;
      developer.log('原生剪切板监听已启动');
    } catch (e) {
      developer.log('启动原生剪切板监听失败: $e');
    }
  }
  
  /// 启动 Web 平台剪切板监听
  Future<void> _startWebClipboardListening() async {
    try {
      // 申请剪切板读取权限
      final hasPermission = await _requestWebClipboardPermission();
      if (!hasPermission) {
        developer.log('Web 剪切板权限申请失败');
        return;
      }
      
      _webClipboardPermissionGranted = true;
      _isListening = true;
      
      // 启动定时器监听剪切板变化
      _webClipboardTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _checkWebClipboard(),
      );
      
      developer.log('Web 剪切板监听已启动');
    } catch (e) {
      developer.log('启动 Web 剪切板监听失败: $e');
    }
  }
  
  /// 申请 Web 平台剪切板权限
  Future<bool> _requestWebClipboardPermission() async {
    if (!kIsWeb) return false;
    
    try {
      // 检查是否支持 Clipboard API
      if (!_isClipboardApiSupported()) {
        developer.log('浏览器不支持 Clipboard API');
        return false;
      }
      
      // 临时设置权限标志以允许读取剪切板
      _webClipboardPermissionGranted = true;
      
      // 尝试读取剪切板以测试权限
      final testRead = await flutter_services.Clipboard.getData(flutter_services.Clipboard.kTextPlain);
      developer.log('Web 剪切板权限申请成功: ${testRead?.text?.isNotEmpty ?? false}');
      return true;
    } catch (e) {
      developer.log('Web 剪切板权限申请失败: $e');
      _webClipboardPermissionGranted = false;
      return false;
    }
  }
  
  /// 检查浏览器是否支持 Clipboard API
  bool _isClipboardApiSupported() {
    // Web 平台使用 Flutter 的 Clipboard API，总是支持
    return kIsWeb;
  }

  /// 读取 Web 平台剪切板内容
  Future<String?> _readWebClipboard() async {
    if (!kIsWeb || !_webClipboardPermissionGranted) return null;
    
    try {
      // 使用 Flutter 的 Clipboard API 读取剪切板
      final clipboardData = await flutter_services.Clipboard.getData(flutter_services.Clipboard.kTextPlain);
      return clipboardData?.text;
    } catch (e) {
      developer.log('读取 Web 剪切板失败: $e');
      return null;
    }
  }
  
  /// 检查 Web 平台剪切板变化
  void _checkWebClipboard() async {
    if (!kIsWeb || !_webClipboardPermissionGranted) return;
    
    try {
      final content = await _readWebClipboard();
      if (content == null || content.isEmpty || content == _lastClipboardContent) {
        return;
      }
      
      _lastClipboardContent = content;
      
      // 检测问卷ID
      final surveyId = UrlHandler.instance.detectSurveyIdFromClipboard(content);
      if (surveyId != null && surveyId.isNotEmpty) {
        developer.log('Web 平台检测到问卷ID: $surveyId');
        _onSurveyIdDetected?.call(surveyId);
      }
    } catch (e) {
      developer.log('Web 剪切板检查失败: $e');
    }
  }
  
  /// 停止监听剪切板
  Future<void> stopListening() async {
    if (!_isListening) return;
    
    try {
      if (kIsWeb) {
        _webClipboardTimer?.cancel();
        _webClipboardTimer = null;
        _webClipboardPermissionGranted = false;
      } else {
        clipboardWatcher.removeListener(this);
        await clipboardWatcher.stop();
      }
      
      _isListening = false;
      _onSurveyIdDetected = null;
      _lastClipboardContent = null;
      developer.log('剪切板监听已停止');
    } catch (e) {
      developer.log('停止剪切板监听失败: $e');
    }
  }
  
  @override
  void onClipboardChanged() async {
    if (kIsWeb) return;
    
    try {
      final clipboardData = await flutter_services.Clipboard.getData(flutter_services.Clipboard.kTextPlain);
      final content = clipboardData?.text?.trim() ?? '';
      
      // 避免重复处理相同内容
      if (content.isEmpty || content == _lastClipboardContent) return;
      _lastClipboardContent = content;
      
      // 检测问卷ID
      final surveyId = UrlHandler.instance.detectSurveyIdFromClipboard(content);
      if (surveyId != null && surveyId.isNotEmpty) {
        developer.log('检测到问卷ID: $surveyId');
        _onSurveyIdDetected?.call(surveyId);
      }
    } catch (e) {
      developer.log('处理剪切板变化失败: $e');
    }
  }
  
  /// 显示问卷打开提示
  static void showSurveyToast(
    BuildContext context,
    String surveyId,
    VoidCallback onOpenSurvey,
  ) {
    final displayId = surveyId.length > 8 ? '${surveyId.substring(0, 8)}...' : surveyId;
    
    showRawFToast(
      context: context,
      duration: const Duration(seconds: 5),
      builder: (context, entry) => Container(
        constraints: const BoxConstraints(
          maxWidth: 300,
          minHeight: 0,
        ),
        child: Material(
          color: FTheme.of(context).colors.muted,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: FTheme.of(context).colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '检测到问卷链接',
                  style: TextStyle(
                    color: FTheme.of(context).colors.foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '发现问卷ID: $displayId',
                  style: TextStyle(
                    color: FTheme.of(context).colors.foreground,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FButton(
                      onPress: () {
                        entry.dismiss();
                        onOpenSurvey();
                      },
                      child: const Text('打开'),
                    ),
                    const SizedBox(width: 8),
                    FButton(
                      onPress: () => entry.dismiss(),
                      child: const Text('忽略'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

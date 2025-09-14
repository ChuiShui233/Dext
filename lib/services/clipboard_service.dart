import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:clipboard_watcher/clipboard_watcher.dart' if (dart.library.io) 'package:clipboard_watcher/clipboard_watcher.dart';
import 'url_handler.dart';

/// 剪切板监听服务
class ClipboardService with ClipboardListener {
  static ClipboardService? _instance;
  static ClipboardService get instance => _instance ??= ClipboardService._();
  
  ClipboardService._();
  
  bool _isListening = false;
  String? _lastClipboardContent;
  Function(String)? _onSurveyIdDetected;
  
  /// 开始监听剪切板
  Future<void> startListening({Function(String)? onSurveyIdDetected}) async {
    if (kIsWeb || _isListening) return;
    
    try {
      _onSurveyIdDetected = onSurveyIdDetected;
      await clipboardWatcher.start();
      clipboardWatcher.addListener(this);
      _isListening = true;
      developer.log('剪切板监听已启动');
    } catch (e) {
      developer.log('启动剪切板监听失败: $e');
    }
  }
  
  /// 停止监听剪切板
  Future<void> stopListening() async {
    if (kIsWeb || !_isListening) return;
    
    try {
      clipboardWatcher.removeListener(this);
      await clipboardWatcher.stop();
      _isListening = false;
      _onSurveyIdDetected = null;
      developer.log('剪切板监听已停止');
    } catch (e) {
      developer.log('停止剪切板监听失败: $e');
    }
  }
  
  @override
  void onClipboardChanged() async {
    if (kIsWeb) return;
    
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
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
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '检测到问卷链接',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '发现问卷ID: $displayId',
                  style: const TextStyle(fontSize: 12),
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

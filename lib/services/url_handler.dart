import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'dart:developer' as developer;

import 'url_handler_web.dart' if (dart.library.io) 'url_handler_stub.dart';
import 'package:app_links/app_links.dart';

class UrlHandler {
  static UrlHandler? _instance;
  static UrlHandler get instance => _instance ??= UrlHandler._();
  
  UrlHandler._();
  final AppLinks _appLinks = AppLinks();

  /// 获取Web平台的URL参数
  String? getWebUrlParameter(String paramName) {
    if (!kIsWeb) return null;
    
    try {
      return getWebUrlParameterImpl(paramName);
    } catch (e) {
      developer.log('获取Web URL参数失败: $e');
      return null;
    }
  }

  Future<String?> getInitialDeepLink() async {
    if (kIsWeb) return null;
    
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return null;
    }
    
    try {
      await _appLinks.getInitialLink();
    } catch (e) {
      developer.log('获取初始深度链接失败: $e');
      return null;
    }
    return null;
  }

  /// 监听深度链接（移动平台）
  Stream<String>? getDeepLinkStream() {
    if (kIsWeb) return null;
    
    // 检查是否为桌面平台（Windows、macOS、Linux）
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return null;
    }
    
    try {
      return _appLinks.stringLinkStream;
    } catch (e) {
      developer.log('监听深度链接失败: $e');
      return null;
    }
  }

  /// 从URL中提取问卷ID
  String? extractSurveyId(String url) {
    try {
      final uri = Uri.parse(url);
      
      // 优先从查询参数获取
      final idFromQuery = uri.queryParameters['id'];
      if (idFromQuery != null && idFromQuery.isNotEmpty) {
        return idFromQuery;
      }
      
      // 从路径中提取（如 /public/survey/xxx）
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 3 && 
          pathSegments[0] == 'public' && 
          pathSegments[1] == 'survey') {
        return pathSegments[2];
      }
      
      return null;
    } catch (e) {
      developer.log('提取问卷ID失败: $e');
      return null;
    }
  }

  /// 从剪切板内容中检测问卷ID
  String? detectSurveyIdFromClipboard(String clipboardText) {
    if (clipboardText.isEmpty) return null;
    
    try {
      // 检查是否是完整的URL
      if (clipboardText.startsWith('http')) {
        return extractSurveyId(clipboardText);
      }
      
      // 检查是否直接是16位问卷ID
      final trimmed = clipboardText.trim();
      if (trimmed.length == 16 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(trimmed)) {
        return trimmed;
      }
      
      // 检查是否包含?id=参数
      if (clipboardText.contains('?id=')) {
        final match = RegExp(r'\?id=([a-zA-Z0-9]{16})').firstMatch(clipboardText);
        if (match != null) {
          return match.group(1);
        }
      }
      
      return null;
    } catch (e) {
      developer.log('检测剪切板问卷ID失败: $e');
      return null;
    }
  }
}

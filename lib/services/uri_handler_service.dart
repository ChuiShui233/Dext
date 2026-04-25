import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

class UriHandlerService {
  static StreamSubscription? _linkSubscription;
  static final Map<String, Completer<String?>> _pendingCallbacks = {};
  static final AppLinks _appLinks = AppLinks();
  static const _windowsChannel = MethodChannel('dext/uri_handler');

  static final StreamController<String> _quickShareController = StreamController<String>.broadcast();
  static Stream<String> get onQuickShareLink => _quickShareController.stream;

  /// 初始化URI监听
  static Future<void> initialize() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return; // 这些平台不需要特殊处理
    }

    debugPrint('=== 开始初始化URI处理服务 ===');
    
    // 设置Windows平台的Method Channel处理器
    if (Platform.isWindows) {
      _windowsChannel.setMethodCallHandler((call) async {
        if (call.method == 'handleUri') {
          final uri = call.arguments['uri'] as String?;
          if (uri != null) {
            debugPrint('从Windows原生层接收到URI: $uri');
            try {
              final parsedUri = Uri.parse(uri);
              handleIncomingUri(parsedUri);
            } catch (e) {
              debugPrint('❌ 解析URI失败: $e');
            }
          }
        }
      });
      debugPrint('Windows Method Channel已设置');
    }

    try {
      // 监听传入的URI链接
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          debugPrint('🔗 接收到URI链接: $uri');
          handleIncomingUri(uri);
        },
        onError: (err) {
          debugPrint('❌ URI监听错误: $err');
        },
      );

      debugPrint('✅ URI监听器已启动，等待 dext:// 协议回调...');

      // 检查应用启动时是否有URI
      final initialUri = await _appLinks.getInitialAppLink();
      if (initialUri != null) {
        debugPrint('📱 应用启动时检测到URI: $initialUri');
        handleIncomingUri(initialUri);
      } else {
        debugPrint('ℹ️ 应用启动时没有检测到URI');
      }
      
      debugPrint('=== URI处理服务初始化完成 ===');
    } catch (e) {
      debugPrint('❌ URI处理服务初始化失败: $e');
      debugPrint('⚠️ 请确保已注册 dext:// 协议');
    }
  }

  /// 处理传入的URI
  static void _handleQuickShareLink(String id) {
    debugPrint('🔗 处理快速分享链接: $id');
    _quickShareController.add(id);
  }

  static void handleIncomingUri(Uri uri) {
    debugPrint('🔍 处理URI: $uri');
    debugPrint('  - Scheme: ${uri.scheme}');
    debugPrint('  - Host: ${uri.host}');
    debugPrint('  - Path: ${uri.path}');
    debugPrint('  - Query: ${uri.query}');

    // 处理 https://qs.chuishui.top/?id=xxx 格式的深度链接
    if ((uri.host == 'qs.chuishui.top' || uri.host == 'wucode.xyz') && uri.queryParameters.containsKey('id')) {
      final id = uri.queryParameters['id']!;
      debugPrint('📋 深度链接ID: $id');
      _handleQuickShareLink(id);
      return;
    }
    
    if (uri.scheme == 'dext' && uri.host == 'oauth') {
      final path = uri.path;
      final queryParams = uri.queryParameters;
      
      if (path == '/callback') {
        final state = queryParams['state'];
        final code = queryParams['code'];
        final error = queryParams['error'];
        
        debugPrint('OAuth回调参数:');
        debugPrint('  - State: $state');
        debugPrint('  - Code: ${code != null ? "存在" : "缺失"}');
        debugPrint('  - Error: $error');
        
        if (state != null && _pendingCallbacks.containsKey(state)) {
          debugPrint('✅ 找到对应的待处理回调，状态码: $state');
          final completer = _pendingCallbacks.remove(state);
          
          if (error != null) {
            debugPrint('❌ OAuth返回错误: $error');
            completer?.completeError(Exception('OAuth错误: $error'));
          } else if (code != null) {
            debugPrint('✅ OAuth授权成功，已获取授权码');
            completer?.complete(code);
          } else {
            debugPrint('❌ OAuth回调缺少授权码');
            completer?.completeError(Exception('OAuth回调缺少授权码'));
          }
        } else {
          debugPrint('⚠️ 未找到对应的待处理回调');
          debugPrint('  当前待处理状态: ${_pendingCallbacks.keys.toList()}');
        }
      }
    }
  }

  /// 启动OAuth流程并等待回调
  /// 返回: Map 包含 'code' (授权码) 和 'state' (状态码)
  static Future<Map<String, String>> launchOAuthAndWaitForCallback({
    required String authUrl,
    required String state,
  }) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      // 非桌面平台直接抛出异常
      throw UnsupportedError('此平台不支持桌面OAuth流程');
    }

    // 创建回调等待器
    final completer = Completer<String?>();
    _pendingCallbacks[state] = completer;

    Timer? heartbeatTimer;
    
    try {
      // 启动系统浏览器
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint('已启动浏览器进行OAuth授权，等待回调...');
      } else {
        throw Exception('无法启动浏览器');
      }

      // 创建心跳检测，每5秒显示一次提示
      heartbeatTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        // 检查是否还有待处理的回调
        if (!_pendingCallbacks.containsKey(state)) {
          timer.cancel();
          return;
        }
        
        debugPrint('⏳ 等待OAuth授权中... 请在浏览器完成授权或点击取消按钮');
      });

      // 等待回调（无超时限制，用户可通过取消按钮终止）
      final result = await completer.future;

      heartbeatTimer.cancel();
      return {'code': result ?? '', 'state': state};
    } catch (e) {
      heartbeatTimer?.cancel();
      _pendingCallbacks.remove(state);
      rethrow;
    }
  }

  /// 取消所有待处理的OAuth回调
  static void cancelAllPendingCallbacks() {
    for (final completer in _pendingCallbacks.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('OAuth流程已取消'));
      }
    }
    _pendingCallbacks.clear();
    debugPrint('已取消所有待处理的OAuth回调');
  }

  /// 取消特定状态的OAuth回调
  static void cancelCallback(String state) {
    final completer = _pendingCallbacks.remove(state);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(Exception('OAuth流程已取消'));
      debugPrint('已取消OAuth回调: $state');
    }
  }

  /// 清理资源
  static void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    
    // 移除Method Channel处理器
    if (Platform.isWindows) {
      _windowsChannel.setMethodCallHandler(null);
    }
    
    // 清理所有待处理的回调
    for (final completer in _pendingCallbacks.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('服务已关闭'));
      }
    }
    _pendingCallbacks.clear();
    
    // 关闭快速分享链接流
    _quickShareController.close();
  }

  /// 生成随机state参数
  static String generateState() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp * 31) % 1000000;
    return 'state_${timestamp}_$random';
  }
}

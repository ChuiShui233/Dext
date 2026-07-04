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

  static String generateState() {
    return 'state_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecondsSinceEpoch % 100000).toString().padLeft(5, '0')}';
  }

  static Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    if (Platform.isWindows) {
      _windowsChannel.setMethodCallHandler((call) async {
        if (call.method == 'handleUri') {
          final uri = call.arguments['uri'] as String?;
          if (uri != null) {
            try {
              final parsedUri = Uri.parse(uri);
              handleIncomingUri(parsedUri);
            } catch (_) {}
          }
        }
      });
    }

    try {
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          handleIncomingUri(uri);
        },
        onError: (_) {},
      );

      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        handleIncomingUri(initialUri);
      }
    } catch (_) {}
  }

  static void _handleQuickShareLink(String id) {
    _quickShareController.add(id);
  }

  static void handleIncomingUri(Uri uri) {
    if ((uri.host == 'qs.chuishui.top' || uri.host == 'wucode.xyz') && uri.queryParameters.containsKey('id')) {
      final id = uri.queryParameters['id']!;
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

        if (state != null && _pendingCallbacks.containsKey(state)) {
          final completer = _pendingCallbacks.remove(state);

          if (error != null) {
            completer?.completeError(Exception('OAuth错误: $error'));
          } else if (code != null) {
            completer?.complete(code);
          } else {
            completer?.completeError(Exception('OAuth回调缺少授权码'));
          }
        }
      }
      return;
    }

    if (uri.host == 'server.chuishui.top' && uri.path.startsWith('/api/auth/oauth/callback/')) {
      final queryParams = uri.queryParameters;
      final state = queryParams['state'];
      final code = queryParams['code'];
      final error = queryParams['error'];

      if (state != null && _pendingCallbacks.containsKey(state)) {
        final completer = _pendingCallbacks.remove(state);

        if (error != null) {
          completer?.completeError(Exception('OAuth错误: $error'));
        } else if (code != null) {
          completer?.complete(code);
        } else {
          completer?.completeError(Exception('OAuth回调缺少授权码'));
        }
      }
    }
  }

  static Future<Map<String, String>> launchOAuthAndWaitForCallback({
    required String authUrl,
    required String state,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('此平台不支持桌面OAuth流程');
    }

    final completer = Completer<String?>();
    _pendingCallbacks[state] = completer;

    Timer? heartbeatTimer;

    try {
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('无法启动浏览器');
      }

      heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!_pendingCallbacks.containsKey(state)) {
          timer.cancel();
        }
      });

      final result = await completer.future;

      heartbeatTimer.cancel();
      return {'code': result ?? '', 'state': state};
    } catch (e) {
      heartbeatTimer?.cancel();
      _pendingCallbacks.remove(state);
      rethrow;
    }
  }

  static void cancelAllPendingCallbacks() {
    for (final completer in _pendingCallbacks.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('OAuth流程已取消'));
      }
    }
    _pendingCallbacks.clear();
  }

  static void cancelCallback(String state) {
    final completer = _pendingCallbacks.remove(state);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(Exception('OAuth流程已取消'));
    }
  }

  static void dispose() {
    _linkSubscription?.cancel();
  }
}

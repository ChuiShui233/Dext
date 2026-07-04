import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:getuiflut/getuiflut.dart';
import 'package:permission_handler/permission_handler.dart';

/// 个推推送服务封装
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  bool _initialized = false;
  String? _clientId;
  String? _deviceToken;
  final Getuiflut _gt = Getuiflut();
  
  // 消息回调
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationArrivedController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationClickedController = StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get onMessageReceived => _messageController.stream;
  Stream<Map<String, dynamic>> get onNotificationArrived => _notificationArrivedController.stream;
  Stream<Map<String, dynamic>> get onNotificationClicked => _notificationClickedController.stream;

  /// 初始化个推SDK
  /// 
  /// [appId] 个推应用ID
  /// [appKey] 个推应用Key
  /// [appSecret] 个推应用Secret
  Future<bool> initialize({
    required String appId,
    required String appKey,
    required String appSecret,
  }) async {
    if (_initialized) {
      debugPrint('[PushService] 已经初始化，跳过');
      return true;
    }

    try {
      // 自定义SDK：Android/ohos 需先 initGetuiSdk；iOS 需要 startSdk
      _gt.initGetuiSdk;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _gt.startSdk(appId: appId, appKey: appKey, appSecret: appSecret);
      }

      _setupListeners();
      await _checkAndRequestNotificationPermission();

      _initialized = true;
      debugPrint('[PushService] 初始化成功');
      return true;
    } catch (e) {
      debugPrint('[PushService] 初始化异常: $e');
      return false;
    }
  }

  /// 设置事件监听
  void _setupListeners() {
    _gt.addEventHandler(
      onReceiveClientId: (String res) async {
        _clientId = res;
        debugPrint('[PushService] ClientId: $res');
      },
      onNotificationMessageArrived: (Map<String, dynamic> msg) async {
        debugPrint('[PushService] 通知消息到达: $msg');
        _notificationArrivedController.add(msg);
      },
      onNotificationMessageClicked: (Map<String, dynamic> msg) async {
        debugPrint('[PushService] 通知消息点击: $msg');
        _notificationClickedController.add(msg);
      },
      onTransmitUserMessageReceive: (Map<String, dynamic> msg) async {
        debugPrint('[PushService] 透传消息: $msg');
        _messageController.add(msg);
      },
      onReceiveOnlineState: (String state) async {
        debugPrint('[PushService] Push online status: $state');
      },
      onRegisterDeviceToken: (String token) async {
        _deviceToken = token;
        debugPrint('[PushService] Device Token: $token');
      },
      onReceivePayload: (Map<String, dynamic> payload) async {},
      onReceiveNotificationResponse: (Map<String, dynamic> resp) async {},
      onAppLinkPayload: (String res) async {},
      onPushModeResult: (Map<String, dynamic> res) async {},
      onSetTagResult: (Map<String, dynamic> res) async {
        debugPrint('[PushService] 设置标签结果: $res');
      },
      onAliasResult: (Map<String, dynamic> res) async {
        debugPrint('[PushService] 别名结果: $res');
      },
      onQueryTagResult: (Map<String, dynamic> res) async {},
      onWillPresentNotification: (Map<String, dynamic> res) async {},
      onOpenSettingsForNotification: (Map<String, dynamic> res) async {},
      onGrantAuthorization: (String res) async {},
      onLiveActivityResult: (Map<String, dynamic> res) async {},
      onRegisterPushToStartTokenResult: (Map<String, dynamic> res) async {},
    );
  }

  /// 绑定别名 (通常用于绑定用户ID)
  Future<void> bindAlias(String alias, {String? sn}) async {
    if (!_initialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      _gt.bindAlias(alias, sn ?? '');
      debugPrint('[PushService] 绑定别名: $alias');
    } catch (e) {
      debugPrint('[PushService] 绑定别名失败: $e');
    }
  }

  /// 解绑别名
  Future<void> unbindAlias(String alias, {String? sn}) async {
    if (!_initialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      _gt.unbindAlias(alias, sn ?? '', true);
      debugPrint('[PushService] 解绑别名: $alias');
    } catch (e) {
      debugPrint('[PushService] 解绑别名失败: $e');
    }
  }

  /// 设置标签
  Future<void> setTags(List<String> tags, {String? sn}) async {
    if (!_initialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      _gt.setTag(tags, sn ?? '');
      debugPrint('[PushService] 设置标签: $tags');
    } catch (e) {
      debugPrint('[PushService] 设置标签失败: $e');
    }
  }

  /// 启动推送服务
  Future<void> startPush() async {
    if (!_initialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      _gt.turnOnPush();
      debugPrint('[PushService] 启动推送服务');
    } catch (e) {
      debugPrint('[PushService] 启动推送服务失败: $e');
    }
  }

  /// 停止推送服务
  Future<void> stopPush() async {
    if (!_initialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      _gt.turnOffPush();
      debugPrint('[PushService] 停止推送服务');
    } catch (e) {
      debugPrint('[PushService] 停止推送服务失败: $e');
    }
  }

  /// 设置应用角标 (iOS)
  Future<void> setBadge(int badge) async {
    if (!_initialized) return;
    
    try {
      _gt.setBadge(badge);
      debugPrint('[PushService] 设置角标: $badge');
    } catch (e) {
      debugPrint('[PushService] 设置角标失败: $e');
    }
  }

  /// 重置角标 (iOS)
  Future<void> resetBadge() async {
    if (!_initialized) return;
    
    try {
      _gt.resetBadge();
      debugPrint('[PushService] 重置角标');
    } catch (e) {
      debugPrint('[PushService] 重置角标失败: $e');
    }
  }

  /// 获取ClientId
  String? get clientId => _clientId;
  
  /// 获取DeviceToken (iOS)
  String? get deviceToken => _deviceToken;

  /// 检查并请求通知权限 (Android)
  Future<void> _checkAndRequestNotificationPermission() async {
    try {
      // 先检查当前权限状态
      var status = await Permission.notification.status;
      
      if (status.isGranted) {
        debugPrint('[PushService] 通知权限已授予');
        return;
      }
      
      if (status.isDenied) {
        // 主动请求通知权限 (Android 13+)
        debugPrint('[PushService] 请求通知权限...');
        status = await Permission.notification.request();
        
        if (status.isGranted) {
          debugPrint('[PushService] 通知权限已授予');
        } else if (status.isDenied) {
          debugPrint('[PushService] 用户拒绝了通知权限');
        } else if (status.isPermanentlyDenied) {
          debugPrint('[PushService] 用户永久拒绝了通知权限，需要引导到设置页面');
          // 可以引导用户到设置页面
          // await openAppSettings();
        }
      } else if (status.isPermanentlyDenied) {
        debugPrint('[PushService] 通知权限被永久拒绝');
      }
    } catch (e) {
      debugPrint('[PushService] 检查/请求通知权限失败: $e');
    }
  }

  /// 检查通知权限是否已开启 (Android)
  Future<bool> checkNotificationPermission() async {
    if (!_initialized) return false;
    
    try {
      // 自定义插件无直接方法，这里仅依据系统权限返回
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('[PushService] 检查通知权限失败: $e');
      return false;
    }
  }

  /// 打开通知权限设置页面 (Android)
  Future<void> openNotificationSettings() async {
    // 自定义插件无直接方法，这里可以引导到系统设置（如有需要可集成额外插件）
    // await openAppSettings();
  }

  /// 检查集成配置 (Android)
  Future<void> checkManifest() async {
    // 自定义插件不提供该方法
  }

  /// 获取推送服务状态 (Android)
  Future<bool> getPushStatus() async {
    if (!_initialized) return false;
    
    try {
      // 自定义插件不提供该方法，这里返回系统通知权限作为近似
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('[PushService] 获取推送服务状态失败: $e');
      return false;
    }
  }

  /// 释放资源
  void dispose() {
    _messageController.close();
    _notificationArrivedController.close();
    _notificationClickedController.close();
  }
}

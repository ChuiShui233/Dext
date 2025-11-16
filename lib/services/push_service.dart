import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_getui/flutter_getui.dart';
import 'package:permission_handler/permission_handler.dart';

/// 个推推送服务封装
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  bool _isInitialized = false;
  String? _clientId;
  String? _deviceToken;
  
  // 消息回调
  final StreamController<GTMessageModel> _messageController = StreamController<GTMessageModel>.broadcast();
  final StreamController<GTMessageModel> _notificationArrivedController = StreamController<GTMessageModel>.broadcast();
  final StreamController<GTMessageModel> _notificationClickedController = StreamController<GTMessageModel>.broadcast();
  
  Stream<GTMessageModel> get onMessageReceived => _messageController.stream;
  Stream<GTMessageModel> get onNotificationArrived => _notificationArrivedController.stream;
  Stream<GTMessageModel> get onNotificationClicked => _notificationClickedController.stream;

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
    if (_isInitialized) {
      debugPrint('[PushService] 已经初始化，跳过');
      return true;
    }

    try {
      final status = await FlGeTui().init(
        appId: appId,
        appKey: appKey,
        appSecret: appSecret,
      );
      
      _isInitialized = status;
      
      if (status) {
        debugPrint('[PushService] 初始化成功');
        _setupEventHandlers();
        
        // 检查并请求通知权限
        await _checkAndRequestNotificationPermission();
      } else {
        debugPrint('[PushService] 初始化失败');
      }
      
      return status;
    } catch (e) {
      debugPrint('[PushService] 初始化异常: $e');
      return false;
    }
  }

  /// 设置事件监听
  void _setupEventHandlers() {
    FlGeTui().addEventHandler(
      // 在线状态变化
      onReceiveOnlineState: (bool? state) {
        debugPrint('[PushService] Push online status: $state');
      },
      
      // 收到透传消息
      onReceiveMessageData: (GTMessageModel? msg) {
        if (msg != null) {
          debugPrint('[PushService] 收到透传消息: ${msg.toMap()}');
          _messageController.add(msg);
        }
      },
      
      // 通知消息到达
      onNotificationMessageArrived: (GTMessageModel? msg) {
        if (msg != null) {
          debugPrint('[PushService] 通知消息到达: ${msg.toMap()}');
          _notificationArrivedController.add(msg);
        }
      },
      
      // 通知消息点击
      onNotificationMessageClicked: (GTMessageModel? msg) {
        if (msg != null) {
          debugPrint('[PushService] 通知消息点击: ${msg.toMap()}');
          _notificationClickedController.add(msg);
        }
      },
      
      // 获取设备Token (iOS)
      onReceiveDeviceToken: (String? token) {
        _deviceToken = token;
        debugPrint('[PushService] Device Token: $token');
      },
      
      // 设置标签结果
      onSetTagResult: (GTResultModel result) {
        debugPrint('[PushService] 设置标签结果: ${result.toMap()}');
      },
      
      // 绑定别名结果
      onBindAliasResult: (GTResultModel result) {
        debugPrint('[PushService] 绑定别名结果: ${result.toMap()}');
      },
      
      // 解绑别名结果
      onUnBindAliasResult: (GTResultModel result) {
        debugPrint('[PushService] 解绑别名结果: ${result.toMap()}');
      },
    );
  }

  /// 绑定别名 (通常用于绑定用户ID)
  Future<void> bindAlias(String alias, {String? sn}) async {
    if (!_isInitialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      await FlGeTui().bindAlias(alias, sn ?? '');
      debugPrint('[PushService] 绑定别名: $alias');
    } catch (e) {
      debugPrint('[PushService] 绑定别名失败: $e');
    }
  }

  /// 解绑别名
  Future<void> unbindAlias(String alias, {String? sn}) async {
    if (!_isInitialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      await FlGeTui().unbindAlias(alias, sn ?? '');
      debugPrint('[PushService] 解绑别名: $alias');
    } catch (e) {
      debugPrint('[PushService] 解绑别名失败: $e');
    }
  }

  /// 设置标签
  Future<void> setTags(List<String> tags, {String? sn}) async {
    if (!_isInitialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      await FlGeTui().setTag(tags, sn ?? '');
      debugPrint('[PushService] 设置标签: $tags');
    } catch (e) {
      debugPrint('[PushService] 设置标签失败: $e');
    }
  }

  /// 启动推送服务
  Future<void> startPush() async {
    if (!_isInitialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      await FlGeTui().startPush();
      debugPrint('[PushService] 启动推送服务');
    } catch (e) {
      debugPrint('[PushService] 启动推送服务失败: $e');
    }
  }

  /// 停止推送服务
  Future<void> stopPush() async {
    if (!_isInitialized) {
      debugPrint('[PushService] SDK未初始化');
      return;
    }
    
    try {
      await FlGeTui().stopPush();
      debugPrint('[PushService] 停止推送服务');
    } catch (e) {
      debugPrint('[PushService] 停止推送服务失败: $e');
    }
  }

  /// 设置应用角标 (iOS)
  Future<void> setBadge(int badge) async {
    if (!_isInitialized) return;
    
    try {
      await FlGeTui().setBadge(badge);
      debugPrint('[PushService] 设置角标: $badge');
    } catch (e) {
      debugPrint('[PushService] 设置角标失败: $e');
    }
  }

  /// 重置角标 (iOS)
  Future<void> resetBadge() async {
    if (!_isInitialized) return;
    
    try {
      await FlGeTui().resetBadgeWithIOS();
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
      
      // 使用个推的方法再次检查
      final isEnabled = await FlGeTui().checkNotificationsEnabledWithAndroid();
      if (isEnabled != true) {
        debugPrint('[PushService] 个推检测到通知权限未开启');
      }
    } catch (e) {
      debugPrint('[PushService] 检查/请求通知权限失败: $e');
    }
  }

  /// 检查通知权限是否已开启 (Android)
  Future<bool> checkNotificationPermission() async {
    if (!_isInitialized) return false;
    
    try {
      final isEnabled = await FlGeTui().checkNotificationsEnabledWithAndroid();
      return isEnabled;
    } catch (e) {
      debugPrint('[PushService] 检查通知权限失败: $e');
      return false;
    }
  }

  /// 打开通知权限设置页面 (Android)
  Future<void> openNotificationSettings() async {
    if (!_isInitialized) return;
    
    try {
      await FlGeTui().openNotificationWithAndroid();
      debugPrint('[PushService] 打开通知权限设置页面');
    } catch (e) {
      debugPrint('[PushService] 打开通知权限设置失败: $e');
    }
  }

  /// 检查集成配置 (Android)
  Future<void> checkManifest() async {
    if (!_isInitialized) return;
    
    try {
      await FlGeTui().checkManifestWithAndroid();
      debugPrint('[PushService] 检查集成配置');
    } catch (e) {
      debugPrint('[PushService] 检查集成配置失败: $e');
    }
  }

  /// 获取推送服务状态 (Android)
  Future<bool> getPushStatus() async {
    if (!_isInitialized) return false;
    
    try {
      final status = await FlGeTui().getPushStatusWithAndroid();
      return status;
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

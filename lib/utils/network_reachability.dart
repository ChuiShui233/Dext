
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkReachability {
  static final NetworkReachability _instance = NetworkReachability._internal();
  // 私有内部构造函数
  NetworkReachability._internal();
  // 创建 Connectivity 实例
  final Connectivity _connectivity = Connectivity();
  // 用于保存订阅对象，以便在页面销毁时取消监听

  ValueChanged<String>? haveNetBlock;

  // 工厂构造函数，返回单例实例
  factory NetworkReachability() { return _instance; }

  void connectNetworkFunc({ValueChanged<String>? connectNetWorkBlock}) {
    haveNetBlock = connectNetWorkBlock;
    _initConnectivity();
    // 订阅网络状态变化流
  }
  // 获取初始状态
  Future<void> _initConnectivity() async {
    late List<ConnectivityResult> result;
    try {
      result = await _connectivity.checkConnectivity();
    } catch (e) {
      if (kDebugMode) {
        print("Couldn't check connectivity status: $e");
      }
      return;
    }

    _updateConnectionStatus(result);
  }

  // 处理状态更新
  void _updateConnectionStatus(List<ConnectivityResult> result) {
    final isDisconnected = result.contains(ConnectivityResult.none);
    if (isDisconnected) {
      if (kDebugMode) {
        print('网络已断开');
      }
      // 通知无网络状态
      haveNetBlock?.call('none');
    } else {
      if (kDebugMode) {
        print('网络已连接，类型：$result');
      }
      // 通知已连接状态
      haveNetBlock?.call('connected');
    }
  }

}
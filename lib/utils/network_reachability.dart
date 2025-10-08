
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkReachability {
  static final NetworkReachability _instance = NetworkReachability._internal();
  NetworkReachability._internal();
  final Connectivity _connectivity = Connectivity();

  ValueChanged<String>? haveNetBlock;

  factory NetworkReachability() { return _instance; }

  void connectNetworkFunc({ValueChanged<String>? connectNetWorkBlock}) {
    haveNetBlock = connectNetWorkBlock;
    _initConnectivity();
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
      haveNetBlock?.call('none');
    } else {
      if (kDebugMode) {
        print('网络已连接，类型：$result');
      }
      haveNetBlock?.call('connected');
    }
  }

}
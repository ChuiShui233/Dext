import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

/// 隐私政策服务 - 提供统一的隐私政策打开功能
class PrivacyPolicyService {
  /// 打开隐私政策页面
  /// 
  /// [context] - BuildContext，用于显示错误对话框
  /// [onLoading] - 可选的回调函数，在加载状态变化时调用
  /// 
  /// 返回一个Future，表示操作是否成功
  static Future<void> launchPrivacyPolicy({
    required BuildContext context,
    Function(bool isLoading)? onLoading,
  }) async {
    try {
      onLoading?.call(true);
      
      // 从服务端获取隐私政策链接
      final privacyPolicyUrl = await ApiService().getPrivacyPolicyUrl();
      final Uri url = Uri.parse(privacyPolicyUrl);
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (!context.mounted) return;
        _showErrorDialog(context, '无法打开隐私政策页面');
      }
    } catch (e) {
      if (!context.mounted) return;
      _showErrorDialog(context, '获取隐私政策链接失败: ${e.toString()}');
    } finally {
      onLoading?.call(false);
    }
  }
  
  /// 显示错误对话框
  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
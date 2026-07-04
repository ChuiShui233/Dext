/// 统一的错误消息格式化工具
class ErrorFormatter {
  /// 格式化错误消息为用户友好的提示
  static String format(dynamic error) {
    final errorStr = error.toString();
    
    // HandshakeException - SSL/TLS 握手失败
    if (errorStr.contains('HandshakeException') || 
        errorStr.contains('Connection terminated during handshake')) {
      return '服务端维护中，请稍后再试';
    }
    
    // 连接被拒绝
    if (errorStr.contains('Connection refused') || 
        errorStr.contains('Failed to connect')) {
      return '无法连接到服务器，服务端维护中';
    }
    
    // 证书错误
    if (errorStr.contains('CERTIFICATE_VERIFY_FAILED') ||
        errorStr.contains('certificate')) {
      return '服务器证书验证失败，请检查网络环境';
    }
    
    // 超时错误
    if (errorStr.contains('Timeout') || errorStr.contains('超时')) {
      return '请求超时，请检查您的网络连接';
    }
    
    // 网络不可达
    if (errorStr.contains('Network is unreachable') ||
        errorStr.contains('SocketException')) {
      return '网络连接失败，请检查您的网络';
    }
    
    // 401 未授权
    if (errorStr.contains('401') || errorStr.contains('未授权')) {
      return '登录已过期，请重新登录';
    }
    
    // 403 禁止访问
    if (errorStr.contains('403')) {
      return '没有访问权限';
    }
    
    // 404 未找到
    if (errorStr.contains('404')) {
      return '请求的资源不存在';
    }
    
    // 500 服务器错误
    if (errorStr.contains('500')) {
      return '服务器内部错误';
    }
    
    // 默认错误消息
    return errorStr;
  }
}

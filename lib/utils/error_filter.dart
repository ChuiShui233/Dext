/// 错误过滤工具类，用于过滤不需要显示的日志信息
class ErrorFilter {
  /// 判断是否应该过滤掉该错误消息
  static bool shouldFilter(String message) {
    // 过滤AccessibilityBridge相关日志
    if (message.contains('AccessibilityBridge') ||
        message.contains('Scroll index is out of bounds') ||
        message.contains('E/AccessibilityBridge') ||
        message.contains('!semantics.parentDataDirty')) {
      return true;
    }
    
    // 过滤高通/厂商图形驱动的无害告警
    if (message.contains('qdgralloc') ||
        message.contains('OplusViewDragTouchViewHelper') ||
        message.contains('ViewRootImplExtImpl')) {
      return true;
    }
    
    // 过滤网络连接错误
    if (message.contains('SocketException') ||
        message.contains('Connection refused')) {
      return true;
    }
    
    return false;
  }
  
  /// 判断是否应该过滤掉该异常
  static bool shouldFilterException(Object exception) {
    final errorMessage = exception.toString();
    
    // 过滤网络连接错误
    if (errorMessage.contains('SocketException') ||
        errorMessage.contains('Connection refused')) {
      return true;
    }
    
    // 过滤AccessibilityBridge错误日志
    if (errorMessage.contains('AccessibilityBridge') ||
        errorMessage.contains('Scroll index is out of bounds') ||
        errorMessage.contains('!semantics.parentDataDirty')) {
      return true;
    }
    
    return false;
  }
  
  /// 判断是否应该过滤掉该错误对象
  static bool shouldFilterError(Object error) {
    final errorString = error.toString();
    
    // 过滤网络连接错误
    if (errorString.contains('SocketException') ||
        errorString.contains('Connection refused')) {
      return true;
    }
    
    // 过滤AccessibilityBridge错误日志
    if (errorString.contains('AccessibilityBridge') ||
        errorString.contains('Scroll index is out of bounds') ||
        errorString.contains('!semantics.parentDataDirty')) {
      return true;
    }
    
    return false;
  }
}
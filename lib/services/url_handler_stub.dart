import 'dart:developer' as developer;

/// 非Web平台的URL参数获取存根实现
String? getWebUrlParameterImpl(String paramName) {
  developer.log('非Web平台不支持URL参数获取');
  return null;
}

import 'dart:html' as html;
import 'dart:developer' as developer;

/// Web平台URL参数获取的具体实现
String? getWebUrlParameterImpl(String paramName) {
  try {
    final windowLocation = html.window.location;
    final search = windowLocation.search;
    developer.log('URL调试: window.location.search = $search');
    developer.log('URL调试: 完整URL = ${windowLocation.href}');
    
    if (search != null && search.isNotEmpty) {
      final params = Uri.splitQueryString(search.substring(1));
      developer.log('URL调试: 解析的参数 = $params');
      final result = params[paramName];
      developer.log('URL调试: 参数[$paramName] = $result');
      return result;
    } else {
      developer.log('URL调试: search为空或null');
    }
    return null;
  } catch (e) {
    developer.log('Web URL参数获取实现失败: $e');
    return null;
  }
}

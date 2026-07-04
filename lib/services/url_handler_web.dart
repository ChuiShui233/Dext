// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

/// Web平台URL参数获取的具体实现
String? getWebUrlParameterImpl(String paramName) {
  try {
    final windowLocation = web.window.location;
    final search = windowLocation.search;
    
    if (search.isNotEmpty) {
      final params = Uri.splitQueryString(search.substring(1));
      final result = params[paramName];
      return result;
    }
    return null;
  } catch (e) {
    return null;
  }
}

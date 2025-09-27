/// 通用时间格式化工具
/// 统一输出格式：YYYY-MM-DD HH:MM:SS（本地时区）
library;

class DateFormatUtils {
  /// 将 DateTime 按本地时间格式化为 "YYYY-MM-DD HH:MM:SS"
  static String formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  /// 将 ISO8601 或普通字符串时间格式化为 "YYYY-MM-DD HH:MM:SS"
  static String formatIsoString(String s) {
    if (s.isEmpty) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      return formatDateTime(dt);
    } catch (_) {
      // 简单兜底：去掉中间的 'T'，移除末尾的时区偏移或 'Z'，并去掉毫秒
      var t = s.replaceFirst('T', ' ');
      if (t.endsWith('Z')) t = t.substring(0, t.length - 1);
      // 去掉末尾的时区偏移，例如 +08:00 或 -03:00
      final plus = t.lastIndexOf('+');
      final minus = t.lastIndexOf('-');
      int cut = -1;
      if (plus > 10) cut = plus; // 防止匹配到日期里的减号
      if (minus > 10) cut = cut == -1 ? minus : (minus < cut ? minus : cut);
      if (cut != -1) t = t.substring(0, cut);
      // 去掉小数秒
      final dot = t.indexOf('.');
      if (dot != -1) t = t.substring(0, dot);
      return t.trim();
    }
  }
}

library;

class DateFormatUtils {
  static String formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String formatIsoString(String s) {
    if (s.isEmpty) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      return formatDateTime(dt);
    } catch (_) {
      var t = s.replaceFirst('T', ' ');
      if (t.endsWith('Z')) t = t.substring(0, t.length - 1);
      final plus = t.lastIndexOf('+');
      final minus = t.lastIndexOf('-');
      int cut = -1;
      if (plus > 10) cut = plus;
      if (minus > 10) cut = cut == -1 ? minus : (minus < cut ? minus : cut);
      if (cut != -1) t = t.substring(0, cut);
      final dot = t.indexOf('.');
      if (dot != -1) t = t.substring(0, dot);
      return t.trim();
    }
  }
}

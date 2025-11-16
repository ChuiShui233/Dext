import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  Future<void> clearCache({String? specificKey}) async {
    final prefs = await SharedPreferences.getInstance();
    if (specificKey != null) {
      await prefs.remove(specificKey);
    } else {
      await prefs.remove('projects_cache');
      await prefs.remove('surveys_cache');
      await prefs.remove('survey_stats_cache');
      await prefs.remove('recent_submissions');
      await prefs.remove('analytics_overview');
      for (int i = 0; i < 1000; i++) {
        await prefs.remove('questions_cache_$i');
        await prefs.remove('survey_results_cache_$i');
      }
    }
  }

  Future<void> clearAllCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.contains('cache') || key.contains('submit_trend') || key.contains('submissions')) {
        await prefs.remove(key);
      }
    }
  }
}

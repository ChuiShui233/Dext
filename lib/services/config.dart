// Centralized API configuration
// Update the base URL here and all services will use it.

const String apiBaseUrl = 'https://wucode.xyz:11222';

// ===== 域名配置 =====
const String appDomain = 'dext.wucode.xyz';
const String appDomainUrl = 'https://dext.wucode.xyz';

// ===== OAuth 配置 =====
// Google OAuth
const String googleClientId = '1098222292927-26rbvt32p9kfu8bvin8btapknj5qomhk.apps.googleusercontent.com';
const String googleClientSecret = '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';

// GitHub OAuth
const String githubClientId = 'Ov23linQUMRmORjFIiXr';
const String githubClientSecret = '651a67daf9829ba701ca1058344acb0171375b2f';

// Microsoft OAuth
const String microsoftClientId = '6358d1bc-76bd-4340-951b-b250570209d9';
const String microsoftClientSecret = 'tVE8Q~4Ela3vsIQ8QzmJ4ocz5ZfvCbUOWaY~_chm';

// ===== OAuth 重定向URI配置 =====
const String oauthCallbackWeb = 'https://wucode.xyz/oauth/callback';
const String oauthCallbackAndroid = 'com.dext.app://oauth/callback';
const String oauthCallbackIOS = 'dext://oauth/callback';
const String oauthCallbackDesktop = 'http://localhost:8080/oauth/callback';

// ===== Android/iOS URI Scheme =====
const String uriSchemeAndroid = 'com.dext.app';
const String uriSchemeIOS = 'dext';

/// 将相对路径（/openassets/...）转换为绝对URL，便于移动端/桌面端使用
String toAbsoluteUrl(String? pathOrUrl) {
  final p = pathOrUrl?.trim() ?? '';
  if (p.isEmpty) return p;
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  if (p.startsWith('/')) {
    return apiBaseUrl.endsWith('/') ? '${apiBaseUrl.substring(0, apiBaseUrl.length - 1)}$p' : '$apiBaseUrl$p';
  }
  // 其他情况（如意外的相对路径），尝试拼接
  return apiBaseUrl.endsWith('/') ? '$apiBaseUrl$p' : '$apiBaseUrl/$p';
}

/// 构建公开问卷链接
String buildPublicSurveyUrl(String surveyUid) {
  return '$appDomainUrl/?id=$surveyUid';
}

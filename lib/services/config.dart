// Centralized API configuration
// Update the base URL here and all services will use it.

const String apiBaseUrl = 'https://wucode.xyz:11222';

// ===== 域名配置 =====
const String appDomain = 'dext.wucode.xyz';
const String appDomainUrl = 'https://dext.wucode.xyz';

// ===== OAuth 配置 =====
// 注意：前端只保留Client ID用于原生平台OAuth，Web端完全由后端处理
// Google OAuth
const String googleClientId = '1098222292927-26rbvt32p9kfu8bvin8btapknj5qomhk.apps.googleusercontent.com';

// GitHub OAuth
const String githubClientId = 'Ov23linQUMRmORjFIiXr';

// Microsoft OAuth
const String microsoftClientId = '6358d1bc-76bd-4340-951b-b250570209d9';

// ===== OAuth 重定向URI配置 =====
const String oauthCallbackWeb = 'https://dext.wucode.xyz/oauth_callback.html';
const String oauthCallbackAndroid = 'com.dext.app://oauth/callback';
const String oauthCallbackIOS = 'dext://oauth/callback';
const String oauthCallbackDesktop = 'http://wucode.xyz:11222/oauth/callback';

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

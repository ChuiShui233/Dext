// Centralized API configuration
// Update the base URL here and all services will use it.

const String apiBaseUrl = 'https://wucode.xyz:11222';

// ===== 域名配置 =====
const String appDomain = 'dext.wucode.xyz';
const String appDomainUrl = 'https://dext.wucode.xyz';

// ===== OAuth 配置 =====
// Google OAuth
// 默认填入 Client ID，便于本地/桌面直接运行；生产可用 --dart-define 覆盖
const String googleClientId = String.fromEnvironment(
  'GOOGLE_CLIENT_ID',
  defaultValue: '1098222292927-26rbvt32p9kfu8bvin8btapknj5qomhk.apps.googleusercontent.com',
);
const String googleClientSecret = String.fromEnvironment(
  'GOOGLE_CLIENT_SECRET',
  defaultValue: '',
);

// GitHub OAuth
const String githubClientId = String.fromEnvironment(
  'GITHUB_CLIENT_ID',
  defaultValue: 'Ov23linQUMRmORjFIiXr',
);
const String githubClientSecret = String.fromEnvironment(
  'GITHUB_CLIENT_SECRET',
  defaultValue: '',
);

// Microsoft OAuth
const String microsoftClientId = String.fromEnvironment(
  'MS_CLIENT_ID',
  defaultValue: '6358d1bc-76bd-4340-951b-b250570209d9',
);
const String microsoftClientSecret = String.fromEnvironment(
  'MS_CLIENT_SECRET',
  defaultValue: '',
);

// ===== OAuth 重定向URI配置 =====
const String oauthCallbackWeb = 'https://dext.wucode.xyz/oauth/callback';
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

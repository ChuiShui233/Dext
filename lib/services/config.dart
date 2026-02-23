// Centralized API configuration
// Update the base URL here and all services will use it.

const String apiBaseUrl = 'https://chuishui.top:11222';

// ===== 域名配置 =====
const String appDomain = 'qs.chuishui.top';
const String appDomainUrl = 'https://qs.chuishui.top';

// ===== OAuth 配置 =====
const String googleClientId = '339404388031-krfjaiki8nade0j3a7thgcrca10claqa.apps.googleusercontent.com';

// GitHub OAuth
const String githubClientId = 'Ov23linQUMRmORjFIiXr';

// Microsoft OAuth
const String microsoftClientId = 'a936dc9c-08e4-44c6-acb5-6aa0548e5199';

// ===== 个推SDK配置 =====
const String getuiAppId = 'cy0d7CICux7YKvteM5cy87';
const String getuiAppKey = '你的个推AppKey';  // 从个推控制台获取
const String getuiAppSecret = '你的个推AppSecret';  // 从个推控制台获取

// ===== OAuth 重定向URI配置 =====
const String oauthCallbackWeb = 'https://chuishui.top:11222/api/auth/oauth/callback/web';
const String oauthCallbackAndroid = 'https://chuishui.top:11222/api/auth/oauth/callback/mobile';
const String oauthCallbackIOS = 'https://chuishui.top:11222/api/auth/oauth/callback/mobile';
const String oauthCallbackDesktop = 'https://chuishui.top:11222/api/auth/oauth/callback/desktop';

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

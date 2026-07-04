// Centralized API configuration
// Update the base URL here and all services will use it.
// 示例网址记得删掉...

import 'package:flutter/foundation.dart';

const String _releaseApiBaseUrl = 'https://csmy-dext.hf.space';
const String _debugApiBaseUrl = 'http://127.0.0.1:11222';

final String apiBaseUrl = kReleaseMode ? _releaseApiBaseUrl : _debugApiBaseUrl;

// ===== 域名配置 =====
const String appDomain = 'qs.chuishui.top';
const String appDomainUrl = 'https://qs.chuishui.top';

// ===== OAuth 配置 =====
// Google OAuth
const String googleClientId = '/';

// GitHub OAuth
const String githubClientId = '/';

// Microsoft OAuth
const String microsoftClientId = '/';

// ===== getuiSDK =====
const String getuiAppId = 'ID';
const String getuiAppKey = 'AppKey';
const String getuiAppSecret = 'AppSecret';

// ===== OAuth callback =====
const String oauthCallbackWeb = 'https://csmy-dext.hf.space/api/auth/oauth/callback/web';
const String oauthCallbackAndroid = 'https://csmy-dext.hf.space/api/auth/oauth/callback/mobile';
const String oauthCallbackIOS = 'https://csmy-dext.hf.space/api/auth/oauth/callback/mobile';
const String oauthCallbackDesktop = 'https://csmy-dext.hf.space/api/auth/oauth/callback/desktop';

// ===== Android/iOS URI Scheme =====
const String uriSchemeAndroid = 'dext';
const String uriSchemeIOS = 'dext';

String toAbsoluteUrl(String? pathOrUrl) {
  final p = pathOrUrl?.trim() ?? '';
  if (p.isEmpty) return p;
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  if (p.startsWith('/')) {
    return apiBaseUrl.endsWith('/') ? '${apiBaseUrl.substring(0, apiBaseUrl.length - 1)}$p' : '$apiBaseUrl$p';
  }
  return apiBaseUrl.endsWith('/') ? '$apiBaseUrl$p' : '$apiBaseUrl/$p';
}
/// 拼写公开问卷链接
String buildPublicSurveyUrl(String surveyUid) {
  return '$appDomainUrl/?id=$surveyUid';
}

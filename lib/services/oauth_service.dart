import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/google_oauth2_client.dart';
import 'package:oauth2_client/github_oauth2_client.dart';
import 'api_service.dart';
import 'config.dart';
import 'uri_handler_service.dart';
import 'web_oauth_handler.dart' if (dart.library.io) 'web_oauth_handler_stub.dart';

class OAuthService {
  static String get _customUriScheme {
    if (kIsWeb) {
      return 'https';
    } else if (Platform.isAndroid) {
      return uriSchemeAndroid;
    } else if (Platform.isIOS) {
      return uriSchemeIOS;
    } else {
      return 'dext';
    }
  }

  static String get _redirectUri {
    if (kIsWeb) {
      return oauthCallbackWeb;
    } else if (Platform.isAndroid) {
      return oauthCallbackAndroid;
    } else if (Platform.isIOS) {
      return oauthCallbackIOS;
    } else {
      return oauthCallbackDesktop;
    }
  }

  String get redirectUri => _redirectUri;

  Future<String?> getAuthorizationCode(String provider) async {
    try {
      if (kIsWeb) {
        return await _getAuthorizationCodeWeb(provider);
      } else {
        return await _getAuthorizationCodeDesktop(provider);
      }
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getAuthorizationCodeWeb(String provider) async {
    final authUrlResponse = await ApiService().encryptedRequest(
      'POST',
      '${ApiService.baseUrl}/api/auth/oauth/$provider/url',
      {'redirect_uri': _redirectUri},
    );

    if (authUrlResponse.statusCode != 200) {
      throw Exception('获取授权URL失败: ${authUrlResponse.statusCode}');
    }

    final payload = json.decode(authUrlResponse.body);
    final authUrl = payload['auth_url'];

    final authCode = await WebOAuthHandler.authenticate(
      authUrl: authUrl,
      redirectUrl: _redirectUri,
      windowOptions: {
        'width': '500',
        'height': '700',
      },
      timeoutSeconds: 300,
    );

    final uri = Uri.parse(authCode);
    return uri.queryParameters['code'];
  }

  Future<String?> _getAuthorizationCodeDesktop(String provider) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return await _getAuthorizationCodeMobile(provider);
    }

    final state = UriHandlerService.generateState();

    String authUrl;
    switch (provider) {
      case 'google':
        authUrl = _buildGoogleAuthUrl(state);
        break;
      case 'github':
        authUrl = _buildGitHubAuthUrl(state);
        break;
      case 'microsoft':
        authUrl = _buildMicrosoftAuthUrl(state);
        break;
      default:
        throw Exception('不支持的OAuth提供商: $provider');
    }

    final callback = await UriHandlerService.launchOAuthAndWaitForCallback(
      authUrl: authUrl,
      state: state,
    );

    return callback['code'];
  }

  Future<String?> _getAuthorizationCodeMobile(String provider) async {
    try {
      final state = UriHandlerService.generateState();
      final authUrl = _buildMobileAuthUrl(provider, state: state);
      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: _customUriScheme,
      );
      final uri = Uri.parse(callbackUrl);
      final error = uri.queryParameters['error'];
      if (error != null && error.isNotEmpty) {
        final errorDescription = uri.queryParameters['error_description'];
        throw Exception('OAuth error: $error${errorDescription != null ? ' - $errorDescription' : ''}');
      }

      final returnedState = uri.queryParameters['state'];
      // redirect_uri 可能先落到后端，再由后端重定向回 App；部分实现可能不会把 state 透传回来。
      // 这里保持兼容：只有在返回了 state 且不匹配时才报错。
      if (returnedState != null && returnedState != state) {
        throw Exception('OAuth state mismatch');
      }

      final code = uri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw Exception('未获取到授权码');
      }
      return code;
    } catch (e) {
      if (e.toString().contains('cancelled') || e.toString().contains('cancel')) {
        return null;
      }
      rethrow;
    }
  }

  String _buildMobileAuthUrl(String provider, {required String state}) {
    switch (provider) {
      case 'google':
        final params = {
          'client_id': googleClientId,
          'response_type': 'code',
          'redirect_uri': _redirectUri,
          'scope': 'openid profile email',
          'state': state,
        };
        return 'https://accounts.google.com/o/oauth2/v2/auth?${_buildQueryString(params)}';
      case 'github':
        final params = {
          'client_id': githubClientId,
          'redirect_uri': _redirectUri,
          'scope': 'user:email',
          'state': state,
        };
        return 'https://github.com/login/oauth/authorize?${_buildQueryString(params)}';
      case 'microsoft':
        final params = {
          'client_id': microsoftClientId,
          'response_type': 'code',
          'redirect_uri': _redirectUri,
          'scope': 'openid profile email User.Read',
          'response_mode': 'query',
          'state': state,
        };
        return 'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize?${_buildQueryString(params)}';
      default:
        throw Exception('不支持的OAuth提供商: $provider');
    }
  }

  Future<Map<String, dynamic>> _signInWithProviderMobileViaBackend(String provider) async {
    final authorizationCode = await _getAuthorizationCodeMobile(provider);
    if (authorizationCode == null || authorizationCode.isEmpty) {
      return {
        'success': false,
        'error': '登录已取消',
        'cancelled': true,
      };
    }

    final result = await _authenticateWithBackend(provider, {
      'authorization_code': authorizationCode,
      'redirect_uri': _redirectUri,
    });

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
  }

  String _buildQueryString(Map<String, String> params) {
    return params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
  }





  String _buildMicrosoftAuthUrl(String state) {
    final authParams = {
      'client_id': microsoftClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'openid profile email User.Read',
      'state': state,
      'response_mode': 'query',
    };
    return Uri.https(
      'login.microsoftonline.com',
      '/consumers/oauth2/v2.0/authorize',
      authParams,
    ).toString();
  }

  String _buildGoogleAuthUrl(String state) {
    final authParams = {
      'client_id': googleClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'openid profile email',
      'state': state,
    };
    return Uri.https(
      'accounts.google.com',
      '/o/oauth2/v2/auth',
      authParams,
    ).toString();
  }

  String _buildGitHubAuthUrl(String state) {
    final authParams = {
      'client_id': githubClientId,
      'redirect_uri': _redirectUri,
      'scope': 'user:email',
      'state': state,
    };
    return Uri.https(
      'github.com',
      '/login/oauth/authorize',
      authParams,
    ).toString();
  }

  Future<Map<String, dynamic>> signInWithMicrosoft() async {
    if (microsoftClientId.isEmpty || microsoftClientId == 'YOUR_MICROSOFT_CLIENT_ID') {
      return {
        'success': false,
        'error': 'Microsoft OAuth 未配置（缺少 client_id）',
      };
    }
    try {
      if (kIsWeb) {
        return await _signInWithMicrosoftWeb();
      } else {
        return await _signInWithMicrosoftNative();
      }
    } catch (e) {
      if (e is OAuthWindowClosedException) {
        return {
          'success': false,
          'error': '登录已取消',
          'cancelled': true,
        };
      } else if (e is OAuthTimeoutException) {
        return {
          'success': false,
          'error': '登录超时，请重试',
          'timeout': true,
        };
      }
      return {
        'success': false,
        'error': 'Microsoft登录失败: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> _signInWithMicrosoftWeb() async {
    final authUrlResponse = await ApiService().encryptedRequest(
      'GET',
      '${ApiService.baseUrl}/api/auth/oauth/microsoft/url?redirect_uri=${Uri.encodeComponent(_redirectUri)}',
      null,
    );

    if (authUrlResponse.statusCode != 200) {
      throw Exception('获取授权URL失败: ${authUrlResponse.statusCode}');
    }

    final payload = json.decode(authUrlResponse.body);
    final authUrl = payload['auth_url'];

    final authCode = await WebOAuthHandler.authenticate(
      authUrl: authUrl,
      redirectUrl: _redirectUri,
      windowOptions: {
        'width': '500',
        'height': '700',
      },
      timeoutSeconds: 300,
    );

    final uri = Uri.parse(authCode);
    final code = uri.queryParameters['code'];
    if (code == null) {
      throw Exception('未获取到授权码');
    }

    final result = await _authenticateWithBackend('microsoft', {
      'authorization_code': code,
      'redirect_uri': _redirectUri,
    });

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
  }

  Future<Map<String, dynamic>> _signInWithMicrosoftDesktop() async {

    try {
      final state = UriHandlerService.generateState();

      final authParams = {
        'client_id': microsoftClientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'scope': 'openid profile email User.Read',
        'state': state,
        'response_mode': 'query',
      };

      final authUrl = Uri.https(
        'login.microsoftonline.com',
        '/consumers/oauth2/v2.0/authorize',
        authParams,
      ).toString();

      final callback = await UriHandlerService.launchOAuthAndWaitForCallback(
        authUrl: authUrl,
        state: state,
      );

      final authCode = callback['code'];
      if (authCode == null || authCode.isEmpty) {
        throw Exception('未收到授权码');
      }


      final backendAuth = await _authenticateWithBackend('microsoft', {
        'authorization_code': authCode,
        'redirect_uri': _redirectUri,
      });

      return {
        'success': true,
        'token': backendAuth['token'],
        'expires': backendAuth['expires'],
        'user': backendAuth['user'],
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _signInWithMicrosoftNative() async {
    if (!kIsWeb && Platform.isWindows) {
      return await _signInWithMicrosoftDesktop();
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // Mobile 端统一走“授权码 -> 后端换取并登录”，避免各 Provider 对 client_secret/PKCE 的差异导致失败。
      return await _signInWithProviderMobileViaBackend('microsoft');
    }

    final client = OAuth2Client(
      authorizeUrl: 'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize',
      tokenUrl: 'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
      redirectUri: _redirectUri,
      customUriScheme: _customUriScheme,
    );


    final helper = OAuth2Helper(
      client,
      grantType: OAuth2Helper.authorizationCode,
      clientId: microsoftClientId,
      scopes: ['openid', 'profile', 'email', 'User.Read'],
      webAuthOpts: {
        'useWebview': true,
        'timeout': 300,
      },
    );

    final response = await helper.get('https://graph.microsoft.com/v1.0/me');
    
    if (response.statusCode == 200) {
      final userInfo = json.decode(response.body);
      final accessToken = await helper.getToken();
      
      final backendResult = await _authenticateWithBackend('microsoft', {
        'access_token': accessToken.accessToken,
        'user_info': {
          'id': userInfo['id'],
          'email': userInfo['mail'] ?? userInfo['userPrincipalName'],
          'name': userInfo['displayName'],
          'picture': null,
          'provider': 'microsoft',
        },
      });

      return {
        'success': true,
        'token': backendResult['token'],
        'expires': backendResult['expires'],
        'user': userInfo,
      };
    } else {
      throw Exception('获取用户信息失败: ${response.statusCode}');
    }
  }

  /// Google OAuth2 登录
  Future<Map<String, dynamic>> signInWithGoogle() async {
    if (googleClientId.isEmpty || googleClientId == 'YOUR_GOOGLE_CLIENT_ID') {
      return {
        'success': false,
        'error': 'Google OAuth 未配置（缺少 client_id）',
      };
    }
    try {
      if (kIsWeb) {
        return await _signInWithGoogleWeb();
      } else {
        return await _signInWithGoogleNative();
      }
    } catch (e) {
      if (e is OAuthWindowClosedException) {
        return {
          'success': false,
          'error': '登录已取消',
          'cancelled': true,
        };
      } else if (e is OAuthTimeoutException) {
        return {
          'success': false,
          'error': '登录超时，请重试',
          'timeout': true,
        };
      }
      return {
        'success': false,
        'error': 'Google登录失败: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> _signInWithGoogleWeb() async {
    final authUrlResponse = await ApiService().encryptedRequest(
      'POST',
      '${ApiService.baseUrl}/api/auth/oauth/google/url',
      {'redirect_uri': _redirectUri},
    );

    if (authUrlResponse.statusCode != 200) {
      throw Exception('获取授权URL失败: ${authUrlResponse.statusCode}');
    }

    final payload = json.decode(authUrlResponse.body);
    final authUrl = payload['auth_url'];

    // 使用自定义处理器打开OAuth窗口
    final authCode = await WebOAuthHandler.authenticate(
      authUrl: authUrl,
      redirectUrl: _redirectUri,
      windowOptions: {
        'width': '500',
        'height': '700',
      },
      timeoutSeconds: 300,
    );

    // 解析授权码
    final uri = Uri.parse(authCode);
    final code = uri.queryParameters['code'];
    if (code == null) {
      throw Exception('未获取到授权码');
    }

    final result = await _authenticateWithBackend('google', {
      'authorization_code': code,
      'redirect_uri': _redirectUri,
    });

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
  }

  Future<Map<String, dynamic>> _signInWithGoogleDesktop() async {
    try {
      final state = UriHandlerService.generateState();
      
      // 构建授权URL
      final authParams = {
        'client_id': googleClientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'scope': 'openid profile email',
        'state': state,
        'access_type': 'offline',
      };
      
      final authUrl = Uri.https(
        'accounts.google.com',
        '/o/oauth2/v2/auth',
        authParams,
      ).toString();
      
      // 启动OAuth流程并等待回调
      final callback = await UriHandlerService.launchOAuthAndWaitForCallback(
        authUrl: authUrl,
        state: state,
      );
      
      final authCode = callback['code'];
      if (authCode == null || authCode.isEmpty) {
        throw Exception('未收到授权码');
      }
      
      debugPrint('✅ 收到Google授权码，发送给后端处理');
      final backendAuth = await _authenticateWithBackend('google', {
        'authorization_code': authCode,
        'redirect_uri': _redirectUri,
      });
      
      return {
        'success': true,
        'token': backendAuth['token'],
        'expires': backendAuth['expires'],
        'user': backendAuth['user'],
      };
    } catch (e) {
      debugPrint('❌ Google桌面端登录失败: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _signInWithGoogleNative() async {
    if (!kIsWeb && Platform.isWindows) {
      return await _signInWithGoogleDesktop();
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return await _signInWithProviderMobileViaBackend('google');
    }

    final client = GoogleOAuth2Client(
      redirectUri: _redirectUri,
      customUriScheme: _customUriScheme,
    );


    final helper = OAuth2Helper(
      client,
      grantType: OAuth2Helper.authorizationCode,
      clientId: googleClientId,
      scopes: ['openid', 'profile', 'email'],
      webAuthOpts: {
        'windowName': 'Dext - Google登录',
        'windowTitle': 'Dext - Google登录',
        'useWebview': false,
        'timeout': 300,
      },
    );

    final accessToken = await helper.getToken();
    if (accessToken.accessToken == null) {
      throw Exception('获取访问令牌失败');
    }
    
    final response = await helper.get('https://www.googleapis.com/oauth2/v2/userinfo');
    
    if (response.statusCode == 200) {
      final userInfo = json.decode(response.body);
      
      final backendResult = await _authenticateWithBackend('google', {
        'access_token': accessToken.accessToken,
        'user_info': {
          'id': userInfo['id'],
          'email': userInfo['email'],
          'name': userInfo['name'],
          'picture': userInfo['picture'],
          'provider': 'google',
        },
      });

      return {
        'success': true,
        'token': backendResult['token'],
        'expires': backendResult['expires'],
        'user': userInfo,
      };
    } else {
      throw Exception('获取用户信息失败: ${response.statusCode}');
    }
  }

  /// GitHub OAuth2 登录
  Future<Map<String, dynamic>> signInWithGitHub() async {
    if (githubClientId.isEmpty || githubClientId == 'YOUR_GITHUB_CLIENT_ID') {
      return {
        'success': false,
        'error': 'GitHub OAuth 未配置（缺少 client_id）',
      };
    }
    try {
      if (kIsWeb) {
        return await _signInWithGitHubWeb();
      } else {
        return await _signInWithGitHubNative();
      }
    } catch (e) {
      if (e is OAuthWindowClosedException) {
        return {
          'success': false,
          'error': '登录已取消',
          'cancelled': true,
        };
      } else if (e is OAuthTimeoutException) {
        return {
          'success': false,
          'error': '登录超时，请重试',
          'timeout': true,
        };
      }
      return {
        'success': false,
        'error': 'GitHub登录失败: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> _signInWithGitHubWeb() async {
    final authUrlResponse = await ApiService().encryptedRequest(
      'GET',
      '${ApiService.baseUrl}/api/auth/oauth/github/url?redirect_uri=${Uri.encodeComponent(_redirectUri)}',
      null,
    );

    if (authUrlResponse.statusCode != 200) {
      throw Exception('获取授权URL失败: ${authUrlResponse.statusCode}');
    }

    final authUrlData = json.decode(authUrlResponse.body);
    final authUrl = authUrlData['auth_url'];

    // 使用自定义处理器打开OAuth窗口
    final authCode = await WebOAuthHandler.authenticate(
      authUrl: authUrl,
      redirectUrl: _redirectUri,
      windowOptions: {
        'width': '500',
        'height': '700',
      },
      timeoutSeconds: 300,
    );

    // 解析授权码
    final uri = Uri.parse(authCode);
    final code = uri.queryParameters['code'];
    if (code == null) {
      throw Exception('未获取到授权码');
    }

    final result = await _authenticateWithBackend('github', {
      'authorization_code': code,
      'redirect_uri': _redirectUri,
    });

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
  }

  Future<Map<String, dynamic>> _signInWithGitHubDesktop() async {
    try {
      final state = UriHandlerService.generateState();
      
      // 构建授权URL
      final authParams = {
        'client_id': githubClientId,
        'redirect_uri': _redirectUri,
        'scope': 'user:email',
        'state': state,
      };
      
      final authUrl = Uri.https(
        'github.com',
        '/login/oauth/authorize',
        authParams,
      ).toString();
      
      // 启动OAuth流程并等待回调
      final callback = await UriHandlerService.launchOAuthAndWaitForCallback(
        authUrl: authUrl,
        state: state,
      );
      
      final authCode = callback['code'];
      if (authCode == null || authCode.isEmpty) {
        throw Exception('未收到授权码');
      }
      
      final backendAuth = await _authenticateWithBackend('github', {
        'authorization_code': authCode,
        'redirect_uri': _redirectUri,
      });
      
      return {
        'success': true,
        'token': backendAuth['token'],
        'expires': backendAuth['expires'],
        'user': backendAuth['user'],
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _signInWithGitHubNative() async {
    if (!kIsWeb && Platform.isWindows) {
      return await _signInWithGitHubDesktop();
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return await _signInWithProviderMobileViaBackend('github');
    }

    final client = GitHubOAuth2Client(
      redirectUri: _redirectUri,
      customUriScheme: _customUriScheme,
    );


    final helper = OAuth2Helper(
      client,
      grantType: OAuth2Helper.authorizationCode,
      clientId: githubClientId,
      scopes: ['user:email'],
      webAuthOpts: {
        'windowName': 'Dext - GitHub登录',
        'windowTitle': 'Dext - GitHub登录',
        'useWebview': false,
        'timeout': 300,
      },
    );

    final userResponse = await helper.get('https://api.github.com/user');
    
    if (userResponse.statusCode == 200) {
      final userInfo = json.decode(userResponse.body);
      final accessToken = await helper.getToken();
      
      String? email = userInfo['email'];
      if (email == null || email.isEmpty) {
        final emailResponse = await helper.get('https://api.github.com/user/emails');
        if (emailResponse.statusCode == 200) {
          final emails = json.decode(emailResponse.body) as List;
          final primaryEmail = emails.firstWhere(
            (e) => e['primary'] == true,
            orElse: () => emails.isNotEmpty ? emails.first : null,
          );
          email = primaryEmail?['email'];
        }
      }

      final userInfoFormatted = {
        'id': userInfo['id'].toString(),
        'email': email ?? '',
        'name': userInfo['name'] ?? userInfo['login'],
        'picture': userInfo['avatar_url'],
        'username': userInfo['login'],
        'provider': 'github',
      };
      
      final backendResult = await _authenticateWithBackend('github', {
        'access_token': accessToken.accessToken,
        'user_info': userInfoFormatted,
      });

      return {
        'success': true,
        'token': backendResult['token'],
        'expires': backendResult['expires'],
        'user': userInfoFormatted,
      };
    } else {
      throw Exception('获取用户信息失败: ${userResponse.statusCode}');
    }
  }


  /// 与后端进行OAuth认证
  Future<Map<String, dynamic>> _authenticateWithBackend(
    String provider,
    Map<String, dynamic> oauthData,
  ) async {
    try {
      // 使用ApiService的加密请求方法
      final requestData = {
        'provider': provider,
        'oauth_data': oauthData,
      };

      final response = await ApiService().encryptedRequest(
        'POST',
        '${ApiService.baseUrl}/api/auth/oauth',
        requestData,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'token': data['token'],
          'expires': DateTime.parse(data['expires']),
          'user': data['user'],
        };
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? '后端认证失败');
      }
    } catch (e) {
      throw Exception('后端认证失败: ${e.toString()}');
    }
  }

  /// 交换授权码获取Provider原始access_token（用于绑定已有账号，不创建用户）
  Future<Map<String, dynamic>> exchangeCodeForBinding(
    String provider, {
    required String authorizationCode,
    required String redirectUri,
  }) async {
    try {
      final requestData = {
        'provider': provider,
        'oauth_data': {
          'authorization_code': authorizationCode,
          'redirect_uri': redirectUri,
        },
      };

      final response = await ApiService(authToken: '').encryptedRequest(
        'POST',
        '${ApiService.baseUrl}/api/oauth/exchange-code-for-binding',
        requestData,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'provider_access_token': data['provider_access_token'],
          'provider_user_id': data['provider_user_id'],
          'provider_email': data['provider_email'],
          'provider_username': data['provider_username'],
          'provider_name': data['provider_name'],
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? '交换授权码失败',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': '交换授权码失败: ${e.toString()}',
      };
    }
  }

  /// 检查OAuth配置是否完整
  static bool isConfigured() {
    return googleClientId != 'YOUR_GOOGLE_CLIENT_ID' &&
           githubClientId != 'YOUR_GITHUB_CLIENT_ID' &&
           microsoftClientId != 'YOUR_MICROSOFT_CLIENT_ID';
  }
}

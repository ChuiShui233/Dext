import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/google_oauth2_client.dart';
import 'package:oauth2_client/github_oauth2_client.dart';
import 'package:http/http.dart' as http;
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

  Future<Map<String, dynamic>> signInWithMicrosoft() async {
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

  /// Web端Microsoft OAuth登录
  Future<Map<String, dynamic>> _signInWithMicrosoftWeb() async {
    // 从后端获取授权URL
    final authUrlResponse = await http.get(
      Uri.parse('${ApiService.baseUrl}/api/auth/oauth/microsoft/url?redirect_uri=${Uri.encodeComponent(_redirectUri)}'),
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

    // 直接将授权码发送给后端，让后端处理令牌交换
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

  /// Windows桌面端Microsoft OAuth登录
  Future<Map<String, dynamic>> _signInWithMicrosoftDesktop() async {
    try {
      final state = UriHandlerService.generateState();
      
      // 构建授权URL
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
      
      // 启动OAuth流程并等待回调
      final result = await UriHandlerService.launchOAuthAndWaitForCallback(
        authUrl: authUrl,
        state: state,
      );
      
      final authCode = result['code'];
      if (authCode == null || authCode.isEmpty) {
        throw Exception('未收到授权码');
      }
      
      debugPrint('✅ 收到Microsoft授权码，发送给后端处理');
      
      // 直接将授权码发送给后端，让后端处理令牌交换
      final authResult = await _authenticateWithBackend('microsoft', {
        'authorization_code': authCode,
        'redirect_uri': _redirectUri,
      });
      
      return {
        'success': true,
        'token': authResult['token'],
        'expires': authResult['expires'],
        'user': authResult['user'],
      };
    } catch (e) {
      debugPrint('❌ Microsoft桌面端登录失败: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 原生平台Microsoft OAuth登录
  Future<Map<String, dynamic>> _signInWithMicrosoftNative() async {
    // Windows桌面端使用自定义URI处理
    if (!kIsWeb && Platform.isWindows) {
      return await _signInWithMicrosoftDesktop();
    }
    
    // 其他平台使用原有逻辑
    final client = OAuth2Client(
      authorizeUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
      tokenUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
      redirectUri: _redirectUri,
      customUriScheme: _customUriScheme,
    );

    final helper = OAuth2Helper(
      client,
      grantType: OAuth2Helper.authorizationCode,
      clientId: microsoftClientId,
      scopes: ['openid', 'profile', 'email', 'User.Read'],
      webAuthOpts: {
        'useWebview': false,
        'timeout': 300,
      },
    );

    // 使用Microsoft Graph API获取用户信息
    final response = await helper.get('https://graph.microsoft.com/v1.0/me');
    
    if (response.statusCode == 200) {
      final userInfo = json.decode(response.body);
      final accessToken = await helper.getToken();
      
      // 调用后端OAuth接口，只传递访问令牌
      final result = await _authenticateWithBackend('microsoft', {
        'access_token': accessToken?.accessToken,
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
        'token': result['token'],
        'expires': result['expires'],
        'user': userInfo,
      };
    } else {
      throw Exception('获取用户信息失败: ${response.statusCode}');
    }
  }

  /// Google OAuth2 登录
  Future<Map<String, dynamic>> signInWithGoogle() async {
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

  /// Web端Google OAuth登录
  Future<Map<String, dynamic>> _signInWithGoogleWeb() async {
    // 从后端获取授权URL
    final authUrlResponse = await http.get(
      Uri.parse('${ApiService.baseUrl}/api/auth/oauth/google/url?redirect_uri=${Uri.encodeComponent(_redirectUri)}'),
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

    // 直接将授权码发送给后端，让后端处理令牌交换
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

  /// Windows桌面端Google OAuth登录
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
      final result = await UriHandlerService.launchOAuthAndWaitForCallback(
        authUrl: authUrl,
        state: state,
      );
      
      final authCode = result['code'];
      if (authCode == null || authCode.isEmpty) {
        throw Exception('未收到授权码');
      }
      
      debugPrint('✅ 收到Google授权码，发送给后端处理');
      
      // 直接将授权码发送给后端，让后端处理令牌交换
      final authResult = await _authenticateWithBackend('google', {
        'authorization_code': authCode,
        'redirect_uri': _redirectUri,
      });
      
      return {
        'success': true,
        'token': authResult['token'],
        'expires': authResult['expires'],
        'user': authResult['user'],
      };
    } catch (e) {
      debugPrint('❌ Google桌面端登录失败: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 原生平台Google OAuth登录
  Future<Map<String, dynamic>> _signInWithGoogleNative() async {
    // Windows桌面端使用自定义URI处理
    if (!kIsWeb && Platform.isWindows) {
      return await _signInWithGoogleDesktop();
    }
    
    // 其他平台使用原有逻辑
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
        'windowIcon': 'assets/images/Dext.ico',
        'useWebview': false,
        'timeout': 300,
      },
    );

    // 首先获取访问令牌
    final accessToken = await helper.getToken();
    if (accessToken?.accessToken == null) {
      throw Exception('获取访问令牌失败');
    }
    
    // 使用访问令牌获取用户信息
    final response = await helper.get('https://www.googleapis.com/oauth2/v2/userinfo');
    
    if (response.statusCode == 200) {
      final userInfo = json.decode(response.body);
      
      // 调用后端OAuth接口，只传递访问令牌
      final result = await _authenticateWithBackend('google', {
        'access_token': accessToken!.accessToken,
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
        'token': result['token'],
        'expires': result['expires'],
        'user': userInfo,
      };
    } else {
      throw Exception('获取用户信息失败: ${response.statusCode}');
    }
  }

  /// GitHub OAuth2 登录
  Future<Map<String, dynamic>> signInWithGitHub() async {
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

  /// Web端GitHub OAuth登录
  Future<Map<String, dynamic>> _signInWithGitHubWeb() async {
    // 从后端获取授权URL
    final authUrlResponse = await http.get(
      Uri.parse('${ApiService.baseUrl}/api/auth/oauth/github/url?redirect_uri=${Uri.encodeComponent(_redirectUri)}'),
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

    // 直接将授权码发送给后端，让后端处理令牌交换
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

  /// Windows桌面端GitHub OAuth登录
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
      final result = await UriHandlerService.launchOAuthAndWaitForCallback(
        authUrl: authUrl,
        state: state,
      );
      
      final authCode = result['code'];
      if (authCode == null || authCode.isEmpty) {
        throw Exception('未收到授权码');
      }
      
      // 调用后端OAuth接口，直接传递授权码
      final authResult = await _authenticateWithBackend('github', {
        'authorization_code': authCode,
        'redirect_uri': _redirectUri,
      });
      
      return {
        'success': true,
        'token': authResult['token'],
        'expires': authResult['expires'],
        'user': authResult['user'],
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 原生平台GitHub OAuth登录
  Future<Map<String, dynamic>> _signInWithGitHubNative() async {
    // Windows桌面端使用自定义URI处理
    if (!kIsWeb && Platform.isWindows) {
      return await _signInWithGitHubDesktop();
    }
    
    // 其他平台使用原有逻辑
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
        'windowIcon': 'assets/images/Dext.ico',
        'useWebview': false,
        'timeout': 300,
      },
    );

    // 获取用户基本信息
    final userResponse = await helper.get('https://api.github.com/user');
    
    if (userResponse.statusCode == 200) {
      final userInfo = json.decode(userResponse.body);
      final accessToken = await helper.getToken();
      
      // 获取用户邮箱
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
      
      // 调用后端OAuth接口，只传递访问令牌
      final result = await _authenticateWithBackend('github', {
        'access_token': accessToken?.accessToken,
        'user_info': userInfoFormatted,
      });

      return {
        'success': true,
        'token': result['token'],
        'expires': result['expires'],
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
          'user': data['user'], // 返回完整的用户信息
        };
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? '后端认证失败');
      }
    } catch (e) {
      throw Exception('后端认证失败: ${e.toString()}');
    }
  }

  /// 检查OAuth配置是否完整
  static bool isConfigured() {
    return googleClientId != 'YOUR_GOOGLE_CLIENT_ID' &&
           githubClientId != 'YOUR_GITHUB_CLIENT_ID' &&
           microsoftClientId != 'YOUR_MICROSOFT_CLIENT_ID';
  }
}
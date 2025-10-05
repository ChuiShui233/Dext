import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/google_oauth2_client.dart';
import 'package:oauth2_client/github_oauth2_client.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'config.dart';
import 'web_oauth_handler.dart' if (dart.library.io) 'web_oauth_handler_stub.dart';

class OAuthService {
  // 重定向URI和自定义URI方案配置
  static String get _customUriScheme {
    if (kIsWeb) {
      return 'https';
    } else if (Platform.isAndroid) {
      return uriSchemeAndroid;
    } else if (Platform.isIOS) {
      return uriSchemeIOS;
    } else {
      return 'http';
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

  /// Microsoft OAuth2 登录
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
    // 构建授权URL
    final authUrl = Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/authorize', {
      'client_id': microsoftClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'openid profile email User.Read',
      'response_mode': 'query',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    // 使用自定义处理器打开OAuth窗口
    final authCode = await WebOAuthHandler.authenticate(
      authUrl: authUrl.toString(),
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

    // 交换访问令牌
    final tokenResponse = await http.post(
      Uri.parse('https://login.microsoftonline.com/common/oauth2/v2.0/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': microsoftClientId,
        'client_secret': microsoftClientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': _redirectUri,
      },
    );

    if (tokenResponse.statusCode != 200) {
      throw Exception('获取访问令牌失败: ${tokenResponse.statusCode}');
    }

    final tokenData = json.decode(tokenResponse.body);
    final accessToken = tokenData['access_token'];

    // 获取用户信息
    final userResponse = await http.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (userResponse.statusCode != 200) {
      throw Exception('获取用户信息失败: ${userResponse.statusCode}');
    }

    final userInfo = json.decode(userResponse.body);
    
    // 调用后端OAuth接口
    final result = await _authenticateWithBackend('microsoft', {
      'access_token': accessToken,
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
  }

  /// 原生平台Microsoft OAuth登录
  Future<Map<String, dynamic>> _signInWithMicrosoftNative() async {
    // 创建自定义的Microsoft OAuth2客户端
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
      clientSecret: microsoftClientSecret,
      scopes: ['openid', 'profile', 'email', 'User.Read'],
      webAuthOpts: {
        'windowName': 'Dext - Microsoft登录',
        'windowTitle': 'Dext - Microsoft登录',
        'windowIcon': 'assets/images/Dext.ico',
        'useWebview': true,
        'timeout': 300,
      },
    );

    // 使用Microsoft Graph API获取用户信息
    final response = await helper.get('https://graph.microsoft.com/v1.0/me');
    
    if (response.statusCode == 200) {
      final userInfo = json.decode(response.body);
      
      // 调用后端OAuth接口
      final result = await _authenticateWithBackend('microsoft', {
        'access_token': await helper.getToken(),
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
    // 构建授权URL
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': googleClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'openid profile email',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    // 使用自定义处理器打开OAuth窗口
    final authCode = await WebOAuthHandler.authenticate(
      authUrl: authUrl.toString(),
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

    // 交换访问令牌
    final tokenResponse = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': googleClientId,
        'client_secret': googleClientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': _redirectUri,
      },
    );

    if (tokenResponse.statusCode != 200) {
      throw Exception('获取访问令牌失败: ${tokenResponse.statusCode}');
    }

    final tokenData = json.decode(tokenResponse.body);
    final accessToken = tokenData['access_token'];

    // 获取用户信息
    final userResponse = await http.get(
      Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (userResponse.statusCode != 200) {
      throw Exception('获取用户信息失败: ${userResponse.statusCode}');
    }

    final userInfo = json.decode(userResponse.body);
    
    // 调用后端OAuth接口
    final result = await _authenticateWithBackend('google', {
      'access_token': accessToken,
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
  }

  /// 原生平台Google OAuth登录
  Future<Map<String, dynamic>> _signInWithGoogleNative() async {
    final client = GoogleOAuth2Client(
      redirectUri: _redirectUri,
      customUriScheme: _customUriScheme,
    );

    final helper = OAuth2Helper(
      client,
      grantType: OAuth2Helper.authorizationCode,
      clientId: googleClientId,
      clientSecret: googleClientSecret,
      scopes: ['openid', 'profile', 'email'],
      webAuthOpts: {
        'windowName': 'Dext - Google登录',
        'windowTitle': 'Dext - Google登录',
        'windowIcon': 'assets/images/Dext.ico',
        'useWebview': true,
        'timeout': 300,
      },
    );

    // 使用helper获取访问令牌
    final response = await helper.get('https://www.googleapis.com/oauth2/v2/userinfo');
    
    if (response.statusCode == 200) {
      final userInfo = json.decode(response.body);
      
      // 调用后端OAuth接口
      final result = await _authenticateWithBackend('google', {
        'access_token': await helper.getToken(),
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
    // 构建授权URL
    final authUrl = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': githubClientId,
      'redirect_uri': _redirectUri,
      'scope': 'user:email',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    // 使用自定义处理器打开OAuth窗口
    final authCode = await WebOAuthHandler.authenticate(
      authUrl: authUrl.toString(),
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

    // 交换访问令牌
    final tokenResponse = await http.post(
      Uri.parse('https://github.com/login/oauth/access_token'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: {
        'client_id': githubClientId,
        'client_secret': githubClientSecret,
        'code': code,
      },
    );

    if (tokenResponse.statusCode != 200) {
      throw Exception('获取访问令牌失败: ${tokenResponse.statusCode}');
    }

    final tokenData = json.decode(tokenResponse.body);
    final accessToken = tokenData['access_token'];

    // 获取用户基本信息
    final userResponse = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (userResponse.statusCode != 200) {
      throw Exception('获取用户信息失败: ${userResponse.statusCode}');
    }

    final userInfo = json.decode(userResponse.body);
    
    // 获取用户邮箱
    String? email = userInfo['email'];
    if (email == null || email.isEmpty) {
      final emailResponse = await http.get(
        Uri.parse('https://api.github.com/user/emails'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
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
    
    // 调用后端OAuth接口
    final result = await _authenticateWithBackend('github', {
      'access_token': accessToken,
      'user_info': userInfoFormatted,
    });

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': userInfoFormatted,
    };
  }

  /// 原生平台GitHub OAuth登录
  Future<Map<String, dynamic>> _signInWithGitHubNative() async {
    final client = GitHubOAuth2Client(
      redirectUri: _redirectUri,
      customUriScheme: _customUriScheme,
    );

    final helper = OAuth2Helper(
      client,
      grantType: OAuth2Helper.authorizationCode,
      clientId: githubClientId,
      clientSecret: githubClientSecret,
      scopes: ['user:email'],
      webAuthOpts: {
        'windowName': 'Dext - GitHub登录',
        'windowTitle': 'Dext - GitHub登录',
        'windowIcon': 'assets/images/Dext.ico',
        'useWebview': true,
        'timeout': 300,
      },
    );

    // 获取用户基本信息
    final userResponse = await helper.get('https://api.github.com/user');
    
    if (userResponse.statusCode == 200) {
      final userInfo = json.decode(userResponse.body);
      
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
      
      // 调用后端OAuth接口
      final result = await _authenticateWithBackend('github', {
        'access_token': await helper.getToken(),
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
      // 这里调用后端的OAuth认证接口
      // 后端会验证OAuth令牌并返回应用的JWT令牌
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/auth/oauth'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'provider': provider,
          'oauth_data': oauthData,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'token': data['token'],
          'expires': DateTime.parse(data['expires']),
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

  /// 获取配置说明
  static String getConfigurationInstructions() {
    return '''
OAuth配置说明：

1. Google OAuth配置：
   - 访问 https://console.developers.google.com/
   - 创建项目并启用Google+ API
   - 创建OAuth 2.0客户端ID
   - 将客户端ID和密钥替换到代码中

2. GitHub OAuth配置：
   - 访问 https://github.com/settings/developers
   - 创建新的OAuth App
   - 设置Authorization callback URL为: $_redirectUri
   - 将客户端ID和密钥替换到代码中

3. Microsoft OAuth配置：
   - 访问 https://portal.azure.com/
   - 在Azure Active Directory中注册应用
   - 在"身份验证"中选择"任何组织目录中的帐户和个人Microsoft帐户"
   - 配置重定向URI和API权限
   - 获取应用程序(客户端)ID和客户端密钥
   - 将客户端ID和密钥替换到代码中

4. 重定向URI配置：
   - Web: $oauthCallbackWeb
   - Android: $oauthCallbackAndroid
   - iOS: $oauthCallbackIOS
   - Desktop: $oauthCallbackDesktop
''';
  }
}

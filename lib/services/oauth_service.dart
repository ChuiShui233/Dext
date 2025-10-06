import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart' as webauth2;
import 'api_service.dart';
import 'config.dart';
import 'web_oauth_handler.dart' if (dart.library.io) 'web_oauth_handler_stub.dart';

class OAuthService {
  // 重定向URI和自定义URI方案配置

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
    // 生成 PKCE 参数
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeS256(verifier);

    // 构建授权URL（使用 PKCE）
    final authUrl = Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/authorize', {
      'client_id': microsoftClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'openid profile email User.Read',
      'response_mode': 'query',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });

    // 打开授权窗口（Web 用 WebOAuthHandler；原生容错使用 _nativeAuthenticate）
    final authCode = kIsWeb
        ? await WebOAuthHandler.authenticate(
            authUrl: authUrl.toString(),
            redirectUrl: _redirectUri,
            windowOptions: {
              'width': '500',
              'height': '700',
            },
            timeoutSeconds: 300,
          )
        : await _nativeAuthenticate(authUrl.toString());

    // 解析授权码
    final uri = Uri.parse(authCode);
    final code = uri.queryParameters['code'];
    if (code == null) {
      throw Exception('未获取到授权码');
    }

    // 使用后端进行交换（避免在前端持有 client secret）
    final result = await _exchangeWithBackend(
      provider: 'microsoft',
      code: code,
      redirectUri: _redirectUri,
      codeVerifier: verifier,
    );

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
  }

  /// 原生平台Microsoft OAuth登录
  Future<Map<String, dynamic>> _signInWithMicrosoftNative() async {
    // 使用与 Web 一致的模式：PKCE + 后端交换
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeS256(verifier);

    final authUrl = Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/authorize', {
      'client_id': microsoftClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'openid profile email User.Read',
      'response_mode': 'query',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });

    final authCode = await _nativeAuthenticate(authUrl.toString());

    final uri = Uri.parse(authCode);
    final code = uri.queryParameters['code'];
    if (code == null) {
      throw Exception('未获取到授权码');
    }

    final result = await _exchangeWithBackend(
      provider: 'microsoft',
      code: code,
      redirectUri: _redirectUri,
      codeVerifier: verifier,
    );

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
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
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeS256(verifier);
    // 构建授权URL（使用 PKCE）
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': googleClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'openid profile email',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
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

    // 使用后端进行交换
    final result = await _exchangeWithBackend(
      provider: 'google',
      code: code,
      redirectUri: _redirectUri,
      codeVerifier: verifier,
    );

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
  }

  /// 原生平台Google OAuth登录
  Future<Map<String, dynamic>> _signInWithGoogleNative() async {
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeS256(verifier);

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': googleClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'openid profile email',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
    });

    final authCode = await _nativeAuthenticate(authUrl.toString());

    final uri = Uri.parse(authCode);
    final code = uri.queryParameters['code'];
    if (code == null) {
      throw Exception('未获取到授权码');
    }

    final result = await _exchangeWithBackend(
      provider: 'google',
      code: code,
      redirectUri: _redirectUri,
      codeVerifier: verifier,
    );

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
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
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeS256(verifier);
    // 构建授权URL（GitHub 支持 PKCE）
    final authUrl = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': githubClientId,
      'redirect_uri': _redirectUri,
      'scope': 'user:email',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
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

    // 使用后端进行交换
    final result = await _exchangeWithBackend(
      provider: 'github',
      code: code,
      redirectUri: _redirectUri,
      codeVerifier: verifier,
    );

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
  }

  /// 原生平台GitHub OAuth登录
  Future<Map<String, dynamic>> _signInWithGitHubNative() async {
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeS256(verifier);

    final authUrl = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': githubClientId,
      'redirect_uri': _redirectUri,
      'scope': 'user:email',
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });

    final authCode = await _nativeAuthenticate(authUrl.toString());

    final uri = Uri.parse(authCode);
    final code = uri.queryParameters['code'];
    if (code == null) {
      throw Exception('未获取到授权码');
    }

    final result = await _exchangeWithBackend(
      provider: 'github',
      code: code,
      redirectUri: _redirectUri,
      codeVerifier: verifier,
    );

    return {
      'success': true,
      'token': result['token'],
      'expires': result['expires'],
      'user': result['user'],
    };
  }



  // 使用后端进行授权码交换（PKCE）
  Future<Map<String, dynamic>> _exchangeWithBackend({
    required String provider,
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/auth/oauth/exchange'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'provider': provider,
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      }),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return {
        'token': data['token'],
        'expires': DateTime.parse(data['expires']),
        'user': data['user'],
      };
    } else {
      throw Exception('后端交换失败: ${response.statusCode}');
    }
  }

  // 生成 PKCE code_verifier（43-128 长度的高熵字符串）
  String _generateCodeVerifier([int length = 64]) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    final sb = StringBuffer();
    for (int i = 0; i < length; i++) {
      sb.write(chars[rand.nextInt(chars.length)]);
    }
    return sb.toString();
  }

  // 计算 S256 code_challenge（base64url-无填充）
  String _codeChallengeS256(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = crypto.sha256.convert(bytes).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  // 原生平台统一使用 flutter_web_auth_2 弹出授权并等待回调
  Future<String> _nativeAuthenticate(String authUrl) async {
    final scheme = Uri.parse(_redirectUri).scheme; // com.dext.app / dext / http
    // flutter_web_auth_2 需要 callbackUrlScheme；对 http/https 桌面回调也能支持
    final result = await webauth2.FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: scheme,
    );
    return result; // 返回完整回调URL字符串
  }

  /// 检查OAuth配置是否完整
  static bool isConfigured() {
    // 通过 --dart-define 注入的客户端ID必须为非空
    return googleClientId.isNotEmpty &&
           githubClientId.isNotEmpty &&
           microsoftClientId.isNotEmpty;
  }
}
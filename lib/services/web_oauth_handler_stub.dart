// Stub for non-Web platforms to avoid importing package:web
import 'dart:async';

class WebOAuthHandler {
  static Future<String> authenticate({
    required String authUrl,
    required String redirectUrl,
    Map<String, dynamic>? windowOptions,
    int timeoutSeconds = 300,
  }) async {
    throw UnsupportedError('WebOAuthHandler 仅在 Web 平台可用');
  }
}

class OAuthWindowClosedException implements Exception {
  final String message;
  const OAuthWindowClosedException(this.message);
  @override
  String toString() => 'OAuthWindowClosedException: $message';
}

class OAuthTimeoutException implements Exception {
  final String message;
  const OAuthTimeoutException(this.message);
  @override
  String toString() => 'OAuthTimeoutException: $message';
}

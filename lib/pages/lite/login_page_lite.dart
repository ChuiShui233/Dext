import 'package:flutter/material.dart';
import 'package:dext/widgets/survey_preview_card.dart';
import '../login_page.dart';

/// 精简版专用的登录页。

class LoginPageLite extends StatelessWidget {
  final VoidCallback onToggleTheme;

  final Function(String token, DateTime expires) onLoginSuccess;
  final SurveyPreview? surveyPreview;

  const LoginPageLite({
    super.key,
    required this.onToggleTheme,
    required this.onLoginSuccess,
    this.surveyPreview,
  });

  @override
  Widget build(BuildContext context) {
    return LoginPage(
      onToggleTheme: onToggleTheme,
      onLoginSuccess: onLoginSuccess,
      surveyPreview: surveyPreview,
      showOAuth: false,
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaption;
import '../widgets/window_caption.dart';
import '../main.dart' show isDesktop;
import '../services/api_service.dart';
import '../services/oauth_service.dart';
import '../widgets/frosted_oauth_dialog.dart';
import '../services/uri_handler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  
  final Function(String token, DateTime expires) onLoginSuccess;

  const LoginPage({
  super.key, 
  required this.onToggleTheme,
  required this.onLoginSuccess,
});

  @override
  // ignore: library_private_types_in_public_api
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _emailCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _captchaController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _emailCodeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _captchaFocus = FocusNode();
  
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _isResettingPassword = false;
  bool _agreeToTerms = false;
  bool _emailCodeSent = false;
  int _emailCodeCountdown = 0;
  Timer? _countdownTimer;

  final _apiService = ApiService();
  final _oauthService = OAuthService();
  String? _captchaId;
  String? _captchaImage;
  Uint8List? _captchaBytes;
  
  late AnimationController _brandAnimationController;
  late Animation<double> _titleFadeAnimation;
  late Animation<Offset> _titleSlideAnimation;
  late Animation<double> _titleScaleAnimation;
  late Animation<double> _subtitleFadeAnimation;
  late Animation<Offset> _subtitleSlideAnimation;
  late Animation<double> _subtitleScaleAnimation;
  late Animation<double> _descriptionFadeAnimation;
  late Animation<Offset> _descriptionSlideAnimation;
  late Animation<double> _descriptionScaleAnimation;

  @override
  void initState() {
    super.initState();
    _fetchCaptcha();
    
    _brandAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _titleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    
    _titleSlideAnimation = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
      ),
    );
    
    _titleScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    
    _subtitleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
      ),
    );
    
    _subtitleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
      ),
    );
    
    _subtitleScaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOutBack),
      ),
    );
    
    _descriptionFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
      ),
    );
    
    _descriptionSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOutCubic),
      ),
    );
    
    _descriptionScaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _brandAnimationController,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOutBack),
      ),
    );
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _brandAnimationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _emailCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _captchaController.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _emailCodeFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _captchaFocus.dispose();
    _brandAnimationController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String hashPassword(String password) {
    return password;
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://cc12.eu.org');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) return;
      showErrorDialog('无法打开隐私政策页面');
    }
  }

  Future<void> _fetchCaptcha() async {
    try {
      final captcha = await ApiService().getTextCaptcha();
      final String data = captcha['data'];
      final String raw = data.startsWith('data:image') ? data.split(',').last : data;
      final decoded = base64Decode(raw);
      if (!mounted) return;
      setState(() {
        _captchaId = captcha['captchaId'];
        _captchaImage = data;
        _captchaBytes = decoded;
        _captchaController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _captchaId = null;
        _captchaImage = null;
        _captchaBytes = null;
      });
      showErrorDialog('获取验证码失败，请检查网络后重试');
    }
  }

  void _recordLoginInfo(String token, DateTime expires) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('token_expiry', expires.toIso8601String());
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    if (_usernameController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      showErrorDialog('用户名和密码不能为空');
      return;
    }
    if (_captchaController.text.trim().isEmpty) {
      showErrorDialog('请输入验证码');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _apiService.login(
        username: _usernameController.text,
        password: hashPassword(_passwordController.text),
        captchaId: _captchaId ?? '',
        captchaValue: _captchaController.text.trim(),
      );
      
      if (!mounted) return;
      
      final token = result['token'];
      final expires = result['expires'];
      
      widget.onLoginSuccess(token, expires);
      _recordLoginInfo(token, expires);
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _fetchCaptcha();
      }
    }
  }

  // Google OAuth登录
  Future<void> _handleGoogleLogin() async {
    if (_isLoading) return;
    
    BuildContext? dialogContext;
    bool dialogShown = false;
    
    void closeDialog() {
      if (dialogShown && dialogContext != null) {
        try {
          Navigator.of(dialogContext!).pop();
        } catch (_) {}
        dialogShown = false;
        dialogContext = null;
      }
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            dialogContext = context;
            return FrostedOAuthDialog(
              providerName: 'Google',
              waitingText: '请在浏览器中完成授权，或点击取消',
              onCancel: () {
                UriHandlerService.cancelAllPendingCallbacks();
                closeDialog();
              },
            );
          },
        );
        dialogShown = true;
      }
      
      final result = await _oauthService.signInWithGoogle();
      
      closeDialog();
      
      debugPrint('🔍 Google OAuth结果: ${result.keys.join(", ")}');
      
      if (!mounted) return;
      
      if (result['success']) {
        final token = result['token'];
        final expires = result['expires'];
        
        debugPrint('✅ Google登录成功，准备保存token');
        debugPrint('Token前20字符: ${token?.substring(0, 20)}...');
        debugPrint('过期时间: $expires');
        
        await widget.onLoginSuccess(token, expires);
        debugPrint('✅ onLoginSuccess回调完成');
        
        _recordLoginInfo(token, expires);
        debugPrint('✅ 记录登录信息完成');
      } else {
        if (result['cancelled'] == true) {
          return;
        } else if (result['timeout'] == true) {
          showErrorDialog('登录超时，请重试');
        } else {
          showErrorDialog(result['error']);
        }
      }
    } catch (e) {
      closeDialog();
      if (!mounted) return;
      showErrorDialog('Google登录失败: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // GitHub OAuth登录
  Future<void> _handleGitHubLogin() async {
    if (_isLoading) return;
    
    BuildContext? dialogContext;
    bool dialogShown = false;
    
    void closeDialog() {
      if (dialogShown && dialogContext != null) {
        try {
          Navigator.of(dialogContext!).pop();
        } catch (_) {}
        dialogShown = false;
        dialogContext = null;
      }
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            dialogContext = context;
            return FrostedOAuthDialog(
              providerName: 'GitHub',
              waitingText: '请在浏览器中完成授权，或点击取消',
              onCancel: () {
                UriHandlerService.cancelAllPendingCallbacks();
                closeDialog();
              },
            );
          },
        );
        dialogShown = true;
      }
      
      final result = await _oauthService.signInWithGitHub();
      
      closeDialog();
      
      if (!mounted) return;
      
      if (result['success']) {
        final token = result['token'];
        final expires = result['expires'];
        
        widget.onLoginSuccess(token, expires);
        _recordLoginInfo(token, expires);
      } else {
        if (result['cancelled'] == true) {
          return;
        } else if (result['timeout'] == true) {
          showErrorDialog('登录超时，请重试');
        } else {
          showErrorDialog(result['error']);
        }
      }
    } catch (e) {
      closeDialog();
      if (!mounted) return;
      showErrorDialog('GitHub登录失败: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Microsoft OAuth登录
  Future<void> _handleMicrosoftLogin() async {
    if (_isLoading) return;
    
    BuildContext? dialogContext;
    bool dialogShown = false;
    
    void closeDialog() {
      if (dialogShown && dialogContext != null) {
        try {
          Navigator.of(dialogContext!).pop();
        } catch (_) {}
        dialogShown = false;
        dialogContext = null;
      }
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            dialogContext = context;
            return FrostedOAuthDialog(
              providerName: 'Microsoft',
              waitingText: '请在浏览器中完成授权，或点击取消',
              onCancel: () {
                UriHandlerService.cancelAllPendingCallbacks();
                closeDialog();
              },
            );
          },
        );
        dialogShown = true;
      }
      
      final result = await _oauthService.signInWithMicrosoft();
      
      closeDialog();
      
      if (!mounted) return;
      
      if (result['success']) {
        final token = result['token'];
        final expires = result['expires'];
        
        widget.onLoginSuccess(token, expires);
        _recordLoginInfo(token, expires);
      } else {
        if (result['cancelled'] == true) {
          return;
        } else if (result['timeout'] == true) {
          showErrorDialog('登录超时，请重试');
        } else {
          showErrorDialog(result['error']);
        }
      }
    } catch (e) {
      closeDialog();
      if (!mounted) return;
      showErrorDialog('Microsoft登录失败: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendEmailCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      showErrorDialog('请输入邮箱地址');
      return;
    }
    if (!_isValidEmail(email)) {
      showErrorDialog('邮箱格式不正确');
      return;
    }
    if (_captchaController.text.trim().isEmpty) {
      showErrorDialog('请先输入图形验证码');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final purpose = _isResettingPassword ? 'reset_password' : 'register';
      await _apiService.sendEmailVerificationCode(
        email: email,
        purpose: purpose,
        captchaId: _captchaId ?? '',
        captchaValue: _captchaController.text.trim(),
      );
      
      if (!mounted) return;
      
      setState(() {
        _emailCodeSent = true;
        _emailCodeCountdown = 60;
      });
      
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_emailCodeCountdown > 0) {
            _emailCodeCountdown--;
          } else {
            timer.cancel();
            _emailCodeSent = false;
          }
        });
      });
      
      showAdaptiveDialog(
        context: context,
        builder: (context) => FDialog(
          direction: Axis.horizontal,
          title: const Text('验证码已发送'),
          body: const Text('请查收邮件并输入6位验证码'),
          actions: [
            FButton(
              style: FButtonStyle.outline,
              child: const Text('确定'),
              onPress: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _fetchCaptcha();
      }
    }
  }

  Future<void> _handleRegister() async {
    if (_isLoading || !_agreeToTerms) return;
    if (_usernameController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      showErrorDialog('用户名和密码不能为空');
      return;
    }
    if (_captchaController.text.trim().isEmpty) {
      showErrorDialog('请输入验证码');
      return;
    }
    if (_usernameController.text.length < 3 || _usernameController.text.length > 12) {
      showErrorDialog('用户名要在3到12个字符之间哦');
      return;
    }
    if (_passwordController.text.length < 8 || _passwordController.text.length > 64) {
      showErrorDialog('密码长度要在8到64个字符之间哦');
      return;
    }
    if (_confirmPasswordController.text.trim().isEmpty) {
      showErrorDialog('请再次输入确认密码');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      showErrorDialog('两次输入的密码不一致');
      return;
    }
    
    final email = _emailController.text.trim();
    if (email.isNotEmpty && !_isValidEmail(email)) {
      showErrorDialog('邮箱格式不正确');
      return;
    }
    
    final emailCode = _emailCodeController.text.trim();
    if (email.isNotEmpty && emailCode.isEmpty) {
      showErrorDialog('请输入邮箱验证码');
      return;
    }
    if (email.isNotEmpty && emailCode.length != 6) {
      showErrorDialog('邮箱验证码应为6位数字');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.register(
        username: _usernameController.text,
        password: hashPassword(_passwordController.text),
        captchaId: _captchaId ?? '',
        captchaValue: _captchaController.text.trim(),
        email: email.isNotEmpty ? email : null,
        emailCode: emailCode.isNotEmpty ? emailCode : null,
      );
      
      if (!mounted) return;
      
      showAdaptiveDialog(
        context: context, 
        builder: (context) => FDialog(
          direction: Axis.horizontal,
          title: const Text('注册成功'),
          body: const Text('你现在可以登录了'),
          actions: [
            FButton(
              style: FButtonStyle.outline,
              child: const Text('确定'),
              onPress: () {
                Navigator.of(context).pop();
                setState(() {
                  _isRegistering = false;
                  _usernameController.clear();
                  _passwordController.clear();
                  _confirmPasswordController.clear();
                });
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _fetchCaptcha();
      }
    }
  }

  Future<void> _handleResetPassword() async {
    if (_isLoading) return;
    
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      showErrorDialog('请输入邮箱地址');
      return;
    }
    if (!_isValidEmail(email)) {
      showErrorDialog('邮箱格式不正确');
      return;
    }
    
    final emailCode = _emailCodeController.text.trim();
    if (emailCode.isEmpty) {
      showErrorDialog('请输入邮箱验证码');
      return;
    }
    if (emailCode.length != 6) {
      showErrorDialog('邮箱验证码应为6位数字');
      return;
    }
    
    if (_passwordController.text.trim().isEmpty) {
      showErrorDialog('请输入新密码');
      return;
    }
    if (_passwordController.text.length < 8 || _passwordController.text.length > 64) {
      showErrorDialog('密码长度要在8到64个字符之间');
      return;
    }
    if (_confirmPasswordController.text.trim().isEmpty) {
      showErrorDialog('请再次输入确认密码');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      showErrorDialog('两次输入的密码不一致');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.resetPassword(
        email: email,
        code: emailCode,
        newPassword: hashPassword(_passwordController.text),
      );
      
      if (!mounted) return;
      
      showAdaptiveDialog(
        context: context,
        builder: (context) => FDialog(
          direction: Axis.horizontal,
          title: const Text('密码重置成功'),
          body: const Text('请使用新密码登录'),
          actions: [
            FButton(
              style: FButtonStyle.outline,
              child: const Text('确定'),
              onPress: () {
                Navigator.of(context).pop();
                setState(() {
                  _isResettingPassword = false;
                  _usernameController.clear();
                  _emailController.clear();
                  _emailCodeController.clear();
                  _passwordController.clear();
                  _confirmPasswordController.clear();
                  _captchaController.clear();
                  _emailCodeSent = false;
                  _emailCodeCountdown = 0;
                  _countdownTimer?.cancel();
                });
                _fetchCaptcha();
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isValidEmail(String email) {
    if (email.length < 3 || email.length > 255) {
      return false;
    }
    final atIndex = email.indexOf('@');
    if (atIndex <= 0 || atIndex == email.length - 1) {
      return false;
    }
    final dotIndex = email.lastIndexOf('.');
    if (dotIndex <= atIndex + 1 || dotIndex == email.length - 1) {
      return false;
    }
    return true;
  }

  void showErrorDialog(String message) {
    if (!mounted) return;
    showAdaptiveDialog(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('错误'),
        body: Text(message),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            child: const Text('确定'),
            onPress: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  final isWide = screenWidth > 800;
  final statusBarHeight = MediaQuery.of(context).padding.top;

  final Widget content = AnimatedSwitcher(
    duration: const Duration(milliseconds: 400),
    switchInCurve: Curves.easeInOut,
    switchOutCurve: Curves.easeInOut,
    transitionBuilder: (child, animation) {
      final fadeAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOut,
      );
      
      // 桌面端：淡入淡出 + 缩放
      if (isWide) {
        return FadeTransition(
          opacity: fadeAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      }
      // 移动端：淡入淡出 + 滑动
      return FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
    child: _isResettingPassword
        ? _buildResetPasswordForm()
        : (_isRegistering ? _buildRegisterForm() : _buildLoginForm()),
  );

  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Scaffold(
    body: Stack(
      children: [
Positioned.fill(
  child: Stack(
    children: [
      // p.jpg 背景（桌面端）
      AnimatedOpacity(
        opacity: isWide ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: SizedBox.expand(
          child: Image.asset(
            "assets/images/p.jpg",
            fit: BoxFit.cover,
          ),
        ),
      ),
      // m.png 背景（移动端）
      AnimatedOpacity(
        opacity: isWide ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: SizedBox.expand(
          child: Image.asset(
            "assets/images/m.png",
            fit: BoxFit.cover,
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.5),
                  ]
                : [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.2),
                  ],
          ),
        ),
      ),
    ],
  ),
),


        if (isDesktop)
          const Align(
            alignment: Alignment.topRight,
            child: WindowCaption(),
          ),
        if (isDesktop)
          const DragToMoveArea(
            child: SizedBox(
              height: 40,
              width: double.infinity,
            ),
          ),
        if (isWide)
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutCubic,
                    offset: _isRegistering ? const Offset(-0.5, 0) : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 500),
                      opacity: _isRegistering ? 0.0 : 1.0,
                      curve: Curves.easeInOut,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 32),
                            // 主标题 - 带交错动画
                            FadeTransition(
                              opacity: _titleFadeAnimation,
                              child: SlideTransition(
                                position: _titleSlideAnimation,
                                child: ScaleTransition(
                                  scale: _titleScaleAnimation,
                                  alignment: Alignment.centerLeft,
                                  child: ShaderMask(
                                    shaderCallback: (bounds) => LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Colors.white.withValues(alpha: 0.9),
                                      ],
                                    ).createShader(bounds),
                                    child: const Text(
                                      'Dext Survey',
                                      style: TextStyle(
                                        fontSize: 52,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontFamily: 'PingFangSC',
                                        letterSpacing: 1,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FadeTransition(
                              opacity: _subtitleFadeAnimation,
                              child: SlideTransition(
                                position: _subtitleSlideAnimation,
                                child: ScaleTransition(
                                  scale: _subtitleScaleAnimation,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '问卷调查平台',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontFamily: 'PingFangSC',
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FadeTransition(
                              opacity: _descriptionFadeAnimation,
                              child: SlideTransition(
                                position: _descriptionSlideAnimation,
                                child: ScaleTransition(
                                  scale: _descriptionScaleAnimation,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '轻松创建、发布和管理问卷\n实时收集反馈，深入分析数据\n让每一次调查都更有价值',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontFamily: 'PingFangSC',
                                      height: 1.8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 20.0,
                      sigmaY: 20.0,
                      tileMode: TileMode.clamp,
                    ),
                    child: SizedBox(
                      width: 500,
                      child: content,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 20.0,
                  sigmaY: 20.0,
                  tileMode: TileMode.clamp,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDark
                          ? [
                              Colors.black.withValues(alpha: 0.3),
                              Colors.black.withValues(alpha: 0.4),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.6),
                              Colors.white.withValues(alpha: 0.5),
                            ],
                    ),
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: isDesktop ? 40 : statusBarHeight + 16,
          right: 16,
          child: FButton.icon(
            onPress: _isLoading ? null : widget.onToggleTheme,
            child: Icon(
              isDark ? FIcons.sun : FIcons.moon,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
      ],
    ),
  );
}


  Widget _buildCaptchaCard() {
    return Row(
      children: [
        if (_captchaBytes != null)
          GestureDetector(
            onTap: _fetchCaptcha,
            child: Container(
              height: 60,
              width: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: RepaintBoundary(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Image.memory(
                    _captchaBytes!,
                    key: ValueKey(_captchaId),
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        if (_captchaImage == null)
          Container(
            height: 60,
            width: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '加载中',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: FTextField(
            controller: _captchaController,
            focusNode: _captchaFocus,
            label: const Text('验证码'),
            hint: '请输入验证码',
            textInputAction: TextInputAction.next,
            onEditingComplete: () {
              if (_isResettingPassword) {
                FocusScope.of(context).requestFocus(_emailCodeFocus);
              } else if (_isRegistering) {
                if (!_isLoading && _agreeToTerms) _handleRegister();
              } else {
                if (!_isLoading) _handleLogin();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOAuthButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required List<Color> colors,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'PingFangSC',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    
    final loginContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            ],
          ).createShader(bounds),
          child: const Text(
            '欢迎回来',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'PingFangSC',
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '登录以继续使用 Dext',
          style: TextStyle(
            fontSize: 14,
            color: isDark
                ? Colors.white.withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.5),
            fontFamily: 'PingFangSC',
          ),
        ),
        const SizedBox(height: 32),
        FTextField(
          controller: _usernameController,
          focusNode: _usernameFocus,
          label: const Text('用户名'),
          hint: '请输入用户名',
          textInputAction: TextInputAction.next,
          onEditingComplete: () =>
              FocusScope.of(context).requestFocus(_passwordFocus),
        ),
        const SizedBox(height: 16),
        FTextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          label: const Text('密码'),
          hint: '请输入密码',
          obscureText: true,
          textInputAction: TextInputAction.next,
          onEditingComplete: () =>
              FocusScope.of(context).requestFocus(_captchaFocus),
        ),
        const SizedBox(height: 16),
        _buildCaptchaCard(),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _isLoading ? null : () {
                setState(() {
                  _isResettingPassword = true;
                  _usernameController.clear();
                  _emailController.clear();
                  _emailCodeController.clear();
                  _passwordController.clear();
                  _confirmPasswordController.clear();
                  _captchaController.clear();
                  _emailCodeSent = false;
                  _emailCodeCountdown = 0;
                  _countdownTimer?.cancel();
                });
                _fetchCaptcha();
              },
              child: Text(
                '忘记密码？',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: 
                  [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black.withValues(alpha: 0.7),
                    ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isLoading ? null : _handleLogin,
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        '登录',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'PingFangSC',
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isLoading ? null : () => setState(() => _isRegistering = true),
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: Text(
                  '注册新账号',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'PingFangSC',
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '或使用第三方登录',
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontFamily: 'PingFangSC',
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildOAuthButton(
                onTap: _handleGoogleLogin,
                icon: Icons.g_mobiledata,
                label: 'Google',
                colors: const [Color(0xFF4285F4), Color(0xFF357AE8)],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildOAuthButton(
                onTap: _handleGitHubLogin,
                icon: Icons.code,
                label: 'GitHub',
                colors: const [Color(0xFF24292E), Color(0xFF1B1F23)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildOAuthButton(
          onTap: _handleMicrosoftLogin,
          icon: Icons.business,
          label: 'Microsoft',
          colors: const [Color(0xFF00A4EF), Color(0xFF0078D4)],
        ),
      ],
    );
    
    if (isWide) {
      return ClipRect(
        key: const ValueKey('login_form'),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.3),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.8),
                      Colors.white.withValues(alpha: 0.6),
                    ],
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 60,
            vertical: 80,
          ),
          child: Center(
            child: SingleChildScrollView(
              child: loginContent,
            ),
          ),
        ),
      );
    }
    
    return Container(
      key: const ValueKey('login_form'),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 32),
      constraints: const BoxConstraints(maxWidth: 450),
      child: loginContent,
    );
  }


Widget _buildRegisterForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    
    final registerContent = Column(
      mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: _isLoading
                                ? null
                                : () => setState(() => _isRegistering = false),
                            icon: Icon(
                              Icons.arrow_back,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            '创建账号',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'PingFangSC',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '加入 Dext，开始创建问卷',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.black.withValues(alpha: 0.5),
                      fontFamily: 'PingFangSC',
                    ),
                  ),
                  const SizedBox(height: 32),
                  FTextField(
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                    label: const Text('用户名'),
                    hint: '3-12个字符',
                    textInputAction: TextInputAction.next,
                    onEditingComplete: () =>
                        FocusScope.of(context).requestFocus(_emailFocus),
                  ),
                  const SizedBox(height: 16),
                  FTextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    label: const Text('邮箱（建议填写）'),
                    hint: '用于找回密码',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onEditingComplete: () =>
                        FocusScope.of(context).requestFocus(_emailCodeFocus),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FTextField(
                          controller: _emailCodeController,
                          focusNode: _emailCodeFocus,
                          label: const Text('邮箱验证码'),
                          hint: '6位数字',
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          maxLength: 6,
                          enabled: _emailController.text.trim().isNotEmpty,
                          onEditingComplete: () =>
                              FocusScope.of(context).requestFocus(_passwordFocus),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 60,
                        child: Container(
                          decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: (_isLoading || _emailCodeSent || _emailController.text.trim().isEmpty)
                                ? [
                                    Colors.grey.withValues(alpha: 0.3),
                                    Colors.grey.withValues(alpha: 0.2),
                                  ]
                                : [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: (_isLoading || _emailCodeSent || _emailController.text.trim().isEmpty)
                                ? null
                                : _sendEmailCode,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Center(
                                child: Text(
                                  _emailCodeSent
                                      ? '$_emailCodeCountdown秒'
                                      : '发送',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FTextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    label: const Text('密码'),
                    hint: '8-64个字符',
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    onEditingComplete: () =>
                        FocusScope.of(context).requestFocus(_confirmFocus),
                  ),
                  const SizedBox(height: 16),
                  FTextField(
                    controller: _confirmPasswordController,
                    focusNode: _confirmFocus,
                    label: const Text('确认密码'),
                    hint: '请再次输入密码',
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    onEditingComplete: () =>
                        FocusScope.of(context).requestFocus(_captchaFocus),
                  ),
                  const SizedBox(height: 16),
                  _buildCaptchaCard(),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _agreeToTerms,
                          onChanged: (val) =>
                              setState(() => _agreeToTerms = val ?? false),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            children: [
                              Text(
                                '我已阅读并同意 ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : Colors.black.withValues(alpha: 0.7),
                                ),
                              ),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: _launchPrivacyPolicy,
                                  child: Text(
                                    '隐私政策',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.primary,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: (_isLoading || !_agreeToTerms)
                            ? [
                                Colors.grey.withValues(alpha: 0.3),
                                Colors.grey.withValues(alpha: 0.2),
                              ]
                                : [
                                    Colors.black.withValues(alpha: 0.85),
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: (_isLoading || !_agreeToTerms || isDark)
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (_isLoading || !_agreeToTerms) ? null : _handleRegister,
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  '注册',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'PingFangSC',
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
    
    if (isWide) {
      return ClipRect(
        key: const ValueKey('register_form'),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.3),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.8),
                      Colors.white.withValues(alpha: 0.6),
                    ],
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 60,
            vertical: 80,
          ),
          child: Center(
            child: SingleChildScrollView(
              child: registerContent,
            ),
          ),
        ),
      );
    }
    
    return Container(
      key: const ValueKey('register_form'),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 32),
      constraints: const BoxConstraints(maxWidth: 450),
      child: registerContent,
    );
  }

  Widget _buildResetPasswordForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    
    final resetPasswordContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _isResettingPassword = false;
                            _usernameController.clear();
                            _emailController.clear();
                            _emailCodeController.clear();
                            _passwordController.clear();
                            _confirmPasswordController.clear();
                            _captchaController.clear();
                            _emailCodeSent = false;
                            _emailCodeCountdown = 0;
                            _countdownTimer?.cancel();
                          });
                          _fetchCaptcha();
                        },
                  icon: Icon(
                    Icons.arrow_back,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
            Center(
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                  ],
                ).createShader(bounds),
                child: const Text(
                  '重置密码',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'PingFangSC',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '通过邮箱验证码重置您的密码',
          style: TextStyle(
            fontSize: 14,
            color: isDark
                ? Colors.white.withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.5),
            fontFamily: 'PingFangSC',
          ),
        ),
        const SizedBox(height: 32),
        FTextField(
          controller: _emailController,
          focusNode: _emailFocus,
          label: const Text('邮箱'),
          hint: '请输入注册时的邮箱',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onEditingComplete: () =>
              FocusScope.of(context).requestFocus(_captchaFocus),
        ),
        const SizedBox(height: 16),
        _buildCaptchaCard(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FTextField(
                controller: _emailCodeController,
                focusNode: _emailCodeFocus,
                label: const Text('邮箱验证码'),
                hint: '6位数字',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                maxLength: 6,
                enabled: _emailController.text.trim().isNotEmpty,
                onEditingComplete: () =>
                    FocusScope.of(context).requestFocus(_passwordFocus),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 60,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: (_isLoading || _emailCodeSent || _emailController.text.trim().isEmpty)
                        ? [
                            Colors.grey.withValues(alpha: 0.3),
                            Colors.grey.withValues(alpha: 0.2),
                          ]
                        : [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: (_isLoading || _emailCodeSent || _emailController.text.trim().isEmpty)
                        ? null
                        : _sendEmailCode,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Text(
                          _emailCodeSent
                              ? '$_emailCodeCountdown秒'
                              : '发送',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FTextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          label: const Text('新密码'),
          hint: '8-64个字符',
          obscureText: true,
          textInputAction: TextInputAction.next,
          onEditingComplete: () =>
              FocusScope.of(context).requestFocus(_confirmFocus),
        ),
        const SizedBox(height: 16),
        FTextField(
          controller: _confirmPasswordController,
          focusNode: _confirmFocus,
          label: const Text('确认新密码'),
          hint: '请再次输入新密码',
          obscureText: true,
          textInputAction: TextInputAction.done,
          onEditingComplete: _isLoading ? null : _handleResetPassword,
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isLoading
                  ? [
                      Colors.grey.withValues(alpha: 0.3),
                      Colors.grey.withValues(alpha: 0.2),
                    ]
                  : [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black.withValues(alpha: 0.7),
                    ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: (_isLoading || isDark)
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isLoading ? null : _handleResetPassword,
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        '重置密码',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'PingFangSC',
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
    
    if (isWide) {
      return ClipRect(
        key: const ValueKey('reset_password_form'),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.3),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.8),
                      Colors.white.withValues(alpha: 0.6),
                    ],
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 60,
            vertical: 80,
          ),
          child: Center(
            child: SingleChildScrollView(
              child: resetPasswordContent,
            ),
          ),
        ),
      );
    }
    
    return Container(
      key: const ValueKey('reset_password_form'),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 32),
      constraints: const BoxConstraints(maxWidth: 450),
      child: resetPasswordContent,
    );
  }
}
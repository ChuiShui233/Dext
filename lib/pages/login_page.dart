import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaption;
import '../widgets/window_caption.dart';
import '../main.dart' show isDesktop;
import '../services/api_service.dart';
import '../services/oauth_service.dart';
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

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();
  // 添加焦点控制
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _captchaFocus = FocusNode();
  
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _agreeToTerms = false;
  // 默认使用滑块验证

  final _apiService = ApiService();
  final _oauthService = OAuthService();
  String? _captchaId;
  String? _captchaImage;
  // 缓存解码后的验证码字节，避免每次build解码导致闪烁
  Uint8List? _captchaBytes;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchCaptcha();
    // 启动定时任务每10分钟刷新令牌
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _refreshToken();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _captchaFocus.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  String hashPassword(String password) {
    // 这里应该使用更安全的密码哈希方法
    return password;
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://wucode.xyz/privacy-policy');
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
      // 预先解码，避免在build中重复base64解码造成重绘抖动
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

  // 在登录成功后记录信息
  void _recordLoginInfo(String token, DateTime expires) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('token_expiry', expires.toIso8601String());
  }

  Future<void> _refreshToken() async {
    try {
      final newToken = await ApiService().refreshToken();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', newToken);
      // 更新过期时间逻辑可以根据API返回的数据进行调整
    } catch (e) {
      if (!mounted) return;
      showErrorDialog('刷新令牌失败: $e');
    }
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
    
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _oauthService.signInWithGoogle();
      
      if (!mounted) return;
      
      if (result['success']) {
        final token = result['token'];
        final expires = result['expires'];
        
        widget.onLoginSuccess(token, expires);
        _recordLoginInfo(token, expires);
      } else {
        // 检查是否是用户取消或超时
        if (result['cancelled'] == true) {
          // 用户取消登录，不显示错误提示
          return;
        } else if (result['timeout'] == true) {
          showErrorDialog('登录超时，请重试');
        } else {
          showErrorDialog(result['error']);
        }
      }
    } catch (e) {
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
    
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _oauthService.signInWithGitHub();
      
      if (!mounted) return;
      
      if (result['success']) {
        final token = result['token'];
        final expires = result['expires'];
        
        widget.onLoginSuccess(token, expires);
        _recordLoginInfo(token, expires);
      } else {
        // 检查是否是用户取消或超时
        if (result['cancelled'] == true) {
          // 用户取消登录，不显示错误提示
          return;
        } else if (result['timeout'] == true) {
          showErrorDialog('登录超时，请重试');
        } else {
          showErrorDialog(result['error']);
        }
      }
    } catch (e) {
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
    
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _oauthService.signInWithMicrosoft();
      
      if (!mounted) return;
      
      if (result['success']) {
        final token = result['token'];
        final expires = result['expires'];
        
        widget.onLoginSuccess(token, expires);
        _recordLoginInfo(token, expires);
      } else {
        // 检查是否是用户取消或超时
        if (result['cancelled'] == true) {
          // 用户取消登录，不显示错误提示
          return;
        } else if (result['timeout'] == true) {
          showErrorDialog('登录超时，请重试');
        } else {
          showErrorDialog(result['error']);
        }
      }
    } catch (e) {
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

///哈哈不会再分个文件写判断的，千年屎山
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

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.register(
        username: _usernameController.text,
        password: hashPassword(_passwordController.text),
        captchaId: _captchaId ?? '',
        captchaValue: _captchaController.text.trim(),
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

  final content = AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    transitionBuilder: (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    child: _isRegistering ? _buildRegisterForm() : _buildLoginForm(),
  );

  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Scaffold(
    body: Stack(
      children: [
        // 背景层
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
      // 遮罩
      if (isDark)
        Container(
          color: Colors.black.withValues(alpha: 0.4),
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
        Center(
          child: SingleChildScrollView(
            child: isWide
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [content],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [content],
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
    return Column(
      children: [
        Row(
          children: [
            if (_captchaBytes != null)
              GestureDetector(
                onTap: _fetchCaptcha,
                child: RepaintBoundary(
                  child: SizedBox(
                    height: 48,
                    width: 120,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: <Widget>[
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      child: Image.memory(
                        _captchaBytes!,
                        key: ValueKey(_captchaId), // 仅当验证码变更时触发动画
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            if (_captchaImage == null)
             Expanded(
  child: SizedBox(
    width: 48,
    height: 48,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Builder(
          builder: (context) {
            final textColor = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
            return AnimatedDefaultTextStyle(
              duration: Duration.zero, // 禁止文字颜色渐变动画
              style: TextStyle(
                color: textColor,
                fontSize: 14,
              ),
              child: const Text('获取中...'),
            );
          },
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    ),
  ),
),

            const SizedBox(width: 8),
            Expanded(
              child: FTextField(
                controller: _captchaController,
                focusNode: _captchaFocus,
                label: const Text('验证码'),
                hint: '请输入图片中的验证码',
                textInputAction: TextInputAction.done,
                onEditingComplete: () => _isRegistering ? 
                  (_isLoading || !_agreeToTerms) ? null : _handleRegister() : 
                  _isLoading ? null : _handleLogin(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLoginForm() {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
    constraints: const BoxConstraints(maxWidth: 430),
    child: Material(
      color: Colors.transparent,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 12.0,
          sigmaY: 12.0,
          tileMode: TileMode.clamp,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: CupertinoColors.white.withAlpha(51), // 半透明背景
            border: Border.all(
              color: CupertinoDynamicColor.resolve(CupertinoColors.white, context)
                  .withAlpha(51),
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(12.0),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: Duration.zero,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color ?? Colors.black,
                  fontFamily: 'PingFangSC',
                ),
                child: const Text('登录'),
              ),
              const SizedBox(height: 20),
              FTextField(
                controller: _usernameController,
                focusNode: _usernameFocus,
                label: const Text('用户名'),
                hint: '请输入用户名',
                textInputAction: TextInputAction.next,
                onEditingComplete: () =>
                    FocusScope.of(context).requestFocus(_passwordFocus),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 20),
              _buildCaptchaCard(),
              const SizedBox(height: 20),
              FButton(
                onPress: _isLoading ? null : _handleLogin,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
              const SizedBox(height: 20),
              FButton(
                style: FButtonStyle.destructive,
                onPress: _isLoading ? null : () => setState(() => _isRegistering = true),
                child: const Text('注册'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.withValues(alpha: 0.5))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '或使用第三方登录',
                      style: TextStyle(
                        color: Colors.grey.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.withValues(alpha: 0.5))),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FButton(
                      style: FButtonStyle.outline,
                      onPress: _isLoading ? null : _handleGoogleLogin,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.g_mobiledata,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Google'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FButton(
                      style: FButtonStyle.outline,
                      onPress: _isLoading ? null : _handleGitHubLogin,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.code,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text('GitHub'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FButton(
                style: FButtonStyle.outline,
                onPress: _isLoading ? null : _handleMicrosoftLogin,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.business,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text('Microsoft'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}


Widget _buildRegisterForm() {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
    constraints: const BoxConstraints(maxWidth: 430),
    child: Material(
      color: Colors.transparent,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 12.0,
          sigmaY: 12.0,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: CupertinoColors.white.withAlpha(51),
            border: Border.all(
              color: CupertinoDynamicColor.resolve(CupertinoColors.white, context)
                  .withAlpha(51),
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(12.0),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部返回按钮 + 注册标题
              SizedBox(
  height: 40,
  child: Stack(
    alignment: Alignment.center,
    children: [
      // 返回按钮靠左
      Positioned(
        left: 0,
        child: FButton.icon(
          onPress: _isLoading ? null : () => setState(() => _isRegistering = false),
          child: Icon(FIcons.chevronLeft),
        ),
      ),
      // 注册文本居中，统一动画样式
      Center(
        child: AnimatedDefaultTextStyle(
          duration: Duration.zero,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.titleLarge?.color ?? Colors.black,
            fontFamily: 'PingFangSC',
          ),
          child: const Text('注册'),
        ),
      ),
    ],
  ),
),
              const SizedBox(height: 20),
              // 用户名
              FTextField(
                controller: _usernameController,
                focusNode: _usernameFocus,
                label: const Text('用户名'),
                hint: '请输入用户名',
                textInputAction: TextInputAction.next,
                onEditingComplete: () => FocusScope.of(context).requestFocus(_passwordFocus),
              ),
              const SizedBox(height: 20),
              // 密码
              FTextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                label: const Text('密码'),
                hint: '请输入密码',
                obscureText: true,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => FocusScope.of(context).requestFocus(_captchaFocus),
              ),
              const SizedBox(height: 20),
              // 验证码
              _buildCaptchaCard(),
              const SizedBox(height: 20),
              // 同意条款
              FCheckbox(
                label: const Text('同意隐私条款'),
                description: Row(
                  children: [
                    const Text('请阅读并同意我们的'),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _launchPrivacyPolicy,
                        child: const Text(
                          '隐私条款',
                          style: TextStyle(
                            color: Color.fromARGB(255, 184, 222, 247),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const Text('。'),
                  ],
                ),
                value: _agreeToTerms,
                onChange: (val) => setState(() => _agreeToTerms = val),
              ),
              const SizedBox(height: 20),
              // 注册按钮
              FButton(
                onPress: (_isLoading || !_agreeToTerms) ? null : _handleRegister,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('注册'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
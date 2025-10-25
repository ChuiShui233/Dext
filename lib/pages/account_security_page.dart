import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../widgets/frosted_oauth_dialog.dart';
import '../services/api_service.dart';
import '../services/oauth_service.dart';
import '../services/uri_handler_service.dart';
import '../models/user.dart';
import 'dart:async';
import '../widgets/frosted_glass_background.dart';
import '../widgets/top_safe_spacer.dart';

class AccountSecurityPage extends StatefulWidget {
  final ApiService apiService;
  final User? currentUser;
  final VoidCallback onUserUpdated;

  const AccountSecurityPage({
    super.key,
    required this.apiService,
    this.currentUser,
    required this.onUserUpdated,
  });

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
    _refreshUserInfo();
  }

  Future<void> _refreshUserInfo() async {
    try {
      final user = await widget.apiService.getCurrentUserHandler();
      if (mounted) {
        setState(() {
          _user = user;
        });
        widget.onUserUpdated();
      }
    } catch (e) {
      if (kDebugMode) {
        print('刷新用户信息失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _user?.email;
    final hasEmail = email != null && email.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          const FrostedGlassBackground(),
          Column(
            children: [
              const TopSafeSpacer(),
              FHeader.nested(
                title: const Text('账号安全'),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () {
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildSectionCard(
                        context,
                        title: '邮箱管理',
                        icon: Icons.email_outlined,
                        children: [
                          _buildListTile(
                            leading: Icon(Icons.email, color: theme.colorScheme.primary),
                            title: const Text('邮箱绑定'),
                            subtitle: Text(
                              _user?.email.isNotEmpty == true 
                                  ? '已绑定: ${_user!.email}' 
                                  : '未绑定邮箱',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            onTap: () => hasEmail ? _showChangeEmailDialog() : _showBindEmailDialog(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _buildSectionCard(
                        context,
                        title: '密码管理',
                        icon: Icons.lock_outline,
                        children: [
                          _buildListTile(
                            leading: Icon(Icons.vpn_key, color: theme.colorScheme.primary),
                            title: const Text('修改密码'),
                            subtitle: Text(
                              '使用旧密码或邮箱验证码修改',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            onTap: _showChangePasswordDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // OAuth账号绑定卡片
                      _buildSectionCard(
                        context,
                        title: '第三方账号',
                        icon: Icons.link,
                        children: [
                          _buildOAuthListTile('google', Icons.g_mobiledata, Color(0xFF4285F4), 'Google账号'),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.dividerColor.withValues(alpha: 0.1),
                          ),
                          _buildOAuthListTile('github', Icons.code, Color(0xFF24292E), 'GitHub账号'),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.dividerColor.withValues(alpha: 0.1),
                          ),
                          _buildOAuthListTile('microsoft', Icons.business, Color(0xFF00A4EF), 'Microsoft账号'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildListTile({
    Widget? leading,
    required Widget title,
    Widget? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      onTap: onTap,
    );
  }

  // 构建OAuth列表项
  Widget _buildOAuthListTile(String provider, IconData icon, Color iconColor, String title) {
    final oauthBindings = _user?.oauthBindings;
    bool isBound = false;
    String? providerName;
    
    if (oauthBindings != null) {
      switch (provider) {
        case 'google':
          isBound = oauthBindings.googleBound;
          break;
        case 'github':
          isBound = oauthBindings.githubBound;
          break;
        case 'microsoft':
          isBound = oauthBindings.microsoftBound;
          break;
      }
      
      final binding = oauthBindings.bindings
          .where((b) => b.provider == provider)
          .firstOrNull;
      if (binding != null) {
        providerName = binding.providerName ?? binding.providerUsername;
      }
    }

    return _buildListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title),
      subtitle: Text(
        isBound 
            ? '已绑定${providerName != null ? ': $providerName' : ''}' 
            : '未绑定',
        style: const TextStyle(
          fontSize: 12, 
        ),
      ),
      trailing: TextButton(
        onPressed: () => isBound ? _unbindOAuth(provider) : _bindOAuth(provider),
        child: Text(isBound ? '解绑' : '绑定'),
      ),
    );
  }

  // OAuth绑定操作
  void _bindOAuth(String provider) async {
    BuildContext? dialogContext;
    bool dialogShown = false;
    
    void closeDialog() {
      if (dialogShown && dialogContext != null) {
        try {
          Navigator.of(dialogContext!).pop();
        } catch (_) {
        }
        dialogShown = false;
        dialogContext = null;
      }
    }
    
    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            dialogContext = context;
            return FrostedOAuthDialog(
              providerName: _getProviderDisplayName(provider),
              waitingText: '请在浏览器中完成授权，或点击取消',
              onCancel: () {
                // 取消OAuth等待
                UriHandlerService.cancelAllPendingCallbacks();
                closeDialog();
              },
            );
          },
        );
        dialogShown = true;
      }

      // 获取OAuth服务实例
      final oauthService = OAuthService();
      
      // 执行OAuth授权流程
      Map<String, dynamic> result;
      switch (provider) {
        case 'google':
          result = await oauthService.signInWithGoogle();
          break;
        case 'github':
          result = await oauthService.signInWithGitHub();
          break;
        case 'microsoft':
          result = await oauthService.signInWithMicrosoft();
          break;
        default:
          throw Exception('不支持的OAuth提供商: $provider');
      }
      
      if (result['success'] == true && result['token'] != null) {
        // OAuth授权成功，现在调用绑定API将OAuth账号绑定到当前主账号
        try {
          await widget.apiService.bindOAuth(
            provider: provider,
            accessToken: result['token'],
          );
          
          closeDialog();
          
          await widget.apiService.clearUserCache();
          await _refreshUserInfo();
          
          if (mounted) {
            showFToast(
              context: context,
              alignment: FToastAlignment.bottomRight,
              title: const Text('绑定成功'),
              description: Text('${_getProviderDisplayName(provider)}账号已成功绑定'),
              suffixBuilder: (context, entry, _) => IntrinsicHeight(
                child: FButton(
                  style: context.theme.buttonStyles.primary.copyWith(
                    contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                      textStyle: FWidgetStateMap.all(
                        context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                      ),
                    ),
                  ),
                  onPress: entry.dismiss,
                  child: const Text('关闭'),
                ),
              ),
            );
          }
        } catch (bindError) {
          closeDialog();
          
          if (mounted) {
            showFToast(
              context: context,
              alignment: FToastAlignment.bottomRight,
              title: const Text('绑定失败'),
              description: Text(bindError.toString()),
              suffixBuilder: (context, entry, _) => IntrinsicHeight(
                child: FButton(
                  style: context.theme.buttonStyles.primary.copyWith(
                    contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                      textStyle: FWidgetStateMap.all(
                        context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                      ),
                    ),
                  ),
                  onPress: entry.dismiss,
                  child: const Text('关闭'),
                ),
              ),
            );
          }
        }
      } else {
        closeDialog();
        
        if (mounted) {
          showFToast(
            context: context,
            alignment: FToastAlignment.bottomRight,
            title: const Text('授权失败'),
            description: const Text('OAuth授权失败，请重试'),
            suffixBuilder: (context, entry, _) => IntrinsicHeight(
              child: FButton(
                style: context.theme.buttonStyles.primary.copyWith(
                  contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                    textStyle: FWidgetStateMap.all(
                      context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                    ),
                  ),
                ),
                onPress: entry.dismiss,
                child: const Text('关闭'),
              ),
            ),
          );
        }
      }
    } catch (e) {
      closeDialog();
      
      if (mounted) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('绑定失败'),
          description: Text(e.toString()),
          suffixBuilder: (context, entry, _) => IntrinsicHeight(
            child: FButton(
              style: context.theme.buttonStyles.primary.copyWith(
                contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                  textStyle: FWidgetStateMap.all(
                    context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                  ),
                ),
              ),
              onPress: entry.dismiss,
              child: const Text('关闭'),
            ),
          ),
        );
      }
    }
  }

  // OAuth解绑操作
  void _unbindOAuth(String provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认解绑'),
        body: Text('确定要解绑${_getProviderDisplayName(provider)}账号吗？'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    BuildContext? dialogContext;
    bool dialogShown = false;
    
    void closeDialog() {
      if (dialogShown && dialogContext != null) {
        try {
          Navigator.of(dialogContext!).pop();
        } catch (_) {
        }
        dialogShown = false;
        dialogContext = null;
      }
    }
    
    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            dialogContext = context;
            return FrostedOAuthDialog(
              providerName: _getProviderDisplayName(provider),
              waitingText: '正在解绑账号，请稍候…',
              onCancel: () {
                // 解绑过程不支持取消请求，这里仅关闭提示框
                closeDialog();
              },
            );
          },
        );
        dialogShown = true;
      }

      // 调用解绑API
      await widget.apiService.unbindOAuth(provider: provider);
      
      closeDialog();
      
      await widget.apiService.clearUserCache();
      await _refreshUserInfo();
      
      if (mounted) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('解绑成功'),
          description: Text('${_getProviderDisplayName(provider)}账号已成功解绑'),
          suffixBuilder: (context, entry, _) => IntrinsicHeight(
            child: FButton(
              style: context.theme.buttonStyles.primary.copyWith(
                contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                  textStyle: FWidgetStateMap.all(
                    context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                  ),
                ),
              ),
              onPress: entry.dismiss,
              child: const Text('关闭'),
            ),
          ),
        );
      }
    } catch (e) {
      closeDialog();
      
      if (mounted) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('解绑失败'),
          description: Text(e.toString()),
          suffixBuilder: (context, entry, _) => IntrinsicHeight(
            child: FButton(
              style: context.theme.buttonStyles.primary.copyWith(
                contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                  textStyle: FWidgetStateMap.all(
                    context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                  ),
                ),
              ),
              onPress: entry.dismiss,
              child: const Text('关闭'),
            ),
          ),
        );
      }
    }
  }

  String _getProviderDisplayName(String provider) {
    switch (provider) {
      case 'google':
        return 'Google';
      case 'github':
        return 'GitHub';
      case 'microsoft':
        return 'Microsoft';
      default:
        return provider;
    }
  }

  void _showBindEmailDialog() {
    showDialog(
      context: context,
      builder: (context) => _BindEmailDialog(
        apiService: widget.apiService,
        onSuccess: () {
          _refreshUserInfo();
          widget.onUserUpdated();
        },
      ),
    );
  }

  void _showChangeEmailDialog() {
    showDialog(
      context: context,
      builder: (context) => _ChangeEmailDialog(
        apiService: widget.apiService,
        currentEmail: _user?.email ?? '',
        onSuccess: () {
          _refreshUserInfo();
          widget.onUserUpdated();
        },
      ),
    );
  }

  void _showChangePasswordDialog() {
    final email = _user?.email;
    final hasEmail = email != null && email.isNotEmpty;
    
    showDialog(
      context: context,
      builder: (context) => _ChangePasswordDialog(
        apiService: widget.apiService,
        hasEmail: hasEmail,
        onSuccess: () {
          widget.onUserUpdated();
        },
      ),
    );
  }
}

// ==================== 绑定邮箱对话框 ====================
class _BindEmailDialog extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSuccess;

  const _BindEmailDialog({
    required this.apiService,
    required this.onSuccess,
  });

  @override
  State<_BindEmailDialog> createState() => _BindEmailDialogState();
}

class _BindEmailDialogState extends State<_BindEmailDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();
  final _emailCodeController = TextEditingController();
  
  bool _isLoading = false;
  bool _codeSent = false;
  int _countdown = 0;
  Timer? _timer;
  String? _captchaId;
  String? _captchaImage;

  @override
  void initState() {
    super.initState();
    _fetchCaptcha();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _captchaController.dispose();
    _emailCodeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchCaptcha() async {
    try {
      final captcha = await widget.apiService.getTextCaptcha();
      if (mounted) {
        setState(() {
          _captchaId = captcha['captchaId'];
          _captchaImage = captcha['data'];
        });
      }
    } catch (e) {
      // 静默失败
    }
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('请输入邮箱地址');
      return;
    }
    if (_captchaController.text.trim().isEmpty) {
      _showError('请输入图形验证码');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.apiService.sendChangeEmailCode(
        email: email,
        captchaId: _captchaId ?? '',
        captchaValue: _captchaController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _codeSent = true;
          _countdown = 60;
        });
        _startCountdown();
        _showSuccess('验证码已发送');
      }
    } catch (e) {
      _showError(e.toString());
      _fetchCaptcha();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          timer.cancel();
          _codeSent = false;
        }
      });
    });
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final code = _emailCodeController.text.trim();

    if (email.isEmpty || password.isEmpty || code.isEmpty) {
      _showError('请填写完整信息');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 调用绑定邮箱API（使用changeEmail，因为后端使用相同的验证流程）
      await widget.apiService.changeEmail(
        newEmail: email,
        password: password,
        code: code,
      );
      
      // 清除用户缓存，强制刷新
      await widget.apiService.clearUserCache();
      
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        _showSuccess('邮箱绑定成功');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      showFToast(
        context: context,
        title: Text(message),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      showFToast(
        context: context,
        title: Text(message),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FDialog(
      direction: Axis.horizontal,
      title: const Text('绑定邮箱'),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FTextField(
            controller: _emailController,
            label: const Text('邮箱地址'),
            hint: '请输入邮箱',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          FTextField(
            controller: _passwordController,
            label: const Text('账号密码'),
            hint: '请输入密码以验证身份',
            obscureText: true,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_captchaImage != null)
                GestureDetector(
                  onTap: _fetchCaptcha,
                  child: Container(
                    height: 50,
                    width: 120,
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
                          Uri.parse(_captchaImage!).data!.contentAsBytes(),
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
                  height: 50,
                  width: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.withValues(alpha: 0.1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '加载中',
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: 0.7),
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
                  label: const Text('图形验证码'),
                  hint: '点击图片刷新',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FTextField(
                  controller: _emailCodeController,
                  label: const Text('邮箱验证码'),
                  hint: '6位数字',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
              ),
              const SizedBox(width: 12),
              FButton(
                onPress: (_isLoading || _codeSent) ? null : _sendCode,
                child: Text(_codeSent ? '$_countdown秒' : '发送'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline,
          onPress: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FButton(
          onPress: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确认'),
        ),
      ],
    );
  }
}

// ==================== 更换邮箱对话框 ====================
class _ChangeEmailDialog extends StatefulWidget {
  final ApiService apiService;
  final String currentEmail;
  final VoidCallback onSuccess;

  const _ChangeEmailDialog({
    required this.apiService,
    required this.currentEmail,
    required this.onSuccess,
  });

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();
  final _emailCodeController = TextEditingController();
  
  bool _isLoading = false;
  bool _codeSent = false;
  int _countdown = 0;
  Timer? _timer;
  String? _captchaId;
  String? _captchaImage;

  @override
  void initState() {
    super.initState();
    _fetchCaptcha();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    _emailCodeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchCaptcha() async {
    try {
      final captcha = await widget.apiService.getTextCaptcha();
      if (mounted) {
        setState(() {
          _captchaId = captcha['captchaId'];
          _captchaImage = captcha['data'];
        });
      }
    } catch (e) {
      // 静默失败
    }
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('请输入新邮箱地址');
      return;
    }
    if (email == widget.currentEmail) {
      _showError('新邮箱不能与当前邮箱相同');
      return;
    }
    if (_captchaController.text.trim().isEmpty) {
      _showError('请输入图形验证码');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.apiService.sendChangeEmailCode(
        email: email,
        captchaId: _captchaId ?? '',
        captchaValue: _captchaController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _codeSent = true;
          _countdown = 60;
        });
        _startCountdown();
        _showSuccess('验证码已发送');
      }
    } catch (e) {
      _showError(e.toString());
      _fetchCaptcha();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          timer.cancel();
          _codeSent = false;
        }
      });
    });
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final code = _emailCodeController.text.trim();

    if (email.isEmpty || password.isEmpty || code.isEmpty) {
      _showError('请填写完整信息');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 调用更换邮箱API
      await widget.apiService.changeEmail(
        newEmail: email,
        password: password,
        code: code,
      );
      
      // 清除用户缓存，强制刷新
      await widget.apiService.clearUserCache();

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        _showSuccess('邮箱更换成功');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      showFToast(
        context: context,
        title: Text(message),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      showFToast(
        context: context,
        title: Text(message),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FDialog(
      direction: Axis.horizontal,
      title: const Text('更换邮箱'),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '当前邮箱：${widget.currentEmail}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          FTextField(
            controller: _emailController,
            label: const Text('新邮箱地址'),
            hint: '请输入新邮箱',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          FTextField(
            controller: _passwordController,
            label: const Text('账号密码'),
            hint: '请输入密码以验证身份',
            obscureText: true,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_captchaImage != null)
                GestureDetector(
                  onTap: _fetchCaptcha,
                  child: Container(
                    height: 50,
                    width: 120,
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
                          Uri.parse(_captchaImage!).data!.contentAsBytes(),
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
                  height: 50,
                  width: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.withValues(alpha: 0.1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '加载中',
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: 0.7),
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
                  label: const Text('图形验证码'),
                  hint: '点击图片刷新',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FTextField(
                  controller: _emailCodeController,
                  label: const Text('邮箱验证码'),
                  hint: '6位数字',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
              ),
              const SizedBox(width: 12),
              FButton(
                onPress: (_isLoading || _codeSent) ? null : _sendCode,
                child: Text(_codeSent ? '$_countdown秒' : '发送'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline,
          onPress: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FButton(
          onPress: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确认'),
        ),
      ],
    );
  }
}

// ==================== 修改密码对话框 ====================
class _ChangePasswordDialog extends StatefulWidget {
  final ApiService apiService;
  final bool hasEmail;
  final VoidCallback onSuccess;

  const _ChangePasswordDialog({
    required this.apiService,
    required this.hasEmail,
    required this.onSuccess,
  });

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailCodeController = TextEditingController();
  
  bool _isLoading = false;
  bool _useEmailVerification = false;
  bool _isCodeSending = false;
  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _emailCodeController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendEmailCode() async {
    setState(() => _isCodeSending = true);
    
    try {
      final user = await widget.apiService.getCurrentUserHandler();
      if (user.email.isEmpty) {
        _showError('您还未绑定邮箱，无法使用邮箱验证码修改密码');
        return;
      }
      
      await widget.apiService.sendEmailCodeForPasswordChange();
      
      _showSuccess('验证码已发送到您的邮箱');
      _startCountdown();
    } catch (e) {
      _showError('发送验证码失败：${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isCodeSending = false);
      }
    }
  }
  
  void _startCountdown() {
    setState(() => _countdown = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _countdown = 0);
        }
      } else {
        if (mounted) {
          setState(() => _countdown--);
        }
      }
    });
  }

  Future<void> _submit() async {
    final oldPassword = _oldPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final emailCode = _emailCodeController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showError('请填写完整信息');
      return;
    }

    if (newPassword != confirmPassword) {
      _showError('两次输入的密码不一致');
      return;
    }

    if (newPassword.length < 8 || newPassword.length > 64) {
      _showError('密码长度必须在8-64个字符之间');
      return;
    }

    if (_useEmailVerification) {
      if (emailCode.isEmpty) {
        _showError('请输入邮箱验证码');
        return;
      }
    } else {
      if (oldPassword.isEmpty) {
        _showError('请输入旧密码');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_useEmailVerification) {
        final user = await widget.apiService.getCurrentUserHandler();
        if (user.email.isEmpty) {
          _showError('您还未绑定邮箱，无法使用邮箱验证码修改密码');
          return;
        }
        
        await widget.apiService.changePasswordWithEmail(
          code: emailCode,
          newPassword: newPassword,
        );
      } else {
        await widget.apiService.changePassword(
          oldPassword: oldPassword,
          newPassword: newPassword,
        );
      }
      
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        _showSuccess('密码修改成功');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      showFToast(
        context: context,
        title: Text(message),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      showFToast(
        context: context,
        title: Text(message),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FDialog(
      direction: Axis.horizontal,
      title: const Text('修改密码'),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hasEmail)
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: Checkbox(
                    value: _useEmailVerification,
                    onChanged: (value) {
                      setState(() {
                        _useEmailVerification = value ?? false;
                      });
                    },
                  ),
                ),
                const Text('使用邮箱验证码修改'),
              ],
            ),
          const SizedBox(height: 8),
          if (!_useEmailVerification)
            FTextField(
              controller: _oldPasswordController,
              label: const Text('旧密码'),
              hint: '请输入旧密码',
              obscureText: true,
            ),
          if (_useEmailVerification) ...[
            Row(
              children: [
                Expanded(
                  child: FTextField(
                    controller: _emailCodeController,
                    label: const Text('邮箱验证码'),
                    hint: '请输入6位验证码',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                FButton(
                  style: FButtonStyle.outline,
                  onPress: (_isCodeSending || _countdown > 0) ? null : _sendEmailCode,
                  child: _isCodeSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_countdown > 0 ? '${_countdown}s' : '发送验证码'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '验证码将发送到您绑定的邮箱',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          FTextField(
            controller: _newPasswordController,
            label: const Text('新密码'),
            hint: '8-64个字符',
            obscureText: true,
          ),
          const SizedBox(height: 16),
          FTextField(
            controller: _confirmPasswordController,
            label: const Text('确认新密码'),
            hint: '请再次输入新密码',
            obscureText: true,
          ),
        ],
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline,
          onPress: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FButton(
          onPress: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确认'),
        ),
      ],
    );
  }
}

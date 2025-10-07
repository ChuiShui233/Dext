//ai太好用了你知道吗
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../services/api_service.dart';
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
      }
    } catch (e) {
      // 静默失败，使用传入的用户信息
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
                      // 邮箱绑定卡片
                      _buildSectionCard(
                        context,
                        title: '邮箱绑定',
                        icon: Icons.email_outlined,
                        children: [
                          _buildListTile(
                            leading: Icon(Icons.email, color: theme.colorScheme.primary),
                            title: Text(hasEmail ? '更换邮箱' : '绑定邮箱'),
                            subtitle: Text(
                              hasEmail ? (_user?.email ?? '') : '绑定邮箱后可用于找回密码',
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

                      // 密码管理卡片
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
                          _buildListTile(
                            leading: const Icon(Icons.g_mobiledata, color: Color(0xFF4285F4)),
                            title: const Text('Google账号'),
                            subtitle: const Text(
                              '未绑定',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            trailing: TextButton(
                              onPressed: () => _bindOAuthAccount('google'),
                              child: const Text('绑定'),
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.dividerColor.withValues(alpha: 0.1),
                          ),
                          _buildListTile(
                            leading: const Icon(Icons.code, color: Color(0xFF24292E)),
                            title: const Text('GitHub账号'),
                            subtitle: const Text(
                              '未绑定',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            trailing: TextButton(
                              onPressed: () => _bindOAuthAccount('github'),
                              child: const Text('绑定'),
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.dividerColor.withValues(alpha: 0.1),
                          ),
                          _buildListTile(
                            leading: const Icon(Icons.business, color: Color(0xFF00A4EF)),
                            title: const Text('Microsoft账号'),
                            subtitle: const Text(
                              '未绑定',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            trailing: TextButton(
                              onPressed: () => _bindOAuthAccount('microsoft'),
                              child: const Text('绑定'),
                            ),
                          ),
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

  // 绑定邮箱对话框
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

  // 更换邮箱对话框
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

  // 修改密码对话框
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

  // 绑定OAuth账号
  void _bindOAuthAccount(String provider) {
    showFToast(
      context: context,
      title: const Text('功能开发中'),
      description: Text('$provider账号绑定功能即将上线'),
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
      await widget.apiService.sendEmailVerificationCode(
        email: email,
        purpose: 'change_email',
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
    final code = _emailCodeController.text.trim();

    if (email.isEmpty || code.isEmpty) {
      _showError('请填写完整信息');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 调用绑定邮箱API（使用change_email目的，因为绑定和更换使用相同的验证流程）
      await widget.apiService.changeEmail(
        newEmail: email,
        code: code,
      );
      
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: Image.memory(
                        Uri.parse(_captchaImage!).data!.contentAsBytes(),
                        key: ValueKey(_captchaId),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              if (_captchaImage == null)
                Container(
                  height: 50,
                  width: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
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
      await widget.apiService.sendEmailVerificationCode(
        email: email,
        purpose: 'change_email',
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
    final code = _emailCodeController.text.trim();

    if (email.isEmpty || code.isEmpty) {
      _showError('请填写完整信息');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 调用更换邮箱API（使用公共方法）
      await widget.apiService.changeEmail(
        newEmail: email,
        code: code,
      );

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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: Image.memory(
                        Uri.parse(_captchaImage!).data!.contentAsBytes(),
                        key: ValueKey(_captchaId),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              if (_captchaImage == null)
                Container(
                  height: 50,
                  width: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
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
  
  bool _isLoading = false;
  bool _useEmailVerification = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oldPassword = _oldPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

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

    if (!_useEmailVerification && oldPassword.isEmpty) {
      _showError('请输入旧密码');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 调用修改密码API（暂时使用模拟，等待后端实现）
      // TODO: 后端需要实现 POST /api/user/change-password
      await Future.delayed(const Duration(seconds: 1));
      
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
                Checkbox(
                  value: _useEmailVerification,
                  onChanged: (value) {
                    setState(() {
                      _useEmailVerification = value ?? false;
                    });
                  },
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
          if (_useEmailVerification)
            const Text(
              '邮箱验证码修改功能开发中...',
              style: TextStyle(color: Colors.grey),
            ),
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

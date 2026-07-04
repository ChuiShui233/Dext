import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../components/privacy_policy_service.dart';
import '../../services/settings_service.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:io';
import '../../services/config.dart';
import '../frame_page.dart' show mobileSidebarOpen;
import '../../widgets/crop_image_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'account_settings_page.dart';
import '../../components/loading_indicator.dart';
import 'general_settings_page.dart';
import 'package:provider/provider.dart';
import '../../providers/user_info_provider.dart';
import '../../providers/theme_provider.dart';

class HomeSettingsContent extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onChangeAvatar;
  final ApiService apiService;

  const HomeSettingsContent({
    super.key,
    required this.onLogout,
    required this.onChangeAvatar,
    required this.apiService,
  });

  @override
  State<HomeSettingsContent> createState() => _HomeSettingsContentState();
}

class _HomeSettingsContentState extends State<HomeSettingsContent> {
  User? _currentUser;
  String _appVersion = '加载中...';
  static String _cachedAppVersion = '';
  // 桌面布局：左侧设置栏可调整宽度
  double _settingsPanelWidth = 420.0;
  static const double _settingsPanelMinWidth = 320.0;
  static const double _settingsPanelMaxWidth = 640.0;
  // 桌面布局：右侧内容区域的本地 Navigator，用于在右侧空白区域打开页面
  final GlobalKey<NavigatorState> _rightPaneNavigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // 若全局已有用户信息，优先使用，避免重复请求
    // 注意：此处不能直接在initState使用context.watch，使用read即可
    final existing = mounted ? context.read<UserInfoProvider>().user : null;
    if (existing != null) {
      _currentUser = existing;
    } else {
      _fetchUserData();
    }
    // 从设置服务加载桌面侧栏宽度
    try {
      final w = SettingsService().settingsPanelWidth;
      _settingsPanelWidth = w.clamp(_settingsPanelMinWidth, _settingsPanelMaxWidth);
    } catch (_) {}
    _loadAppVersion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final providerUser = Provider.of<UserInfoProvider>(context, listen: true).user;
    if (providerUser != null && providerUser != _currentUser) {
      setState(() {
        _currentUser = providerUser;
      });
    }
  }
  Future<void> _loadAppVersion() async {
    if (_cachedAppVersion.isNotEmpty) {
      _appVersion = _cachedAppVersion;
      if (mounted) setState(() {});
    }
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      _cachedAppVersion = version;
      if (mounted) {
        setState(() {
          _appVersion = version;
        });
      }
    } catch (e) {
      if (_cachedAppVersion.isEmpty && mounted) {
        setState(() {
          _appVersion = '未知';
        });
      }
    }
  }


  Future<void> _fetchUserData() async {
    try {
      final user = await widget.apiService.getCurrentUserHandler();

      if (mounted) {
        setState(() {
          _currentUser = user;
        });

        if (mounted) {
          context.read<UserInfoProvider>().setUser(user);
        }
      }
    } catch (e) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text('获取用户信息失败: $e'),
        );
      }
    }
  }

    Future<void> _launchPrivacyPolicy() async {
      await PrivacyPolicyService.launchPrivacyPolicy(context: context);
    }

  Future<void> _changeAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? imageBytes;

        if (file.bytes != null) {
          // Web 和桌面端优先使用 bytes
          imageBytes = file.bytes!;
        } else if (file.path != null) {
          final imageFile = File(file.path!);
          imageBytes = await imageFile.readAsBytes();
        } else {
          throw '无法获取图片数据';
        }

        if (!mounted) return;
        final Uint8List? croppedBytes = await showDialog<Uint8List>(
          context: context,
          barrierDismissible: false,
          builder: (context) => CropImageDialog(
            imageBytes: imageBytes,
          ),
        );

        if (croppedBytes == null) return;

        if (mounted) {
          showFToast(
            context: context,
            title: const Text('正在上传头像...'),
          );
        }

        final String avatarUrl = await widget.apiService.uploadAvatarUniversal(
          imageBytes: croppedBytes,
          fileName: file.name.isNotEmpty ? file.name : 'avatar.png',
        );

        if (mounted) {
          setState(() {
            _currentUser = _currentUser?.copyWith(avatarUrl: avatarUrl);
          });

          if (mounted) {
            context.read<UserInfoProvider>().updateUser((old) => old.copyWith(avatarUrl: avatarUrl));
          }
        }

        if (mounted) {
          showFToast(
            context: context,
            title: const Text('头像上传成功'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text('头像上传失败: $e'),
        );
      }
    }
  }

  Future<void> _showUpdateUsernameDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController(text: _currentUser?.username ?? '');
    bool isLoading = false;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => FDialog(
          direction: Axis.horizontal,
          title: const Text('修改用户名'),
          body: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请输入新的用户名（3-12位字母数字）'),
                const SizedBox(height: 16),
                FTextFormField(
                  controller: usernameController,
                  label: const Text('用户名'),
                  hint: '输入新用户名',
                  maxLength: 12,
                  enabled: !isLoading,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '用户名不能为空';
                    }
                    
                    final trimmed = value.trim();
                    
                    if (trimmed.length < 3 || trimmed.length > 12) {
                      return '用户名长度必须在3-12位之间';
                    }
                    
                    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(trimmed)) {
                      return '用户名只能包含字母和数字';
                    }
                    
                    if (trimmed == _currentUser?.username) {
                      return '新用户名与当前用户名相同';
                    }
                    
                    return null;
                  },
                ),
                if (isLoading) ...[
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      LoadingIndicator.inline(message: '正在更新用户名...'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            FButton(
              style: context.theme.buttonStyles.outline.call,
              onPress: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FButton(
              onPress: isLoading ? null : () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                
                final newUsername = usernameController.text.trim();

                setState(() {
                  isLoading = true;
                });

                try {
                  await widget.apiService.updateUsername(
                    newUsername: newUsername,
                  );

                  await _fetchUserData();

                  if (context.mounted) {
                    context.read<UserInfoProvider>().updateUser((old) => old.copyWith(username: newUsername));
                  }

                  if (context.mounted) {
                    Navigator.of(context).pop();
                    showFToast(
                      context: context,
                      title: const Text('用户名更新成功'),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    showFToast(
                      context: context,
                      title: Text('用户名更新失败: $e'),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      isLoading = false;
                    });
                  }
                }
              },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isCompactWidth = MediaQuery.of(context).size.width < 1025;
    final bool isDesktopLayout = !isCompactWidth; // 与整体布局一致：md及以上为“桌面”
    // 桌面端横向留白更小；移动端更宽松
    final double horizontalPadding = isDesktopLayout ? 4.0 : 12.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 44,
        title: const Text(
          '设置',
          style: TextStyle(fontSize: 18),
        ),
      ),
      body: !isDesktopLayout
          ? ColoredBox(
              color: theme.colorScheme.surface,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 8 + MediaQuery.of(context).padding.bottom),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildUserInfoCard(theme),
                    const SizedBox(height: 12),
                    _buildClientSettingsCard(context, theme),
                    const SizedBox(height: 8),
                    _buildAccountCard(context, theme),
                    const SizedBox(height: 8),
                    _buildAppInfoCard(context, theme),
                    if (!isDesktopLayout) const SizedBox(height: 50),
                  ],
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: _settingsPanelWidth,
                  height: double.infinity,
                  color: theme.colorScheme.surface,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              _buildUserInfoCard(theme),
                              const SizedBox(height: 12),
                              _buildClientSettingsCard(context, theme),
                              const SizedBox(height: 8),
                              _buildAccountCard(context, theme),
                              const SizedBox(height: 8),
                              _buildAppInfoCard(context, theme),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _settingsPanelWidth = (_settingsPanelWidth + details.delta.dx)
                            .clamp(_settingsPanelMinWidth, _settingsPanelMaxWidth);
                      });
                      // 持久化保存
                      SettingsService().setSettingsPanelWidth(_settingsPanelWidth);
                    },
                    child: SizedBox(
                      width: 8,
                      height: double.infinity,
                      child: VerticalDivider(
                        width: 8,
                        thickness: 1,
                        color: theme.dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                ),
                // 右侧本地 Navigator：用于在桌面布局中打开目标页面
                Expanded(
                  child: Navigator(
                    key: _rightPaneNavigator,
                    onGenerateInitialRoutes: (_, __) => [
                      MaterialPageRoute(builder: (_) => const SizedBox.shrink()),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ==================== 用户信息卡片 ====================
  Widget _buildUserInfoCard(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: _currentUser?.avatarUrl != null &&
                          _currentUser!.avatarUrl!.isNotEmpty
                      ? Image.network(
                          toAbsoluteUrl(_currentUser!.avatarUrl!),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            // 加载中显示占位头像，避免出现空白
                            return const Center(
                              child: Icon(
                                Icons.person,
                                size: 50,
                                color: Colors.grey,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.person,
                              size: 50,
                              color: Colors.grey,
                            );
                          },
                        )
                      : const Icon(
                          Icons.person,
                          size: 50,
                          color: Colors.grey,
                        ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _changeAvatar,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.cardColor.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: 16,
                      color: theme.cardColor.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _currentUser?.username ?? 'Ghost',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _currentUser?.email ?? '',
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  // ==================== 桌面端设置卡片 ====================
  Widget _buildClientSettingsCard(BuildContext context, ThemeData theme) {
    return _buildSectionGroup(
      context,
      title: '设置',
      icon: null,
      items: [
        FItem(
          prefix: const Icon(FIcons.settings),
          title: const Text('通用'),
          suffix: const Icon(FIcons.chevronRight),
          onPress: () => _navigateToGeneralSettings(context),
        ),
      ],
    );
  }

  

  void _navigateToGeneralSettings(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isDesktopLayout = width >= 1025;

    final page = GeneralSettingsPage();

    if (isDesktopLayout && _rightPaneNavigator.currentState != null) {
      _rightPaneNavigator.currentState!.push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fade = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
            return FadeTransition(opacity: fade, child: child);
          },
        ),
      );
      return;
    }

    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => page),
    );
  }

  // ==================== 账户操作卡片 ====================
  Widget _buildAccountCard(BuildContext context, ThemeData theme) {
    return _buildSectionGroup(
      context,
      title: '账户操作',
      icon: Icons.settings_outlined,
      items: [
        FItem(
          title: const Text('账号安全'),
          suffix: const Icon(FIcons.chevronRight),
          onPress: () => _navigateToAccountSecurity(context),
        ),
        FItem(
          title: const Text('修改头像'),
          suffix: const Icon(FIcons.chevronRight),
          onPress: _changeAvatar,
        ),
        FItem(
          title: const Text('修改用户名'),
          suffix: const Icon(FIcons.chevronRight),
          onPress: () => _showUpdateUsernameDialog(context),
        ),
        FItem(
          title: Text(
            '退出登录',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          suffix: const Icon(FIcons.chevronRight),
          onPress: () => _confirmLogout(context, widget.onLogout),
        ),
      ],
    );
  }

  void _navigateToAccountSecurity(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isDesktopLayout = width >= 1025;

    final page = AccountSecurityPage(
      apiService: widget.apiService,
      currentUser: _currentUser,
      onUserUpdated: _fetchUserData,
    );

    if (isDesktopLayout && _rightPaneNavigator.currentState != null) {
      _rightPaneNavigator.currentState!.push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fade = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
            return FadeTransition(opacity: fade, child: child);
          },
        ),
      );
      return;
    }

    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => page),
    );
  }

  // ==================== 应用信息卡片 ====================
  Widget _buildAppInfoCard(BuildContext context, ThemeData theme) {
    return _buildSectionGroup(
      context,
      title: '应用信息',
      icon: null,
      items: [
        FItem(
          title: const Text('版本'),
          details: Text(
            _appVersion,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        FItem(
          title: const Text('清空缓存'),
          suffix: const Icon(FIcons.chevronRight),
          onPress: () => _clearCache(context),
        ),
        FItem(
          title: const Text('恢复默认设置'),
          suffix: const Icon(FIcons.chevronRight),
          onPress: () => _resetToDefaults(context),
        ),
        FItem(
          title: const Text('隐私政策'),
          suffix: const Icon(FIcons.chevronRight),
          onPress: _launchPrivacyPolicy,
        ),
      ],
    );
  }

  // ==================== 清空缓存 ====================
  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => FDialog(
        direction: Axis.horizontal,
        title: const Text('清空缓存'),
        body: const Text('确定要清空所有本地缓存吗？\n这将清除问卷、项目、统计数据等缓存，但不会影响您的账户数据。'),
        actions: [
          FButton(
            style: context.theme.buttonStyles.ghost.call,
            onPress: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final localContext = context;
      try {
        final prefs = await SharedPreferences.getInstance();
        
        final keys = prefs.getKeys();
        int clearedCount = 0;
        
        for (final key in keys) {
          if (!key.startsWith('auth_') && 
              !key.startsWith('refresh_') && 
              key != 'session_key') {
            await prefs.remove(key);
            clearedCount++;
          }
        }
        
        if (mounted && localContext.mounted) {
          showFToast(
            context: localContext,
            alignment: FToastAlignment.bottomRight,
            title: const Text('清空成功'),
            description: Text('已清除 $clearedCount 项缓存数据'),
          );
        }
      } catch (e) {
        if (mounted && localContext.mounted) {
          showFToast(
            context: localContext,
            alignment: FToastAlignment.bottomRight,
            title: const Text('清空失败'),
            description: Text('清空缓存失败: $e'),
          );
        }
      }
    }
  }

    Future<void> _resetToDefaults(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => FDialog(
        direction: Axis.horizontal,
        title: const Text('恢复默认设置'),
        body: const Text('确定要将所有设置恢复为默认值吗？\n这将包括主题、侧滑范围、窗口行为等所有设置。'),
        actions: [
          FButton(
            style: context.theme.buttonStyles.ghost.call,
            onPress: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final localContext = context;
      try {
        final settings = SettingsService();

        // 恢复主题为系统默认
        if (mounted) {
          context.read<ThemeProvider>().setMode(ThemeMode.system);
        }

        // 恢复侧滑触发范围为 24px
        await settings.setEdgeDragWidth(24.0);

        // 恢复 DPI 缩放为默认值 1.0
        if (mounted) {
          context.read<ThemeProvider>().setDpiScale(1.0);
        }

        // 恢复窗口关闭行为为每次询问
        await settings.setWindowCloseDontAsk(false);
        await settings.setWindowCloseDefaultAction('ask');

        // 恢复毛玻璃卡片为开启
        await settings.setGlassCardEnabled(true);

        // 恢复桌面模式左侧设置面板宽度为默认 420px
        await settings.setSettingsPanelWidth(420.0);
        if (mounted) {
          setState(() {
            _settingsPanelWidth = 420.0.clamp(_settingsPanelMinWidth, _settingsPanelMaxWidth);
          });
        }
        
        if (mounted && localContext.mounted) {
          setState(() {}); // 刷新UI
          
          showFToast(
            context: localContext,
            alignment: FToastAlignment.bottomRight,
            title: const Text('恢复成功'),
            description: const Text('所有设置已恢复为默认值'),
          );
        }
      } catch (e) {
        if (mounted && localContext.mounted) {
          showFToast(
            context: localContext,
            alignment: FToastAlignment.bottomRight,
            title: const Text('恢复失败'),
            description: Text('恢复默认设置失败: $e'),
          );
        }
      }
    }
  }

  // ==================== 工具方法 ====================

  // 使用 ForUI Item Group 渲染分组列表
  Widget _buildSectionGroup(
    BuildContext context, {
    required String title,
    required IconData? icon,
    required List<FItem> items,
  }) {
    final theme = Theme.of(context);
    final bool isDesktopLayout = MediaQuery.of(context).size.width >= 1025;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
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
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isDesktopLayout ? 4 : 8),
            child: FItemGroup(
              divider: FItemDivider.indented,
              children: items,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, VoidCallback onLogout) async {
    bool isLoading = false;
    
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => PopScope(
            canPop: !isLoading,
            child: FDialog(
              direction: Axis.horizontal,
              title: const Text('确认退出'),
              body: isLoading
                  ? const LoadingIndicator.inline(message: '正在退出登录...')
                  : const Text('确定要退出当前账号吗？'),
              actions: [
                FButton(
                  style: context.theme.buttonStyles.outline.call,
                  onPress: isLoading ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FButton(
                  onPress: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          try {
                            await widget.apiService.logoutStrict();
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (e) {
                            setState(() => isLoading = false);
                            if (dialogContext.mounted) {
                              showFToast(
                                context: dialogContext,
                                title: const Text('退出失败'),
                                description: Text(e.toString()),
                              );
                            }
                          }
                        },
                  child: const Text('确认'),
                ),
              ],
            ),
          ),
        );
      },
    );
    
    if (confirmed == true && context.mounted) {
      onLogout();
    }
  }

}

// 独立的侧滑触发范围卡片小部件
class _EdgeDragWidgetCard extends StatefulWidget {
  final double initialValue;
  final ThemeData theme;
  final ValueChanged<double> onChanged;

  const _EdgeDragWidgetCard({
    required this.initialValue,
    required this.theme,
    required this.onChanged,
  });

  @override
  State<_EdgeDragWidgetCard> createState() => _EdgeDragWidgetCardState();
}

class _EdgeDragWidgetCardState extends State<_EdgeDragWidgetCard> {
  late FDiscreteSliderController _controller;
  late double _currentValue;
  // 全局覆盖层（页面最左侧）
  OverlayEntry? _previewOverlay;
  final ValueNotifier<double> _overlayWidth = ValueNotifier<double>(0);
  final ValueNotifier<double> _overlayOpacity = ValueNotifier<double>(0);
  Timer? _hidePreviewTimer;
  Timer? _deferredShowTimer;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
    _controller = FDiscreteSliderController(
      selection: FSliderSelection(
        max: (_currentValue - 16) / 48,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _hidePreviewTimer?.cancel();
    _deferredShowTimer?.cancel();
    _removeOverlay();
    _overlayWidth.dispose();
    _overlayOpacity.dispose();
    super.dispose();
  }

  void _ensureOverlay() {
    if (_previewOverlay != null) return;
    _previewOverlay = OverlayEntry(
      builder: (context) {
        // 全屏遮罩，左侧淡蓝色区域根据 _overlayWidth 变化
        return IgnorePointer(
          ignoring: true,
          child: SafeArea(
            left: false,
            right: false,
            top: false,
            bottom: false,
            child: Stack(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _overlayOpacity,
                  builder: (context, opacity, child) {
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: opacity.clamp(0.0, 1.0),
                      child: child,
                    );
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _overlayWidth,
                      builder: (context, width, _) {
                        return Container(
                          width: width,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.lightBlueAccent.withValues(alpha: 0.18),
                            border: Border(
                              right: BorderSide(
                                color: Colors.lightBlueAccent.withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_previewOverlay!);
  }

  void _removeOverlay() {
    _previewOverlay?.remove();
    _previewOverlay = null;
    _deferredShowTimer?.cancel();
  }

  void _showGlobalPreview(double pixels) {
    // 以“移动布局”判定（窄屏）而非“移动端平台”
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isCompactLayout = screenWidth < 1025;
    final scaffoldState = Scaffold.maybeOf(context);
    final bool isDrawerOpen = scaffoldState?.isDrawerOpen ?? false;
    if (!isCompactLayout) {
      // 非移动布局时隐藏
      _overlayOpacity.value = 0;
      _hidePreviewTimer?.cancel();
      _deferredShowTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 200), _removeOverlay);
      return;
    }
    // 抽屉或移动侧边栏处于打开/展开中：直接不显示（并移除已有预览）
    if (isDrawerOpen || mobileSidebarOpen.value) {
      _overlayOpacity.value = 0;
      _hidePreviewTimer?.cancel();
      _deferredShowTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _removeOverlay();
      });
      return;
    }

    // 延迟一点再创建预览，期间若侧边栏开始打开则不显示，避免“先显后隐”的闪烁
    _deferredShowTimer?.cancel();
    _deferredShowTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      final s = Scaffold.maybeOf(context);
      final bool drawerNow = s?.isDrawerOpen ?? false;
      if (drawerNow || mobileSidebarOpen.value) {
        // 期间侧边栏打开：不显示
        return;
      }
      // 创建并更新覆盖层
      _ensureOverlay();
      _overlayWidth.value = pixels.clamp(0, screenWidth);
      _overlayOpacity.value = 1.0;

      // 延时自动隐藏
      _hidePreviewTimer?.cancel();
      _hidePreviewTimer = Timer(const Duration(milliseconds: 800), () {
        _overlayOpacity.value = 0.0;
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _removeOverlay();
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '侧滑触发范围',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              Text(
                '${_currentValue.toInt()}px',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '调整从屏幕左侧边缘触发侧边栏的距离',
            style: TextStyle(
              fontSize: 12,
              color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          FSlider(
            tooltipBuilder: (style, value) {
              final pixels = (16 + value * 48).round();
              return Text('${pixels}px');
            },
            controller: _controller,
            onChange: (selection) {
              // 对于离散滑块，应该读取 offset.max 而不是 extent.max
              final normalizedValue = _controller.selection.offset.max;
              final pixels = 16 + normalizedValue * 48;
              // 避免在构建阶段直接 setState，延迟到下一帧
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _currentValue = pixels;
                });
                _showGlobalPreview(pixels);
                widget.onChanged(pixels);
              });
            },
            marks: const [
              FSliderMark(value: 0, label: Text('16px')),
              FSliderMark(value: 0.25, tick: false),
              FSliderMark(value: 0.5, label: Text('40px')),
              FSliderMark(value: 0.75, tick: false),
              FSliderMark(value: 1, label: Text('64px')),
            ],
          ),
        ],
      ),
    );
  }
}

 

// DPI 缩放设置卡片
class _DpiScaleCard extends StatefulWidget {
  final double initialValue;
  final ThemeData theme;
  final ValueChanged<double> onChanged;

  const _DpiScaleCard({
    required this.initialValue,
    required this.theme,
    required this.onChanged,
  });

  @override
  State<_DpiScaleCard> createState() => _DpiScaleCardState();
}

class _DpiScaleCardState extends State<_DpiScaleCard> {
  late FDiscreteSliderController _controller;
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    // 确保初始值在有效范围内 (0.85-1.15)
    _currentValue = widget.initialValue.clamp(0.85, 1.15);
    // 将 0.85-1.15 映射到 0-1 的归一化值
    // normalized = (value - 0.85) / (1.15 - 0.85) = (value - 0.85) / 0.3
    final normalized = ((_currentValue - 0.85) / 0.3).clamp(0.0, 1.0);
    _controller = FDiscreteSliderController(
      selection: FSliderSelection(
        max: normalized,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DPI 缩放',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              Text(
                '${(_currentValue * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '调整界面元素的显示大小',
            style: TextStyle(
              fontSize: 12,
              color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          FSlider(
            tooltipBuilder: (style, value) {
              final percentage = (85 + value * 30).round();
              return Text('$percentage%');
            },
            controller: _controller,
            onChange: (selection) {
              final normalizedValue = _controller.selection.offset.max;
              final scaleValue = 0.85 + normalizedValue * 0.3;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _currentValue = scaleValue;
                });
                widget.onChanged(scaleValue);
              });
            },
            marks: const [
              FSliderMark(value: 0, label: Text('85%')),
              FSliderMark(value: 0.333, tick: false),
              FSliderMark(value: 0.5, label: Text('100%')),
              FSliderMark(value: 0.667, tick: false),
              FSliderMark(value: 1, label: Text('115%')),
            ],
          ),
        ],
      ),
    );
  }
}

// 独立小部件以便保持 trailing 尺寸合适并读取当前设置值
class _FrostedSwitch extends StatefulWidget {
  final ValueChanged<bool> onChanged;
  const _FrostedSwitch({required this.onChanged});

  @override
  State<_FrostedSwitch> createState() => _FrostedSwitchState();
}

class _FrostedSwitchState extends State<_FrostedSwitch> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = SettingsService().glassCardEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return FSwitch(
      value: _value,
      onChange: (v) {
        setState(() => _value = v);
        widget.onChanged(v);
      },
    );
  }
}

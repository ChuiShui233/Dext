import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/config.dart';
import '../widgets/crop_image_dialog.dart';

class HomeSettingsContent extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onChangeAvatar;
  final Function(ThemeMode) onThemeModeChange;
  final ApiService apiService;
  final ValueNotifier<User?>? userNotifier;

  const HomeSettingsContent({
    super.key,
    required this.onLogout,
    required this.onChangeAvatar,
    required this.onThemeModeChange,
    required this.apiService,
    this.userNotifier,
  });

  @override
  State<HomeSettingsContent> createState() => _HomeSettingsContentState();
}

class _HomeSettingsContentState extends State<HomeSettingsContent> {
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }



  Future<void> _fetchUserData() async {
    try {
      final user = await widget.apiService.getCurrentUserHandler();

      setState(() {
        _currentUser = user;
      });
    } catch (e) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text('获取用户信息失败: $e'),
        );
      }
    }
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

        // 获取图片数据
        if (file.bytes != null) {
          // Web 和桌面端优先使用 bytes
          imageBytes = file.bytes!;
        } else if (file.path != null) {
          // 移动端使用文件路径读取
          final imageFile = File(file.path!);
          imageBytes = await imageFile.readAsBytes();
        } else {
          throw '无法获取图片数据';
        }

        // 显示裁剪对话框
        if (!mounted) return;
        final Uint8List? croppedBytes = await showDialog<Uint8List>(
          context: context,
          builder: (context) => CropImageDialog(
            imageBytes: imageBytes,
          ),
        );

        // 用户取消裁剪
        if (croppedBytes == null) return;

        if (mounted) {
          showFToast(
            context: context,
            title: const Text('正在上传头像...'),
          );
        }

        // 上传裁剪后的图片
        final String avatarUrl = await widget.apiService.uploadAvatarUniversal(
          imageBytes: croppedBytes,
          fileName: file.name.isNotEmpty ? file.name : 'avatar.png',
        );

        setState(() {
          _currentUser = _currentUser?.copyWith(avatarUrl: avatarUrl);
        });
        
        // 通知其他组件用户数据已更新
        widget.userNotifier?.value = _currentUser;

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
    final usernameController = TextEditingController(text: _currentUser?.username ?? '');
    bool isLoading = false;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => FDialog(
          title: const Text('修改用户名'),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请输入新的用户名（3-12位字母数字）'),
              const SizedBox(height: 16),
              FTextField(
                controller: usernameController,
                label: const Text('用户名'),
                hint: '输入新用户名',
                maxLength: 12,
                enabled: !isLoading,
              ),
              if (isLoading) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('正在更新用户名...'),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            FButton(
              style: FButtonStyle.outline,
              onPress: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FButton(
              onPress: isLoading ? null : () async {
                final newUsername = usernameController.text.trim();
                
                // 验证用户名格式
                if (newUsername.isEmpty) {
                  showFToast(
                    context: context,
                    title: const Text('用户名不能为空'),
                  );
                  return;
                }
                
                if (newUsername.length < 3 || newUsername.length > 12) {
                  showFToast(
                    context: context,
                    title: const Text('用户名长度必须在3-12位之间'),
                  );
                  return;
                }
                
                if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(newUsername)) {
                  showFToast(
                    context: context,
                    title: const Text('用户名只能包含字母和数字'),
                  );
                  return;
                }
                
                if (newUsername == _currentUser?.username) {
                  showFToast(
                    context: context,
                    title: const Text('新用户名与当前用户名相同'),
                  );
                  return;
                }

                setState(() {
                  isLoading = true;
                });

                try {
                  await widget.apiService.updateUsername(
                    newUsername: newUsername,
                  );
                  
                  // 用户名更新成功后，重新获取用户信息确保数据一致性
                  await _fetchUserData();
                  
                  // 通知其他组件用户数据已更新
                  widget.userNotifier?.value = _currentUser;
                  
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildUserInfoCard(theme),
            const SizedBox(height: 24),
            _buildThemeCard(context),
            const SizedBox(height: 18),
            _buildAccountCard(context, theme),
            const SizedBox(height: 16),
            _buildAppInfoCard(context, theme),
          ],
        ),
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
          _currentUser?.username ?? '用户名示例',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _currentUser?.email ?? 'user@example.com',
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  // ==================== 主题设置卡片 ====================
  Widget _buildThemeCard(BuildContext context) {
    return _buildSectionCard(
      context,
      title: '主题设置',
      icon: Icons.color_lens_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: FSelect<String>(
            hint: '选择主题模式',
            format: (s) => s,
            children: [
              FSelectItem('跟随系统', '跟随系统'),
              FSelectItem('浅色模式', '浅色模式'),
              FSelectItem('深色模式', '深色模式'),
            ],
            onChange: (mode) {
              if (mode != null) {
                switch (mode) {
                  case '跟随系统':
                    widget.onThemeModeChange(ThemeMode.system);
                    break;
                  case '浅色模式':
                    widget.onThemeModeChange(ThemeMode.light);
                    break;
                  case '深色模式':
                    widget.onThemeModeChange(ThemeMode.dark);
                    break;
                }
              }
            },
          ),
        ),
      ],
    );
  }

  // ==================== 账户操作卡片 ====================
  Widget _buildAccountCard(BuildContext context, ThemeData theme) {
    return _buildSectionCard(
      context,
      title: '账户操作',
      icon: Icons.settings_outlined,
      children: [
        _buildNoHighlightListTile(
          leading: Icon(Icons.person_outline, color: theme.colorScheme.primary),
          title: const Text('修改头像'),
          trailing: Icon(Icons.arrow_forward_ios,
              size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          onTap: _changeAvatar,
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
        _buildNoHighlightListTile(
          leading: Icon(Icons.edit_outlined, color: theme.colorScheme.primary),
          title: const Text('修改用户名'),
          trailing: Icon(Icons.arrow_forward_ios,
              size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          onTap: () => _showUpdateUsernameDialog(context),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
        _buildNoHighlightListTile(
          leading: Icon(Icons.logout, color: theme.colorScheme.error),
          title: Text('退出登录',
              style: TextStyle(color: theme.colorScheme.error)),
          trailing: Icon(Icons.arrow_forward_ios,
              size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          onTap: () => _confirmLogout(context, widget.onLogout),
        ),
      ],
    );
  }

  // ==================== 应用信息卡片 ====================
  Widget _buildAppInfoCard(BuildContext context, ThemeData theme) {
    return _buildSectionCard(
      context,
      title: '应用信息',
      icon: Icons.info_outline,
      children: [
        _buildNoHighlightListTile(
          title: const Text('版本'),
          trailing: Text('1.0.0',
              style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
        _buildNoHighlightListTile(
          title: const Text('隐私政策'),
          trailing: Icon(Icons.arrow_forward_ios,
              size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          onTap: () {},
        ),
      ],
    );
  }

  // ==================== 工具方法 ====================
  Widget _buildSectionCard(BuildContext context,
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
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
                      color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildNoHighlightListTile(
      {Widget? leading,
      required Widget title,
      Widget? trailing,
      VoidCallback? onTap}) {
    return ListTile(
      leading: leading,
      title: title,
      trailing: trailing,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      onTap: onTap,
      hoverColor: Colors.transparent,
      tileColor: Colors.transparent,
    );
  }

  void _confirmLogout(BuildContext context, VoidCallback onLogout) {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击遮罩关闭，防止交互
      builder: (context) {
        bool isLoading = false;
        return StatefulBuilder(
          builder: (context, setState) => PopScope(
            canPop: !isLoading, // 加载中阻止返回
            child: FDialog(
              direction: Axis.horizontal,
              title: const Text('确认退出'),
              body: isLoading
                  ? const Row(
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('正在退出登录...')
                      ],
                    )
                  : const Text('确定要退出当前账号吗？'),
              actions: [
                FButton(
                  style: FButtonStyle.outline,
                  intrinsicWidth: true,
                  onPress: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FButton(
                  intrinsicWidth: true,
                  onPress: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          try {
                            await widget.apiService.logoutStrict();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                            onLogout(); // 仅在服务端成功后本地登出
                          } catch (e) {
                            if (context.mounted) {
                              showFToast(
                                context: context,
                                title: const Text('退出失败'),
                                description: Text(e.toString()),
                              );
                            }
                          } finally {
                            if (context.mounted) setState(() => isLoading = false);
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
  }
}

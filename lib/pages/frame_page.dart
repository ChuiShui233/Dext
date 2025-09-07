import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import '../main.dart' show isDesktop;
import '../services/api_service.dart';
import '../models/project.dart';
import '../models/survey.dart';
import '../models/user.dart';
import 'home_page.dart';
import 'project_page.dart';
import 'survey_page.dart';

// 定义侧边栏显示逻辑
final showSidebarInDrawer = LayoutValue(xs: true, md: false);
final showSidebarInline = LayoutValue(xs: false, md: true);

class FramePage extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onIndexChanged;
  final VoidCallback onLogout;
  final Function(ThemeMode) onThemeModeChange;
  final ApiService? apiService;
  final PageStorageBucket bucket;
  final ValueNotifier<User?>? userNotifier;

  const FramePage({
    super.key,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.onLogout,
    required this.onThemeModeChange,
    this.apiService,
    required this.bucket,
    this.userNotifier,
  });

  @override
  FramePageState createState() => FramePageState();
}

class FramePageState extends State<FramePage> {
  int _currentTabIndex = 0;
  int _projectCount = 0;
    int _surveyCount = 0;
    User? _currentUser;
    
    @override
  void dispose() {
    widget.userNotifier?.removeListener(_handleUserUpdate);
    super.dispose();
  }

    @override
  void initState() {
      super.initState();
      _currentTabIndex = widget.selectedIndex;
      _loadData();
      _fetchUserData();
      
      // 监听用户数据更新
      widget.userNotifier?.addListener(_handleUserUpdate);
    }
    
    void _handleUserUpdate() {
      if (mounted) {
        setState(() {
          _currentUser = widget.userNotifier?.value;
        });
      }
    }

    Future<void> _fetchUserData() async {
      try {
        if (widget.apiService != null) {
          final user = await widget.apiService!.getCurrentUserHandler();
          setState(() {
            _currentUser = user;
          });
        }
      } catch (e) {
        if (kDebugMode) {
          print('获取用户数据失败: $e');
        }
      }
    }

  @override
  void didUpdateWidget(FramePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {
        _currentTabIndex = widget.selectedIndex;
      });
    }
  }

  Future<void> _loadData() async {
    if (widget.apiService == null) return;

    try {
      final projects = await widget.apiService!.getProjects();
      final surveys = await widget.apiService!.getSurveys();

      if (!mounted) return;

      setState(() {
        _projectCount = projects.length;
        _surveyCount = surveys.length;
      });
    } catch (e) {
      // 处理错误
    }
  }

  void handleTabChange(int index) {
    setState(() {
      _currentTabIndex = index;
    });
    widget.onIndexChanged(index);
  }

  void _handleProjectTap() {
    handleTabChange(3);
  }

  void _handleSurveyTap() {
    handleTabChange(4);
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认退出'),
        body: const Text('确定要退出当前账号吗？'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            intrinsicWidth: true,
            child: const Text('取消'),
            onPress: () => Navigator.pop(context),
          ),
          FButton(
            intrinsicWidth: true,
            child: const Text('是的捏'),
            onPress: () {
              widget.onLogout();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentTabIndex) {
      case 0:
      case 1:
      case 2:
        return HomePage(
          apiService: widget.apiService!,
          currentIndex: _currentTabIndex,
          projectCount: _projectCount,
          surveyCount: _surveyCount,
          onProjectTap: _handleProjectTap,
          onSurveyTap: _handleSurveyTap,
          onLogout: _handleLogout,
          onThemeModeChange: widget.onThemeModeChange,
          onTabChanged: handleTabChange,
          userNotifier: widget.userNotifier,
        );
      case 3:
        return ProjectPage(token: widget.apiService?.authToken ?? '');
      case 4:
        return SurveyPage(token: widget.apiService?.authToken ?? '');
      default:
        return const Center(child: Text('未知页面'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showDesktopLayout = showSidebarInline.resolve(context) && isDesktop;

    if (showDesktopLayout) {
      return PageStorage(
        bucket: widget.bucket,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSidebar(context),
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      );
    }

    // 移动端布局
    return _buildContent();
  }

  Widget _buildSidebar(BuildContext context) {
    return FSidebar(
      key: PageStorageKey('sidebar'),
      header: _buildSidebarHeader(context),
      footer: _buildSidebarFooter(context),
      children: [
        _buildMainNavigation(context),
        const SizedBox(height: 16),
        _buildQuickActions(context),
        const SizedBox(height: 16),
        _buildSettingsSection(context),
      ],
    );
  }

Widget _buildSidebarHeader(BuildContext context) {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primary.withOpacity(0),
            Theme.of(context).colorScheme.primary.withOpacity(0),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40, // 图片容器宽度
                height: 40, // 图片容器高度
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8), // 圆角
                  child: Image.asset(
                    'assets/images/Dext.png',
                    fit: BoxFit.cover, // 占满整个容器
                    errorBuilder: (context, error, stackTrace) => Icon(
                      FIcons.house,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '问卷调查',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      '管理平台',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FDivider(
            style: FDividerStyle(
              padding: EdgeInsets.zero,
              color: Theme.of(context).dividerColor.withOpacity(0.5),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildSidebarFooter(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.transparent
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                    padding: _currentUser?.avatarUrl != null ? const EdgeInsets.all(2) : const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _currentUser?.avatarUrl != null 
                          ? Colors.transparent 
                          : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: (_currentUser?.avatarUrl?.isNotEmpty ?? false)
    ? ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          _currentUser!.avatarUrl!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Icon(
            FIcons.userRound,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      )
    : Icon(
        FIcons.userRound,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),

                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _currentUser?.username ?? 'Ghost',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _currentUser?.email ?? '啥也没有捏',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
              
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    style: FButtonStyle.ghost,
                    onPress: () {
                      _showThemeMenu(context);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Theme.of(context).brightness == Brightness.dark
                              ? FIcons.moon
                              : FIcons.sun,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '主题',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FButton(
                    style: FButtonStyle.ghost,
                    onPress: () {
                      _showLogoutConfirmDialog(context);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FIcons.logOut, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '退出',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainNavigation(BuildContext context) {
    return FSidebarGroup(
      label: Row(
        children: [
          Icon(
            FIcons.navigation,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '主要功能',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      children: [
        FSidebarItem(
          icon: const Icon(FIcons.house),
          label: const Text('主页'),
          selected: _currentTabIndex == 0,
          onPress: () {
            handleTabChange(0);
          },
        ),
        FSidebarItem(
          icon: const Icon(FIcons.folderArchive),
          label: const Text('项目管理'),
          selected: _currentTabIndex == 3,
          onPress: () {
            handleTabChange(3);
          },
        ),
        FSidebarItem(
          icon: const Icon(FIcons.notebookPen),
          label: const Text('问卷管理'),
          selected: _currentTabIndex == 4,
          onPress: () {
            handleTabChange(4);
          },
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return FSidebarGroup(
      label: Row(
        children: [
          Icon(
            FIcons.zap,
            size: 16,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(
            '快速操作',
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      children: [
        FSidebarItem(
          icon: const Icon(FIcons.plus),
          label: const Text('新建项目'),
          onPress: () {
            _showCreateProjectDialog(context);
          },
        ),
        FSidebarItem(
          icon: const Icon(FIcons.fileText),
          label: const Text('新建问卷'),
          onPress: () {
            _showCreateSurveyDialog(context);
          },
        ),
        FSidebarItem(
          icon: const Icon(Icons.bar_chart),
          label: const Text('数据统计'),
          onPress: () {
            _showStatisticsDialog(context);
          },
        ),
      ],
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    return FSidebarGroup(
      label: Row(
        children: [
          Icon(
            FIcons.settings,
            size: 16,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(
            '设置与工具',
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      children: [
        FSidebarItem(
          icon: const Icon(FIcons.clock),
          label: const Text('历史记录'),
          selected: _currentTabIndex == 1,
          onPress: () {
            handleTabChange(1);
          },
        ),
        FSidebarItem(
          icon: const Icon(FIcons.settings),
          label: const Text('系统设置'),
          selected: _currentTabIndex == 2,
          onPress: () {
            handleTabChange(2);
          },
        ),
        FSidebarItem(
          icon: const Icon(Icons.help_outline),
          label: const Text('帮助中心'),
          onPress: () {
            _showHelpDialog(context);
          },
        ),
      ],
    );
  }

  void _showThemeMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: const Text('主题设置'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FButton(
              style: FButtonStyle.ghost,
              onPress: () {
                widget.onThemeModeChange(ThemeMode.system);
                Navigator.pop(context);
              },
              child: const Text('跟随系统'),
            ),
            FButton(
              style: FButtonStyle.ghost,
              onPress: () {
                widget.onThemeModeChange(ThemeMode.light);
                Navigator.pop(context);
              },
              child: const Text('浅色模式'),
            ),
            FButton(
              style: FButtonStyle.ghost,
              onPress: () {
                widget.onThemeModeChange(ThemeMode.dark);
                Navigator.pop(context);
              },
              child: const Text('深色模式'),
            ),
          ],
        ),
        actions: [
          FButton(
            child: const Text('关闭'),
            onPress: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showCreateProjectDialog(BuildContext context) {
    if (widget.apiService == null) {
      showDialog(
        context: context,
        builder: (context) => FDialog(
          title: const Text('提示'),
          body: const Text('无法创建项目，请先登录'),
          actions: [
            FButton(
              child: const Text('关闭'),
              onPress: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('快速创建项目'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FTextField(
              controller: nameController,
              label: const Text('项目名称'),
              hint: '请输入项目名称',
            ),
            const SizedBox(height: 16),
            FTextField(
              controller: descController,
              label: const Text('项目描述'),
              hint: '请输入项目描述',
            ),
          ],
        ),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () async {
              if (nameController.text.isEmpty || descController.text.isEmpty) {
                showFToast(
                  context: context,
                  alignment: FToastAlignment.bottomRight,
                  title: const Text('提示'),
                  description: const Text('请填写完整信息'),
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
                return;
              }

              try {
                final newProject = Project(
                  id: 0,
                  projectName: nameController.text.trim(),
                  projectDescription: descController.text.trim(),
                  userId: '',
                  createBy: '',
                  createTime: DateTime.now().toIso8601String(),
                  updateTime: DateTime.now().toIso8601String(),
                  updateBy: '',
                );

                await widget.apiService!.createProject(newProject);
                if (!context.mounted) return;
                
                Navigator.pop(context); // 关闭对话框
                
                // 跳转到项目管理页面
                Navigator.pushReplacementNamed(context, '/projects');
                
                showFToast(
                  context: context,
                  alignment: FToastAlignment.bottomRight,
                  title: const Text('创建成功'),
                  description: const Text('项目已创建，正在跳转到项目管理页面'),
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
              } catch (e) {
                if (!context.mounted) return;
                
                showFToast(
                  context: context,
                  alignment: FToastAlignment.bottomRight,
                  title: const Text('创建失败'),
                  description: Text('创建项目失败: $e'),
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
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showCreateSurveyDialog(BuildContext context) {
    if (widget.apiService == null) {
      showDialog(
        context: context,
        builder: (context) => FDialog(
          title: const Text('提示'),
          body: const Text('无法创建问卷，请先登录'),
          actions: [
            FButton(
              child: const Text('关闭'),
              onPress: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    List<Project> projects = [];
    int? selectedProjectId;
    bool isLoadingProjects = false; // 添加加载状态标志
    bool hasLoadedProjects = false; // 添加已加载标志

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // 异步加载项目列表
          if (projects.isEmpty && !isLoadingProjects && !hasLoadedProjects) {
            setState(() {
              isLoadingProjects = true;
            });
            widget.apiService!.getProjects().then((loadedProjects) {
              if (context.mounted) {
                setState(() {
                  projects = loadedProjects;
                  isLoadingProjects = false;
                  hasLoadedProjects = true; // 标记已加载完成
                  if (projects.isNotEmpty) {
                    selectedProjectId = projects.first.id;
                  }
                });
              }
            }).catchError((error) {
              if (context.mounted) {
                setState(() {
                  isLoadingProjects = false;
                  hasLoadedProjects = true; // 即使出错也标记为已加载，避免无限重试
                });
                showFToast(
                  context: context,
                  alignment: FToastAlignment.bottomRight,
                  title: const Text('加载失败'),
                  description: Text('加载项目列表失败: $error'),
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
            });
          }

          return FDialog(
            direction: Axis.horizontal,
            title: const Text('快速创建问卷'),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoadingProjects)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  )
                else if (projects.isNotEmpty)
                  FSelect<int>(
                    label: const Text('所属项目'),
                    hint: '请选择项目',
                    format: (value) => projects
                        .firstWhere((p) => p.id == value)
                        .projectName,
                    onChange: (value) {
                      setState(() {
                        selectedProjectId = value;
                      });
                    },
                    children: projects.map((project) {
                      return FSelectItem(
                        project.projectName,
                        project.id,
                      );
                    }).toList(),
                  )
                else if (hasLoadedProjects) // 已加载但没有项目
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('暂无项目，请先创建项目'),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                const SizedBox(height: 16),
                FTextField(
                  controller: nameController,
                  label: const Text('问卷标题'),
                  hint: '请输入问卷标题',
                ),
                const SizedBox(height: 16),
                FTextField(
                  controller: descController,
                  label: const Text('问卷描述'),
                  hint: '请输入问卷描述',
                ),
              ],
            ),
            actions: [
              FButton(
                style: FButtonStyle.outline,
                onPress: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FButton(
                onPress: () async {
                  if (nameController.text.isEmpty || 
                      descController.text.isEmpty || 
                      selectedProjectId == null) {
                    showFToast(
                      context: context,
                      alignment: FToastAlignment.bottomRight,
                      title: const Text('提示'),
                      description: const Text('请填写完整信息并选择项目'),
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
                    return;
                  }

                  try {
                    final newSurvey = Survey(
                      id: 0,
                      surveyUid: DateTime.now().millisecondsSinceEpoch.toString(),
                      surveyName: nameController.text.trim(),
                      description: descController.text.trim(),
                      surveyType: 0, // 默认普通问卷
                      surveyStatus: 0, // 默认未发布
                      totalTimes: 0,
                      projectId: selectedProjectId!,
                      deadline: null,
                      createTime: DateTime.now().toIso8601String(),
                      updateTime: DateTime.now().toIso8601String(),
                    );

                    await widget.apiService!.createSurvey(newSurvey);
                    if (!context.mounted) return;
                    
                    Navigator.pop(context); // 关闭对话框
                    
                    // 跳转到问卷管理页面
                    Navigator.pushReplacementNamed(context, '/surveys');
                    
                    showFToast(
                      context: context,
                      alignment: FToastAlignment.bottomRight,
                      title: const Text('创建成功'),
                      description: const Text('问卷已创建，正在跳转到问卷管理页面'),
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
                  } catch (e) {
                    if (!context.mounted) return;
                    
                    showFToast(
                      context: context,
                      alignment: FToastAlignment.bottomRight,
                      title: const Text('创建失败'),
                      description: Text('创建问卷失败: $e'),
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
                },
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStatisticsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: const Text('数据统计'),
        body: const Text('数据统计功能开发中...'),
        actions: [
          FButton(
            child: const Text('关闭'),
            onPress: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: const Text('帮助中心'),
        body: const Text('帮助中心功能开发中...'),
        actions: [
          FButton(
            child: const Text('关闭'),
            onPress: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认退出'),
        body: const Text('确定要退出当前账号吗？'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            intrinsicWidth: true,
            child: const Text('取消'),
            onPress: () => Navigator.pop(context),
          ),
          FButton(
            intrinsicWidth: true,
            child: const Text('是的捏'),
            onPress: () {
              widget.onLogout();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

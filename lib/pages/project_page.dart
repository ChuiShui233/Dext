import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import 'project_surveys_page.dart';
import '../components/multi_select_actions.dart';
import 'frame_page.dart'; // 确保已导入

class ProjectPage extends StatefulWidget {
  final String token;
  
  const ProjectPage({
    super.key,
    required this.token,
  });

  @override
  State<ProjectPage> createState() => ProjectPageState();
}

class ProjectPageState extends State<ProjectPage> with WidgetsBindingObserver {
  late final ApiService _apiService;
  List<Project> _projects = [];
  bool _isLoading = true;
  
  // 多选相关状态
  List<int> _selectedProjectIds = [];
  bool _isMultiSelectMode = false;
  
  // 下拉刷新控制器
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  
  // 自动刷新定时器
  Timer? _autoRefreshTimer;
  
  // 分页相关
  final int _itemsPerPage = 10;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  FPaginationController _paginationController = FPaginationController(pages: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(authToken: widget.token);
    _loadProjects();
    
    // 启动自动刷新定时器（每30秒自动刷新一次）
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _paginationController.dispose();
    _refreshController.dispose();
    _stopAutoRefresh();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProjects();
      _startAutoRefresh();
    } else if (state == AppLifecycleState.paused) {
      _stopAutoRefresh();
    }
  }

  // 启动自动刷新
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadProjects(silent: true);
      }
    });
  }

  // 停止自动刷新
  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
  }

  // 分页处理方法
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final value = PageStorage.maybeOf(context)?.readState(context) ?? 0;
    _paginationController.page = value;
  }

  void _handlePageChange(int page) {
    if (_currentPage != page + 1) { // FPagination uses 0-based indexing
      setState(() {
        _currentPage = page + 1; // Convert to 1-based for API
      });
      _loadProjects();
    }
  }


  // 下拉刷新回调
  void _onRefresh() async {
    // 先显示刷新动画
    _refreshController.refreshToIdle();
    
    // 延迟1秒后实际刷新数据
    await Future.delayed(const Duration(seconds: 1));
    
    try {
      // 使用强制刷新而不是普通加载
      final projects = await _apiService.forceRefreshProjects();
      
      if (!mounted) {
        _refreshController.refreshCompleted();
        return;
      }
      
      setState(() {
        _projects = projects;
        _isLoading = false;
      });
      
      _refreshController.refreshCompleted();
    } catch (e) {
      if (!mounted) {
        _refreshController.refreshFailed();
        return;
      }
      
      setState(() => _isLoading = false);
      _refreshController.refreshFailed();
      
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('刷新失败'),
        description: Text('刷新数据失败: $e'),
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

  Future<void> _loadProjects({bool silent = false}) async {
    if (!mounted) return;
    
    if (!silent) {
      setState(() => _isLoading = true);
    }
    
    try {
      final paginatedResponse = await _apiService.getProjectsPaginated(
        page: _currentPage,
        pageSize: _itemsPerPage,
      );
      if (!mounted) return;
      
      setState(() {
        _projects = paginatedResponse.items;
        _totalPages = paginatedResponse.totalPages;
        _totalItems = paginatedResponse.total;
        _isLoading = false;
      });
      
      // 更新分页控制器
      _paginationController.dispose();
      _paginationController = FPaginationController(pages: _totalPages > 0 ? _totalPages : 1);
      // 同步当前页码到分页控制器（转换为0-based）
      _paginationController.page = (_currentPage - 1).clamp(0, (_totalPages - 1).clamp(0, double.infinity).toInt());
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      if (!silent && context.mounted) {
        showFToast(
          context: context,
          alignment:FToastAlignment.bottomRight,
          title: const Text('加载失败'),
          description: Text('加载项目失败: $e'),
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

  Future<void> _showAddProjectDialog() async {
    if (!mounted) return;
    final context = this.context;
    
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();

    return showAdaptiveDialog(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('新建项目'),
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
                  alignment:FToastAlignment.bottomRight,
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

              try {
                await _apiService.createProject(newProject);
                if (!mounted) return;
                if (!context.mounted) return;
                Navigator.pop(context);
                // 触发下拉刷新动画
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _refreshController.requestRefresh();
                });
              } catch (e) {
                if (!mounted) return;
                if (!context.mounted) return;
                showFToast(
                  context: context,
                  alignment:FToastAlignment.bottomRight,
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
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditProjectDialog(Project project) async {
    if (!mounted) return;
    final context = this.context;
    
    final TextEditingController nameController = TextEditingController(text: project.projectName);
    final TextEditingController descController = TextEditingController(text: project.projectDescription);

    return showAdaptiveDialog(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('编辑项目'),
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
                  alignment:FToastAlignment.bottomRight,
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

              final updatedProject = project.copyWith(
                projectName: nameController.text,
                projectDescription: descController.text,
                updateTime: DateTime.now().toString(),
              );

              try {
                await _apiService.updateProject(updatedProject);
                if (!context.mounted) return;
                Navigator.pop(context);
                // 触发下拉刷新动画
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _refreshController.requestRefresh();
                });
              } catch (e) {
                if (!context.mounted) return;
                showFToast(
                  context: context,
                  alignment:FToastAlignment.bottomRight,
                  title: const Text('更新失败'),
                  description: Text('更新项目失败: $e'),
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
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _openProjectSurveys(Project project) async {
    if (!mounted) return;
    final context = this.context;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectSurveysPage(
          token: widget.token,
          project: project,
        ),
      ),
    );
  }

  // 多选相关方法
  void _onSelectionChanged(List<int> selectedIds) {
    setState(() {
      _selectedProjectIds = selectedIds;
      _isMultiSelectMode = selectedIds.isNotEmpty;
    });
  }

  void _onSelectAll() {
    final allIds = _projects.map((project) => project.id).toList();
    setState(() {
      _selectedProjectIds = allIds;
      _isMultiSelectMode = true;
    });
  }

  void _onClearSelection() {
    setState(() {
      _selectedProjectIds = [];
      _isMultiSelectMode = false;
    });
  }

  void _onProjectSelectionChanged(int projectId, bool isSelected) {
    setState(() {
      if (isSelected) {
        if (!_selectedProjectIds.contains(projectId)) {
          _selectedProjectIds.add(projectId);
        }
      } else {
        _selectedProjectIds.remove(projectId);
      }
      _isMultiSelectMode = _selectedProjectIds.isNotEmpty;
    });
  }

  Future<void> _batchDeleteProjects() async {
    if (_selectedProjectIds.isEmpty) return;

    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认批量删除'),
        body: Text('确定要删除选中的 ${_selectedProjectIds.length} 个项目吗？此操作不可撤销。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: FButtonStyle.destructive,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // 在清空选中项前，先保存数量
        final deletedCount = _selectedProjectIds.length;
        
        await _apiService.batchDeleteProjects(_selectedProjectIds);
        
        setState(() {
          _selectedProjectIds = [];
          _isMultiSelectMode = false;
        });
        
        // 修改这里：不再使用下拉刷新，而是直接强制刷新数据
        if (mounted) {
          // 强制刷新数据，忽略缓存
          final projects = await _apiService.forceRefreshProjects();
          
          setState(() {
            _projects = projects;
          });
        }
        
        if (!mounted) return;
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('删除成功'),
          description: Text('已删除 $deletedCount 个项目'),
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
        if (!mounted) return;
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('删除失败'),
          description: Text('批量删除项目失败: $e'),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final frameState = context.findAncestorStateOfType<FramePageState>();
        if (frameState != null) {
          frameState.handleTabChange(0);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(height: isDesktop ? 40 : 20),
                FHeader.nested(
                  title: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Text('项目管理'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '共 ${_projects.length} 个',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  prefixes: [
                    FHeaderAction(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      onPress: () {
                        final frameState = context.findAncestorStateOfType<FramePageState>();
                        if (frameState != null) {
                          frameState.handleTabChange(0);
                        }
                      },
                    ),
                  ],
                  suffixes: [
                    FHeaderAction(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPress: () {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _refreshController.requestRefresh();
                        });
                      },
                    ),
                    FHeaderAction(
                      icon: Icon(
                        FIcons.list,
                        size: 20,
                      ),
                      onPress: () {
                        setState(() {
                          _isMultiSelectMode = !_isMultiSelectMode;
                          if (!_isMultiSelectMode) {
                            _selectedProjectIds = [];
                          }
                        });
                      },
                    ),
                    FHeaderAction(
                      icon: const Icon(Icons.add, size: 20),
                      onPress: _showAddProjectDialog,
                    ),
                  ],
                ),
                // 多选操作组件
                if (_isMultiSelectMode && _selectedProjectIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: MultiSelectActions(
                      selectedIds: _selectedProjectIds,
                      onSelectionChanged: _onSelectionChanged,
                      onSelectAll: _onSelectAll,
                      onClearSelection: _onClearSelection,
                      customActions: [
                        FButton(
                          style: FButtonStyle.destructive,
                          onPress: _batchDeleteProjects,
                          child: const Text('批量删除'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _projects.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.folder_open,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '暂无项目',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '点击右上角的"+"按钮创建新项目',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 32),
                                    child: FButton(
                                      onPress: _showAddProjectDialog,
                                      child: const Text('创建新项目'),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              children: [
                                Expanded(
                                  child: ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(context).copyWith(
                                      scrollbars: false,
                                      dragDevices: const {
                                        PointerDeviceKind.touch,
                                        PointerDeviceKind.mouse,
                                        PointerDeviceKind.trackpad,
                                        PointerDeviceKind.stylus,
                                      },
                                    ),
                                    child: SmartRefresher(
                                      controller: _refreshController,
                                      onRefresh: _onRefresh,
                                      enablePullDown: true,
                                      enablePullUp: false,
                                      physics: const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
                                      ),
                                      header: const ClassicHeader(
                                        refreshStyle: RefreshStyle.Follow,
                                        textStyle: TextStyle(color: Colors.grey),
                                        iconPos: IconPosition.top,
                                      ),
                                      child: ListView.builder(
                                        itemCount: _projects.length,
                                        itemBuilder: (context, index) {
                                          final project = _projects[index];
                                          final isSelected = _selectedProjectIds.contains(project.id);
                                  
                                                Widget cardContent = Card(
                                                  margin: const EdgeInsets.all(8.0),
                                                  elevation: 2,
                                                  color: Theme.of(context).brightness == Brightness.dark 
                                                    ? Colors.transparent
                                                    : Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    side: BorderSide(
                                                      color: Theme.of(context).brightness == Brightness.dark 
                                                        ? Colors.white.withValues(alpha: 0.1)
                                                        : Colors.black.withValues(alpha: 0.1),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: ListTile(
                                                    title: Text(
                                                      project.projectName,
                                                      style: TextStyle(
                                                        color: Theme.of(context).brightness == Brightness.dark 
                                                          ? Colors.white 
                                                          : Colors.black87,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    subtitle: Text(
                                                      project.projectDescription,
                                                      style: TextStyle(
                                                        color: Theme.of(context).brightness == Brightness.dark 
                                                          ? Colors.white70 
                                                          : Colors.black54,
                                                      ),
                                                    ),
                                                    trailing: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        FButton(
                                                          onPress: () => _openProjectSurveys(project),
                                                          child: Icon(
                                                            Icons.assignment_outlined,
                                                            size: 20,
                                                            color: Theme.of(context).brightness == Brightness.dark 
                                                              ? Colors.black.withValues(alpha: 0.6)
                                                              : Colors.white.withValues(alpha: 0.7),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        FButton(
                                                          onPress: () => _showEditProjectDialog(project),
                                                          child: Icon(
                                                            Icons.edit,
                                                            size: 20,
                                                            color: Theme.of(context).brightness == Brightness.dark 
                                                              ? Colors.black.withValues(alpha: 0.6)
                                                              : Colors.white.withValues(alpha: 0.7),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        FButton(
                                                          onPress: () async {
                                                            final confirm = await showAdaptiveDialog<bool>(
                                                              context: context,
                                                              builder: (context) => FDialog(
                                                                direction: Axis.horizontal,
                                                                title: const Text('确认删除'),
                                                                body: const Text('确定要删除这个项目吗？此操作不可撤销。'),
                                                                actions: [
                                                                  FButton(
                                                                    style: FButtonStyle.outline,
                                                                    onPress: () => Navigator.of(context).pop(false),
                                                                    child: const Text('取消'),
                                                                  ),
                                                                  FButton(
                                                                    style: FButtonStyle.destructive,
                                                                    onPress: () => Navigator.of(context).pop(true),
                                                                    child: const Text('删除'),
                                                                  ),
                                                                ],
                                                              ),
                                                            );

                                                            if (confirm == true) {
                                                              try {
                                                                await _apiService.deleteProject(project.id);
                                                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                                                  _refreshController.requestRefresh();
                                                                });
                                                              } catch (e) {
                                                                if (!context.mounted) return;
                                                                showFToast(
                                                                  context: context,
                                                                  alignment:FToastAlignment.bottomRight,
                                                                  title: const Text('删除失败'),
                                                                  description: Text('删除项目失败: $e'),
                                                                );
                                                              }
                                                            }
                                                          },
                                                          child: Icon(
                                                            Icons.delete,
                                                            size: 20,
                                                            color: Theme.of(context).brightness == Brightness.dark 
                                                              ? Colors.red.shade300
                                                              : Colors.red.shade700,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );

                                                // 如果处于多选模式，用MultiSelectItem包装
                                                if (_isMultiSelectMode) {
                                                  cardContent = MultiSelectItem(
                                                    id: project.id,
                                                    isSelected: isSelected,
                                                    onSelectionChanged: _onProjectSelectionChanged,
                                                    child: cardContent,
                                                  );
                                                }

                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: cardContent,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                // 添加分页组件
                                if (_totalPages > 1)
                                  _buildFPagination(context, _totalPages),
                              ],
                            ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFPagination(BuildContext context, int totalPages) {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '共 $_totalItems 个项目，第 $_currentPage / $_totalPages 页',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          FPagination(
            controller: _paginationController,
            onChange: _handlePageChange,
          ),
        ],
      ),
    );
  }
} 
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../widgets/top_safe_spacer.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import 'project_surveys_page.dart';
import '../components/multi_select_actions.dart';
import '../components/glass_card.dart';
import '../components/pull_to_refresh_wrapper.dart';
import '../components/flexible_pagination.dart';
import '../components/loading_indicator.dart';
import 'frame_page.dart';
import '../widgets/frosted_glass_background.dart';
import '../utils/error_formatter.dart';

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
  String _searchQuery = '';
  
  List<int> _selectedProjectIds = [];
  bool _isMultiSelectMode = false;
  
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  
  Timer? _autoRefreshTimer;
  
  int _itemsPerPage = 20;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  FPaginationController _paginationController = FPaginationController(pages: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(authToken: widget.token);
    // 首次加载跳过缓存，确保显示最新数据
    _loadProjects(skipCache: true);
    
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
      // 应用恢复时跳过缓存，加载最新数据
      _loadProjects(skipCache: true);
      _startAutoRefresh();
    } else if (state == AppLifecycleState.paused) {
      _stopAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadProjects(silent: true);
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
  }

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


  void _onRefresh() async {
    // 让SmartRefresher自行管理刷新状态，避免动画被立即复位
    // 延迟1秒后实际刷新数据
    await Future.delayed(const Duration(seconds: 1));
    
    try {
      // 使用分页加载，避免一次性加载全部列表
      await _loadProjects(silent: true);
      if (!mounted) {
        _refreshController.refreshCompleted();
        return;
      }
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

  Future<void> _loadProjects({bool silent = false, bool skipCache = false}) async {
    if (!mounted) return;
    
    Timer? loadingTimer;
    if (!silent) {
      loadingTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted && _isLoading) {
          setState(() => _isLoading = true);
        }
      });
    }
    
    try {
      final paginatedResponse = await _apiService.getProjectsPaginated(
        page: _currentPage,
        pageSize: _itemsPerPage,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        skipCache: skipCache,
      );
      loadingTimer?.cancel();
      if (!mounted) return;
      
      setState(() {
        _projects = paginatedResponse.items;
        _totalPages = paginatedResponse.totalPages;
        _totalItems = paginatedResponse.total;
        _isLoading = false;
        // 数据刷新时清空选中列表，避免选中已不存在的项目导致删除失败
        if (_selectedProjectIds.isNotEmpty) {
          _selectedProjectIds.clear();
          _isMultiSelectMode = false;
        }
      });
      
      _paginationController.dispose();
      _paginationController = FPaginationController(pages: _totalPages > 0 ? _totalPages : 1);
      _paginationController.page = (_currentPage - 1).clamp(0, (_totalPages - 1).clamp(0, double.infinity).toInt());
    } catch (e) {
      loadingTimer?.cancel();
      if (!mounted) return;
      
      final capturedContext = context;
      if (skipCache) {
        try {
          final cachedResponse = await _apiService.getProjectsPaginated(
            page: _currentPage,
            pageSize: _itemsPerPage,
            search: _searchQuery.isNotEmpty ? _searchQuery : null,
            skipCache: false,
          );
          if (mounted) {
            setState(() {
              _projects = cachedResponse.items;
              _totalPages = cachedResponse.totalPages;
              _totalItems = cachedResponse.total;
              _isLoading = false;
            });
            _paginationController.dispose();
            _paginationController = FPaginationController(pages: _totalPages > 0 ? _totalPages : 1);
            _paginationController.page = (_currentPage - 1).clamp(0, (_totalPages - 1).clamp(0, double.infinity).toInt());
          }
        } catch (_) {
          if (mounted) setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
      
      if (!silent && mounted && capturedContext.mounted) {
        showFToast(
          context: capturedContext,
          alignment: FToastAlignment.bottomRight,
          title: const Text('加载失败'),
          description: Text(ErrorFormatter.format(e)),
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

  void _onSelectionChanged(List<int> selectedIds) {
    setState(() {
      _selectedProjectIds = selectedIds;
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
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _selectedProjectIds = [];
      _isMultiSelectMode = false;
    });
  }

  void _onSearchChanged() {
    setState(() {
      _currentPage = 1;
    });
    _loadProjects();
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
    });
  }

  Widget _buildDeleteButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _batchDeleteProjects,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 4),
                Text(
                  '批量删除',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        final deletedCount = _selectedProjectIds.length;
        
        await _apiService.batchDeleteProjects(_selectedProjectIds);
        
        setState(() {
          _selectedProjectIds = [];
          _isMultiSelectMode = false;
        });
        
        // 使用分页加载，避免一次性加载全部数据，跳过缓存强制刷新
        if (mounted) {
          await _loadProjects(silent: true, skipCache: true);
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
            const FrostedGlassBackground(),
            Column(
              children: [
                const TopSafeSpacer(),
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
                          '共 $_totalItems 个',
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
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: _isMultiSelectMode
                      ? Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: MultiSelectActions(
                            selectedIds: _selectedProjectIds,
                            onSelectionChanged: _onSelectionChanged,
                            onSelectAll: _onSelectAll,
                            onClearSelection: _onClearSelection,
                            onExitMultiSelectMode: _exitMultiSelectMode,
                            customActions: [
                              _buildDeleteButton(context),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: FTextField(
                          hint: '搜索项目...',
                          onChange: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                            _onSearchChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        child: FSelect<int>(
                          hint: '每页 $_itemsPerPage 条',
                          format: (value) => '每页 $value 条',
                          onChange: (value) {
                            if (value != null && value != _itemsPerPage) {
                              setState(() {
                                _itemsPerPage = value;
                                _currentPage = 1;
                              });
                              _loadProjects();
                            }
                          },
                          children: [
                            FSelectItem('每页 20 条', 20),
                            FSelectItem('每页 50 条', 50),
                            FSelectItem('每页 100 条', 100),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const LoadingIndicator.page()
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
                                    _searchQuery.isNotEmpty ? '没有找到符合条件的项目' : '暂无项目',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _searchQuery.isNotEmpty ? '请尝试其他搜索关键词' : '点击右上角的"+"按钮创建新项目',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  if (_searchQuery.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: FButton(
                                        onPress: () {
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                          _loadProjects();
                                        },
                                        child: const Text('清除搜索'),
                                      ),
                                    )
                                  else
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
                                  child: PullToRefreshWrapper(
                                    controller: _refreshController,
                                    onRefresh: _onRefresh,
                                    child: ListView.builder(
                                      itemCount: _projects.length,
                                      itemBuilder: (context, index) {
                                        final project = _projects[index];
                                        final isSelected = _selectedProjectIds.contains(project.id);
                                  
                                        final glassCard = GlassCard(
                                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            side: BorderSide(
                                              color: isSelected 
                                                ? Theme.of(context).colorScheme.primary
                                                : Colors.transparent,
                                              width: isSelected ? 2 : 0,
                                            ),
                                          ),
                                          child: ListTile(
                                              leading: _isMultiSelectMode
                                                  ? GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onTap: () => _onProjectSelectionChanged(project.id, !isSelected),
                                                      child: SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child: AnimatedContainer(
                                                          duration: const Duration(milliseconds: 180),
                                                          curve: Curves.easeOutCubic,
                                                          decoration: BoxDecoration(
                                                            color: isSelected
                                                                ? (Theme.of(context).brightness == Brightness.dark
                                                                    ? Colors.white
                                                                    : Theme.of(context).colorScheme.primary)
                                                                : Colors.transparent,
                                                            shape: BoxShape.circle,
                                                            border: Border.all(
                                                              color: isSelected
                                                                  ? (Theme.of(context).brightness == Brightness.dark
                                                                      ? Colors.white
                                                                      : Theme.of(context).colorScheme.primary)
                                                                  : (Theme.of(context).brightness == Brightness.dark
                                                                      ? Colors.white
                                                                      : Colors.black.withValues(alpha: 0.25)),
                                                              width: 2,
                                                            ),
                                                          ),
                                                          alignment: Alignment.center,
                                                          child: AnimatedSwitcher(
                                                            duration: const Duration(milliseconds: 150),
                                                            switchInCurve: Curves.easeOutBack,
                                                            switchOutCurve: Curves.easeInCubic,
                                                            transitionBuilder: (child, anim) => FadeTransition(
                                                              opacity: anim,
                                                              child: ScaleTransition(scale: anim, child: child),
                                                            ),
                                                            child: isSelected
                                                                ? Icon(
                                                                    key: const ValueKey('checked'),
                                                                    Icons.check_rounded,
                                                                    size: 16,
                                                                    color: Theme.of(context).brightness == Brightness.dark
                                                                        ? Colors.black87
                                                                        : Colors.white,
                                                                  )
                                                                : const SizedBox.shrink(key: ValueKey('unchecked')),
                                                          ),
                                                        ),
                                                      ),
                                                    )
                                                  : null,
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
                                              trailing: ConstrainedBox(
                                                constraints: const BoxConstraints(
                                                  maxWidth: 160, // 限制 trailing 的最大宽度，避免占满整行
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    FButton.icon(
                                                      style: FButtonStyle.outline,
                                                      onPress: () => _openProjectSurveys(project),
                                                      child: const Icon(Icons.assignment_outlined, size: 20),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    FButton.icon(
                                                      style: FButtonStyle.outline,
                                                      onPress: () => _showEditProjectDialog(project),
                                                      child: const Icon(Icons.edit, size: 20),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    FButton.icon(
                                                      style: FButtonStyle.outline,
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
                                                          final ctx = context;
                                                          try {
                                                            await _apiService.deleteProject(project.id);
                                                            if (!mounted) return;
                                                            await _loadProjects(silent: true, skipCache: true);
                                                            if (!mounted) return;
                                                            if (mounted) {
                                                              showFToast(
                                                                // ignore: use_build_context_synchronously
                                                                context: ctx,
                                                                alignment: FToastAlignment.bottomRight,
                                                                title: const Text('删除成功'),
                                                                description: Text('已删除项目：${project.projectName}'),
                                                              );
                                                            }
                                                          } catch (e) {
                                                            if (mounted) {
                                                              showFToast(
                                                                // ignore: use_build_context_synchronously
                                                                context: ctx,
                                                                alignment: FToastAlignment.bottomRight,
                                                                title: const Text('删除失败'),
                                                                description: Text('删除项目失败: $e'),
                                                              );
                                                            }
                                                          }
                                                        }
                                                      },
                                                      child: const Icon(Icons.delete_outline, size: 20),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              onTap: _isMultiSelectMode 
                                                ? () => _onProjectSelectionChanged(project.id, !isSelected)
                                                : () => _openProjectSurveys(project),
                                            ),
                                          );
                                          return glassCard;
                                        },
                                      ),
                                    ),
                                  ),
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
    // 同步 controller 的页码（0-based）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_paginationController.page != _currentPage - 1) {
        _paginationController.page = (_currentPage - 1).clamp(0, (totalPages - 1).clamp(0, double.infinity).toInt());
      }
    });

    return FlexiblePagination(
      controller: _paginationController,
      currentPage: _currentPage,
      totalPages: totalPages,
      totalItems: _totalItems,
      onPageChange: _handlePageChange,
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
    );
  }
}
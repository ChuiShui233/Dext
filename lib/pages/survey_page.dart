import 'dart:async';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import '../models/survey.dart';
import '../models/survey_stats.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import 'create_survey_page.dart';
import '../components/survey_actions.dart';
import '../components/multi_select_actions.dart';
import 'frame_page.dart'; // 确保已导入

class SurveyPage extends StatefulWidget {
  final String token;
  
  const SurveyPage({
    super.key,
    required this.token,
  });

  @override
  State<SurveyPage> createState() => SurveyPageState();
}

class SurveyPageState extends State<SurveyPage> with WidgetsBindingObserver, TickerProviderStateMixin {
  late final ApiService _apiService;
  List<Survey> _surveys = [];
  Map<int, SurveyStats> _surveyStats = {};
  Map<int, Project> _projects = {};
  bool _isLoading = true;
  String _searchQuery = '';
  int? _selectedSurveyType;
  int _currentPage = 1;
  final int _pageSize = 5;
  late final FSelectController<String> _typeSelectController;
  final bool _isAllExpanded = false;
  final Key _listKey = UniqueKey();
  
  // 多选相关状态
  List<int> _selectedSurveyIds = [];
  bool _isMultiSelectMode = false;
  
  // 下拉刷新控制器
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  
  // 自动刷新定时器
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(authToken: widget.token);
    _typeSelectController = FSelectController<String>(vsync: this);
    _loadData();
    
    // 启动自动刷新定时器（每30秒自动刷新一次）
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typeSelectController.dispose();
    _refreshController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
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
        _loadData(silent: true);
      }
    });
  }

  // 停止自动刷新
  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
  }

  // 下拉刷新回调
  void _onRefresh() async {
    // 先显示刷新动画
    _refreshController.refreshToIdle();
    
    // 延迟1秒后实际刷新数据
    await Future.delayed(const Duration(seconds: 1));
    
    try {
      // 使用强制刷新而不是普通加载
      final surveys = await _apiService.forceRefreshSurveys();
      final projects = await _apiService.forceRefreshProjects();
      
      if (!mounted) {
        _refreshController.refreshCompleted();
        return;
      }
      
      setState(() {
        _surveys = surveys;
        _projects = {for (var p in projects) p.id: p};
        _isLoading = false;
      });
      
      // 异步加载统计信息
      _loadSurveyStats();
      
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

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    final context = this.context;
    
    if (!silent) {
      setState(() => _isLoading = true);
    }
    
    try {
      final surveys = await _apiService.getSurveys();
      final projects = await _apiService.getProjects();
      
      if (!mounted) return;
      
      setState(() {
        _surveys = surveys;
        _projects = {for (var p in projects) p.id: p};
        _isLoading = false;
      });
      
      // 异步加载统计信息
      _loadSurveyStats();
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      if (!silent) {
        showFToast(
          context: context,
          alignment:FToastAlignment.bottomRight,
          title: const Text('加载失败'),
          description: Text('加载问卷失败: $e'),
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

  // 异步加载统计信息
  Future<void> _loadSurveyStats() async {
    try {
      final stats = await _apiService.getAllSurveyStats();
      if (!mounted) return;
      
      setState(() {
        _surveyStats = {
          for (var stat in stats) stat.surveyId: stat
        };
      });
    } catch (e) {
      // 统计信息加载失败不影响主界面显示
      if (mounted) {
        // 静默处理错误，不显示调试信息
      }
    }
  }

  String _getSurveyTypeText(int type) {
    switch (type) {
      case 0:
        return '普通问卷';
      case 1:
        return '限时问卷';
      case 2:
        return '限次问卷';
      case 3:
        return '自选风格';
      default:
        return '未知类型';
    }
  }

  String _getSurveyStatusText(int status) {
    switch (status) {
      case 0:
        return '未发布';
      case 1:
        return '发布中';
      case 2:
        return '已完结';
      default:
        return '未知状态';
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 0:
        return Colors.grey;
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  List<Survey> _getFilteredSurveys() {
    return _surveys.where((survey) {
      final matchesSearch = survey.surveyName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          survey.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesType = _selectedSurveyType == null || survey.surveyType == _selectedSurveyType;
      return matchesSearch && matchesType;
    }).toList();
  }

  List<Survey> _getPaginatedSurveys() {
    final filtered = _getFilteredSurveys();
    final start = (_currentPage - 1) * _pageSize;
    final end = start + _pageSize;
    return filtered.length > start ? filtered.sublist(start, end > filtered.length ? filtered.length : end) : [];
  }

  Future<void> _viewSurveyStats(Survey survey) async {
    if (!mounted) return;
    final context = this.context;
    
    try {
      final stats = await _apiService.getSurveyStats(survey.id);
      if (!mounted) return;

      showAdaptiveDialog(
        context: context,
        builder: (context) => FDialog(
          direction: Axis.horizontal,
          title: Text('${survey.surveyName} - 统计信息'),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('总访问次数: ${stats.viewCount}'),
              const SizedBox(height: 8),
              Text('总提交次数: ${stats.submitCount}'),
              const SizedBox(height: 8),
              Text('最后访问时间: ${stats.lastViewTime.toLocal().toString()}'),
              const SizedBox(height: 8),
              Text('最后提交时间: ${stats.lastSubmitTime.toLocal().toString()}'),
            ],
          ),
          actions: [
            FButton(
              style: FButtonStyle.outline,
              onPress: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('获取失败'),
        description: Text('获取统计信息失败: $e'),
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

  @override
  Widget build(BuildContext context) {
    final filteredSurveys = _getFilteredSurveys();
    final paginatedSurveys = _getPaginatedSurveys();
    final totalPages = (filteredSurveys.length / _pageSize).ceil();

    return WillPopScope(
      onWillPop: () async {
        final frameState = context.findAncestorStateOfType<FramePageState>();
        if (frameState != null) {
          frameState.handleTabChange(0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                if (isDesktop)
                  const SizedBox(height: 40),
                FHeader.nested(
                  title: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Text('问卷管理'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '共 ${_surveys.length} 份',
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
                      icon: const Icon(Icons.info_outline, size: 20),
                      onPress: () {
                        showAdaptiveDialog(
                          context: context,
                          builder: (context) => FDialog(
                            direction: Axis.horizontal,
                            title: const Text('问卷统计信息'),
                            body: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('总访问量:'),
                                      Text('${_surveyStats.values.fold(0, (sum, stat) => sum + stat.viewCount)}'),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('总提交量:'),
                                      Text('${_surveyStats.values.fold(0, (sum, stat) => sum + stat.submitCount)}'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              FButton(
                                style: FButtonStyle.outline,
                                onPress: () => Navigator.of(context).pop(),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
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
                            _selectedSurveyIds = [];
                          }
                        });
                      },
                    ),
                    FHeaderAction(
                      icon: const Icon(Icons.add, size: 20),
                      onPress: () async {
                        if (!mounted) return;
                        final context = this.context;
                        
                        final projects = await _apiService.getProjects();
                        if (!mounted) return;
                        
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateSurveyPage(
                              token: widget.token,
                              projects: projects,
                            ),
                          ),
                        );
                        
                        if (result == true) {
                          // 触发下拉刷新动画
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _refreshController.requestRefresh();
                          });
                        }
                      },
                    ),
                  ],
                ),
                // 多选操作组件
                if (_isMultiSelectMode && _selectedSurveyIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: MultiSelectActions(
                      selectedIds: _selectedSurveyIds,
                      onSelectionChanged: _onSelectionChanged,
                      onSelectAll: _onSelectAll,
                      onClearSelection: _onClearSelection,
                      customActions: [
                        FButton(
                          style: FButtonStyle.destructive,
                          onPress: _batchDeleteSurveys,
                          child: const Text('批量删除'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: FTextField(
                            hint: '搜索问卷...',
                            onChange: (value) {
                              setState(() {
                                _searchQuery = value;
                                _currentPage = 1;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filteredSurveys.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.assignment_outlined,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isNotEmpty || _selectedSurveyType != null
                                        ? '没有找到符合条件的问卷'
                                        : '暂无问卷',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _searchQuery.isNotEmpty || _selectedSurveyType != null
                                        ? '请尝试其他搜索条件或清除筛选'
                                        : '点击右上角的"+"按钮创建新问卷',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  if (_searchQuery.isNotEmpty || _selectedSurveyType != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: FButton(
                                        onPress: () {
                                          setState(() {
                                            _searchQuery = '';
                                            _selectedSurveyType = null;
                                            _typeSelectController.value = '';
                                          });
                                        },
                                        child: const Text('清除筛选'),
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: FButton(
                                        onPress: () async {
                                          final projects = await _apiService.getProjects();
                                          if (!mounted) return;
                                          
                                          final result = await Navigator.push<bool>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => CreateSurveyPage(
                                                token: widget.token,
                                                projects: projects,
                                              ),
                                            ),
                                          );
                                          
                                          if (result == true) {
                                            // 触发下拉刷新动画
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              _refreshController.requestRefresh();
                                            });
                                          }
                                        },
                                        child: const Text('创建新问卷'),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : SmartRefresher(
                              controller: _refreshController,
                              onRefresh: _onRefresh,
                              enablePullDown: true,
                              enablePullUp: false,
                              header: const ClassicHeader(
                                refreshStyle: RefreshStyle.Follow,
                                textStyle: TextStyle(color: Colors.grey),
                                iconPos: IconPosition.top,
                              ),
                              child: ListView.builder(
                                key: _listKey,
                                itemCount: paginatedSurveys.length,
                                itemBuilder: (context, index) {
                                  final survey = paginatedSurveys[index];
                                  final stats = _surveyStats[survey.id];
                                  final isSelected = _selectedSurveyIds.contains(survey.id);
                                  
                                  Widget cardContent = FCard(
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        dividerColor: Colors.transparent,
                                      ),
                                      child: ExpansionTile(
                                        initiallyExpanded: _isAllExpanded,
                                        title: Text(
                                          survey.surveyName,
                                          style: TextStyle(
                                            color: Theme.of(context).brightness == Brightness.dark 
                                              ? Colors.white 
                                              : Colors.black87,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          survey.description,
                                          style: TextStyle(
                                            color: Theme.of(context).brightness == Brightness.dark 
                                              ? Colors.white70 
                                              : Colors.black54,
                                          ),
                                        ),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(survey.surveyStatus).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: _getStatusColor(survey.surveyStatus).withValues(alpha: 0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            _getSurveyStatusText(survey.surveyStatus),
                                            style: TextStyle(
                                              color: _getStatusColor(survey.surveyStatus),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).brightness == Brightness.dark 
                                                ? Colors.grey.withValues(alpha: 0.05)
                                                : Colors.grey.withValues(alpha: 0.02),
                                              borderRadius: const BorderRadius.only(
                                                bottomLeft: Radius.circular(12),
                                                bottomRight: Radius.circular(12),
                                              ),
                                            ),
                                            padding: const EdgeInsets.all(16.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                _buildInfoRow('问卷类型', _getSurveyTypeText(survey.surveyType)),
                                                const SizedBox(height: 8),
                                                _buildInfoRow('所属项目', _projects[survey.projectId]?.projectName ?? '未知项目'),
                                                const SizedBox(height: 8),
                                                _buildInfoRow('创建时间', survey.createTime),
                                                const SizedBox(height: 8),
                                                _buildInfoRow('更新时间', survey.updateTime),
                                                if (stats != null) ...[
                                                  const Divider(color: Colors.grey),
                                                  _buildInfoRow('访问量', stats.viewCount.toString()),
                                                  const SizedBox(height: 8),
                                                  _buildInfoRow('提交量', stats.submitCount.toString()),
                                                  const SizedBox(height: 8),
                                                  _buildInfoRow('最近访问', stats.lastViewTime.toString()),
                                                  const SizedBox(height: 8),
                                                  _buildInfoRow('最近提交', stats.lastSubmitTime.toString()),
                                                  if (stats.submittedUsers.isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    _buildInfoRow('提交用户', stats.submittedUsers.join(", ")),
                                                  ],
                                                ],
                                                const SizedBox(height: 16),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                  children: [
                                                    FButton(
                                                      style: FButtonStyle.outline,
                                                      onPress: () => _viewSurveyStats(survey),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.info_outline,
                                                            size: 20
                                                          ),
                                                          const SizedBox(width: 4),
                                                          const Text('统计'),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    SurveyActions(
                                                      survey: survey,
                                                      token: widget.token,
                                                      apiService: _apiService,
                                                      onSuccess: () {
                                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                                          _refreshController.requestRefresh();
                                                        });
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                                  // 如果处于多选模式，用MultiSelectItem包装
                                  if (_isMultiSelectMode) {
                                    cardContent = MultiSelectItem(
                                      id: survey.id,
                                      isSelected: isSelected,
                                      onSelectionChanged: _onSurveySelectionChanged,
                                      child: cardContent,
                                    );
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: cardContent,
                                  );
                                },
                              ),
                            ),
                ),
                if (totalPages > 1)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FButton(
                          style: FButtonStyle.outline,
                          onPress: _currentPage > 1
                              ? () {
                                  setState(() {
                                    _currentPage--;
                                  });
                                }
                              : null,
                          child: const Text('上一页'),
                        ),
                        const SizedBox(width: 16),
                        Text('第 $_currentPage 页，共 $totalPages 页'),
                        const SizedBox(width: 16),
                        FButton(
                          style: FButtonStyle.outline,
                          onPress: _currentPage < totalPages
                              ? () {
                                  setState(() {
                                    _currentPage++;
                                  });
                                }
                              : null,
                          child: const Text('下一页'),
                        ),
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.white70 
                : Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.white 
                : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  // 多选相关方法
  void _onSelectionChanged(List<int> selectedIds) {
    setState(() {
      _selectedSurveyIds = selectedIds;
      _isMultiSelectMode = selectedIds.isNotEmpty;
    });
  }

  void _onSelectAll() {
    final filteredSurveys = _getFilteredSurveys();
    final allIds = filteredSurveys.map((survey) => survey.id).toList();
    setState(() {
      _selectedSurveyIds = allIds;
      _isMultiSelectMode = true;
    });
  }

  void _onClearSelection() {
    setState(() {
      _selectedSurveyIds = [];
      _isMultiSelectMode = false;
    });
  }

  void _onSurveySelectionChanged(int surveyId, bool isSelected) {
    setState(() {
      if (isSelected) {
        if (!_selectedSurveyIds.contains(surveyId)) {
          _selectedSurveyIds.add(surveyId);
        }
      } else {
        _selectedSurveyIds.remove(surveyId);
      }
      _isMultiSelectMode = _selectedSurveyIds.isNotEmpty;
    });
  }

  Future<void> _batchDeleteSurveys() async {
    if (_selectedSurveyIds.isEmpty) return;

    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认批量删除'),
        body: Text('确定要删除选中的 ${_selectedSurveyIds.length} 份问卷吗？此操作不可撤销。'),
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
        final deletedCount = _selectedSurveyIds.length;
        
        await _apiService.batchDeleteSurveys(_selectedSurveyIds);
        
        setState(() {
          _selectedSurveyIds = [];
          _isMultiSelectMode = false;
        });
        
        // 修改这里：不再使用下拉刷新，而是直接强制刷新数据
        if (mounted) {
          // 强制刷新数据，忽略缓存
          final surveys = await _apiService.forceRefreshSurveys();
          final projects = await _apiService.getProjects();
          
          setState(() {
            _surveys = surveys;
            _projects = {for (var p in projects) p.id: p};
          });
          
          // 异步加载统计信息
          _loadSurveyStats();
        }
        
        if (mounted) {
          showFToast(
            context: context,
            alignment: FToastAlignment.bottomRight,
            title: const Text('删除成功'),
            description: Text('已删除 $deletedCount 份问卷'),
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
        if (mounted) {
          showFToast(
            context: context,
            alignment: FToastAlignment.bottomRight,
            title: const Text('删除失败'),
            description: Text('批量删除问卷失败: $e'),
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
  }
} 
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../widgets/top_safe_spacer.dart';
import 'package:forui/forui.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import '../models/survey.dart';
import '../models/project.dart';
import '../models/survey_stats.dart';
import '../services/api_service.dart';
import 'create_survey_page.dart';
import '../utils/date_format.dart';
import '../components/survey_actions.dart';
import '../components/multi_select_actions.dart';
import '../components/glass_card.dart';
import 'frame_page.dart'; // 确保已导入
import '../widgets/frosted_glass_background.dart';

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
  final int _pageSize = 5;
  late final FSelectController<String> _typeSelectController;
  final bool _isAllExpanded = false;
  final Key _listKey = UniqueKey();
  
  // 分页相关
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  FPaginationController _paginationController = FPaginationController(pages: 1);
  
  // 多选相关状态
  List<int> _selectedSurveyIds = [];
  bool _isMultiSelectMode = false;
  
  // 下拉刷新控制器
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  
  // 自动刷新定时器
  Timer? _autoRefreshTimer;
  // 倒计时刷新定时器（每秒一次）
  Timer? _countdownTimer;
  // 已经提示过到期的问卷，避免重复弹窗
  final Set<int> _expiryNotified = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(authToken: widget.token);
    _typeSelectController = FSelectController<String>(vsync: this);
    _loadData();
    
    // 启动自动刷新定时器（每30秒自动刷新一次）
    _startAutoRefresh();
    // 启动倒计时刷新（每秒更新UI）
    _startCountdown();
  }

  // 全局统一的时间格式化请使用 DateFormatUtils（lib/utils/date_format.dart）

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typeSelectController.dispose();
    _refreshController.dispose();
    _autoRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    _paginationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
      _startAutoRefresh();
      _startCountdown();
    } else if (state == AppLifecycleState.paused) {
      _stopAutoRefresh();
      _stopCountdown();
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

  // 启动倒计时刷新
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // 检查是否有问卷刚刚到期，进行一次性提醒
      _detectAndNotifyExpiry();
      setState(() {}); // 触发UI中倒计时文本刷新
    });
  }

  // 停止倒计时刷新
  void _stopCountdown() {
    _countdownTimer?.cancel();
  }

  // 检测问卷是否到期并提示一次，同时触发刷新以同步服务端状态
  void _detectAndNotifyExpiry() {
    if (_surveys.isEmpty) return;
    final now = DateTime.now();
    for (final s in _surveys) {
      final dl = _parseDeadline(s.deadline);
      if (dl == null) continue; // 无截止时间
      if (now.isAfter(dl) || now.isAtSameMomentAs(dl)) {
        if (!_expiryNotified.contains(s.id)) {
          _expiryNotified.add(s.id);
          // 弹出提醒
          if (mounted) {
            showFToast(
              context: context,
              alignment: FToastAlignment.bottomRight,
              title: const Text('问卷已到期'),
              description: Text('“${s.surveyName}” 已到达截止时间，状态将自动更新为已完结。'),
            );
            // 触发一次静默刷新，尽快获取到服务端自动完结后的状态
            _loadData(silent: true);
          }
        }
      }
    }
  }

  DateTime? _parseDeadline(String? deadline) {
    if (deadline == null || deadline.isEmpty) return null;
    try {
      // 后端返回格式通常为 "YYYY-MM-DD HH:MM:SS"（本地/UTC由DB驱动决定），统一按本地解析
      return DateTime.parse(deadline).toLocal();
    } catch (_) {
      // 尝试将空格替换为T再解析
      try {
        return DateTime.parse(deadline.replaceFirst(' ', 'T')).toLocal();
      } catch (_) {
        return null;
      }
    }
  }

  String _formatDuration(Duration d) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    final dd = d.inDays;
    final hh = d.inHours % 24;
    final mm = d.inMinutes % 60;
    final ss = d.inSeconds % 60;
    if (dd > 0) {
      return '$dd 天 ${two(hh)}:${two(mm)}:${two(ss)}';
    }
    return '${two(hh)}:${two(mm)}:${two(ss)}';
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
      final surveyResponse = await _apiService.getSurveysPaginated(
        page: _currentPage,
        pageSize: _pageSize,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        type: _selectedSurveyType?.toString(),
      );
      final projectResponse = await _apiService.getProjectsPaginated();
      
      if (!mounted) return;
      
      setState(() {
        _surveys = surveyResponse.items;
        _totalPages = surveyResponse.totalPages;
        _totalItems = surveyResponse.total;
        _projects = {for (var p in projectResponse.items) p.id: p};
        _isLoading = false;
      });
      
      // 更新分页控制器
      _paginationController.dispose();
      _paginationController = FPaginationController(pages: _totalPages > 0 ? _totalPages : 1);
      // 同步当前页码到分页控制器（转换为0-based）
      _paginationController.page = (_currentPage - 1).clamp(0, (_totalPages - 1).clamp(0, double.infinity).toInt());
      
      // 异步加载统计信息
      _loadSurveyStats();
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      if (!silent && context.mounted) {
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
      if (mounted) {
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

  void _onSearchChanged() {
    setState(() {
      _currentPage = 1; // Reset to first page when searching
    });
    _loadData();
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
      _loadData();
    }
  }

  Future<void> _viewSurveyStats(Survey survey) async {
    if (!mounted) return;
    final context = this.context;
    
    try {
      final stats = await _apiService.getSurveyStats(survey.id);
      if (!mounted) return;

      if (context.mounted) {
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
      }
    } catch (e) {
      if (!mounted) return;
      
      if (context.mounted) {
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
  }

  @override
  Widget build(BuildContext context) {
    final paginatedSurveys = _surveys;

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
                        
                        final result = context.mounted ? await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateSurveyPage(
                              token: widget.token,
                              projects: projects,
                            ),
                          ),
                        ) : null;
                        
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
                              });
                              _onSearchChanged();
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
                      : _surveys.isEmpty
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
                                          
                                          final result = context.mounted ? await Navigator.push<bool>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => CreateSurveyPage(
                                                token: widget.token,
                                                projects: projects,
                                              ),
                                            ),
                                          ) : null;
                                          
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
                          : ScrollConfiguration(
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
                                  key: _listKey,
                                  primary: true,
                                  itemCount: paginatedSurveys.length,
                                  itemBuilder: (context, index) {
                                  final survey = paginatedSurveys[index];
                                  final stats = _surveyStats[survey.id];
                                  final isSelected = _selectedSurveyIds.contains(survey.id);
                                  final deadlineDt = _parseDeadline(survey.deadline);
                                  final now = DateTime.now();
                                  final isExpired = deadlineDt != null && !now.isBefore(deadlineDt);
                                  final remain = (deadlineDt != null && now.isBefore(deadlineDt)) ? deadlineDt.difference(now) : Duration.zero;
                                  
                                  Widget cardContent = GlassCard(
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
                                                _buildInfoRow('创建时间', DateFormatUtils.formatIsoString(survey.createTime)),
                                                const SizedBox(height: 8),
                                                _buildInfoRow('更新时间', DateFormatUtils.formatIsoString(survey.updateTime)),
                                                if (survey.deadline != null && survey.deadline!.isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  _buildInfoRow('截止时间', DateFormatUtils.formatIsoString(survey.deadline!)),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text('倒计时', style: Theme.of(context).textTheme.bodyMedium),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: isExpired
                                                              ? Colors.red.withValues(alpha: 0.1)
                                                              : Colors.orange.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(
                                                            color: isExpired
                                                              ? Colors.red.withValues(alpha: 0.3)
                                                              : Colors.orange.withValues(alpha: 0.3),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          isExpired ? '已到期' : _formatDuration(remain),
                                                          style: TextStyle(
                                                            color: isExpired ? Colors.red : Colors.orange,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                                if (stats != null) ...[
                                                  const Divider(color: Colors.grey),
                                                  _buildInfoRow('访问量', stats.viewCount.toString()),
                                                  const SizedBox(height: 8),
                                                  _buildInfoRow('提交量', stats.submitCount.toString()),
                                                  const SizedBox(height: 8),
                                                  _buildInfoRow('最近访问', DateFormatUtils.formatDateTime(stats.lastViewTime)),
                                                  const SizedBox(height: 8),
                                                  _buildInfoRow('最近提交', DateFormatUtils.formatDateTime(stats.lastSubmitTime)),
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
                ),
                if (_totalPages > 1)
                  _buildFPagination(context, _totalPages),
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
            '共 $_totalItems 份问卷，第 $_currentPage / $_totalPages 页',
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
    final allIds = _surveys.map((survey) => survey.id).toList();
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
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/top_safe_spacer.dart';
import 'package:forui/forui.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/survey.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import 'create_survey_page.dart';
import '../utils/date_format.dart';
import '../utils/error_formatter.dart';
import '../components/survey_actions.dart';
import '../components/multi_select_actions.dart';
import '../components/glass_card.dart';
import '../components/flexible_pagination.dart';
import '../components/pull_to_refresh_wrapper.dart';
import '../components/loading_indicator.dart';
import 'frame_page.dart';
import '../widgets/frosted_glass_background.dart';
import '../providers/theme_provider.dart';

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
  Map<int, Project> _projects = {};
  bool _isLoading = true;
  bool _hasLoadedProjects = false;
  String _searchQuery = '';
  int? _selectedSurveyType;
  final int _pageSize = 5;
  late final FSelectController<int> _typeSelectController;
  final bool _isAllExpanded = false;
  final Key _listKey = UniqueKey();
  
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  FPaginationController _paginationController = FPaginationController(pages: 1);
  
  List<int> _selectedSurveyIds = [];
  bool _isMultiSelectMode = false;
  
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  
  Timer? _autoRefreshTimer;
  Timer? _countdownTimer;
  final Set<int> _notifiedExpiryIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(authToken: widget.token);
    _typeSelectController = FSelectController<int>(vsync: this);
    _loadData(skipCache: false).then((_) {
      if (mounted) {
        _loadData(silent: true, skipCache: false);
      }
    });
    
    _startAutoRefresh();
    _startCountdown();
  }

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
      _loadData(skipCache: false);
      _startAutoRefresh();
      _startCountdown();
    } else if (state == AppLifecycleState.paused) {
      _stopAutoRefresh();
      _stopCountdown();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadData(silent: true);
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _detectAndNotifyExpiry();
      setState(() {}); // 触发刷新
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
  }

  void _detectAndNotifyExpiry() {
    if (_surveys.isEmpty) return;
    final now = DateTime.now();
    for (final s in _surveys) {
      final dl = _parseDeadline(s.deadline);
      if (dl == null) continue;
      if (now.isAfter(dl) || now.isAtSameMomentAs(dl)) {
        if (!_notifiedExpiryIds.contains(s.id)) {
          _notifiedExpiryIds.add(s.id);
          if (mounted) {
            showFToast(
              context: context,
              alignment: FToastAlignment.bottomRight,
              title: const Text('问卷已到期'),
              description: Text('“${s.surveyName}” 已到达截止时间，状态将自动更新为已完结。'),
            );
            _loadData(silent: true);
          }
        }
      }
    }
  }

  DateTime? _parseDeadline(String? deadline) {
    if (deadline == null || deadline.isEmpty) return null;
    try {
      // "YYYY-MM-DD HH:MM:SS"
      return DateTime.parse(deadline).toLocal();
    } catch (_) {
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

  void _onRefresh() async {
    // 让SmartRefresher自行管理刷新状态，避免动画被立即复位
    // 延迟1秒后实际刷新数据
    await Future.delayed(const Duration(seconds: 1));
    
    try {
      await _loadData(silent: true, refreshProjects: true, skipCache: true);
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
        suffixBuilder: (context, entry) => IntrinsicHeight(
          child: FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: entry.dismiss.call,
            child: const Text('关闭'),
          ),
        ),
      );
    }
  }

  Future<void> _loadData({bool silent = false, bool refreshProjects = false, bool skipCache = false}) async {
    if (!mounted) return;
    final context = this.context;
    
    Timer? loadingTimer;
    if (!silent) {
      loadingTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted && _isLoading) {
          setState(() => _isLoading = true);
        }
      });
    }
    
    try {
      final surveyResponse = await _apiService.getSurveysPaginated(
        page: _currentPage,
        pageSize: _pageSize,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        type: _selectedSurveyType?.toString(),
        skipCache: skipCache,
      );
      if (refreshProjects) {
        _hasLoadedProjects = false;
      }
      if (!_hasLoadedProjects) {
        final allProjects = await _apiService.getProjects();
        _projects = {for (var p in allProjects) p.id: p};
        _hasLoadedProjects = true;
      }
      
      loadingTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _surveys = surveyResponse.items;
        _totalPages = surveyResponse.totalPages;
        _totalItems = surveyResponse.total;
        _isLoading = false;
        if (_selectedSurveyIds.isNotEmpty) {
          _selectedSurveyIds.clear();
          _isMultiSelectMode = false;
        }
      });
      
      _paginationController.dispose();
      _paginationController = FPaginationController(pages: _totalPages > 0 ? _totalPages : 1);
      _paginationController.page = (_currentPage - 1).clamp(0, (_totalPages - 1).clamp(0, double.infinity).toInt());
      
    } catch (e) {
      loadingTimer?.cancel();
      if (!mounted) return;
      
      if (skipCache) {
        try {
          final cachedResponse = await _apiService.getSurveysPaginated(
            page: _currentPage,
            pageSize: _pageSize,
            search: _searchQuery.isNotEmpty ? _searchQuery : null,
            type: _selectedSurveyType?.toString(),
            skipCache: false,
          );
          if (!_hasLoadedProjects) {
            try {
              final allProjects = await _apiService.getProjects();
              _projects = {for (var p in allProjects) p.id: p};
              _hasLoadedProjects = true;
            } catch (_) {
            }
          }
          if (mounted) {
            setState(() {
              _surveys = cachedResponse.items;
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
      
      if (!silent && context.mounted) {
        showFToast(
          context: context,
          alignment:FToastAlignment.bottomRight,
          title: const Text('加载失败'),
          description: Text(ErrorFormatter.format(e)),
          suffixBuilder: (context, entry) => IntrinsicHeight(
            child: FButton(
              style: context.theme.buttonStyles.primary.call,
              onPress: entry.dismiss.call,
              child: const Text('关闭'),
            ),
          ),
        );
      }
    }
  }


  String _getSurveyTypeText(int type) {
    switch (type) {
      case 0:
        return '问卷调查';
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

  void _viewSurveyStats(Survey survey) {
    if (!mounted) return;
    final context = this.context;
    
    if (context.mounted) {
      showFDialog(
        context: context,
        builder: (context, style, animation) => _SurveyStatsDialog(
          survey: survey,
          apiService: _apiService,
          style: style,
          animation: animation,
        ),
      );
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
                          '共 $_totalItems 份',
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
                        
                        final result = context.mounted ? await Navigator.push<dynamic>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateSurveyPage(
                              token: widget.token,
                              projects: projects,
                            ),
                          ),
                        ) : null;
                        
                        if (result == true || (result is String && result.trim().isNotEmpty)) {
                          // 成功提示
                          if (context.mounted) {
                            showFToast(
                              context: context,
                              alignment: FToastAlignment.bottomRight,
                              title: const Text('创建成功'),
                              description: Text(result is String && result.trim().isNotEmpty
                                  ? '问卷 “${result.trim()}” 已创建，正在刷新列表...'
                                  : '问卷已创建，正在刷新列表...'),
                              duration: const Duration(milliseconds: 1800),
                            );
                          }
                          // 创建成功后，回到第1页并强制跳过缓存拉取最新数据
                          if (mounted) {
                            setState(() {
                              _currentPage = 1;
                            });
                            await _loadData(silent: false, refreshProjects: true, skipCache: true);
                          }
                        }
                      },
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
                            selectedIds: _selectedSurveyIds,
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
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 160,
                        child: FSelect<int>(
                          controller: _typeSelectController,
                          hint: '类型筛选',
                          clearable: true,
                          items: const {
                            '问卷调查': 0,
                            '限时问卷': 1,
                            '限次问卷': 2,
                            '自选风格': 3,
                          },
                          onChange: (value) {
                            setState(() {
                              _selectedSurveyType = value;
                              _currentPage = 1;
                            });
                            _loadData();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const LoadingIndicator.page()
                      : _surveys.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    FIcons.clipboardPen,
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
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: FButton(
                                        onPress: () async {
                                          final projects = await _apiService.getProjects();
                                          if (!mounted) return;
                                          
                                          final result = context.mounted ? await Navigator.push<dynamic>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => CreateSurveyPage(
                                                token: widget.token,
                                                projects: projects,
                                              ),
                                            ),
                                          ) : null;
                                          
                                          if (result == true || (result is String && result.trim().isNotEmpty)) {
                                            // 成功提示
                                            if (context.mounted) {
                                              showFToast(
                                                context: context,
                                                alignment: FToastAlignment.bottomRight,
                                                title: const Text('创建成功'),
                                                description: Text(result is String && result.trim().isNotEmpty
                                                    ? '问卷 “${result.trim()}” 已创建，正在刷新列表...'
                                                    : '问卷已创建，正在刷新列表...'),
                                                duration: const Duration(milliseconds: 1800),
                                              );
                                            }
                                            // 创建成功后，回到第1页并强制跳过缓存拉取最新数据
                                            if (mounted) {
                                              setState(() {
                                                _currentPage = 1;
                                              });
                                              await _loadData(silent: false, refreshProjects: true, skipCache: true);
                                            }
                                          }
                                        },
                                        child: const Text('创建新问卷'),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : PullToRefreshWrapper(
                                controller: _refreshController,
                                onRefresh: _onRefresh,
                                child: ListView.builder(
                                  key: _listKey,
                                  primary: true,
                                  itemCount: paginatedSurveys.length,
                                  itemBuilder: (context, index) {
                                  final survey = paginatedSurveys[index];
                                  final isSelected = _selectedSurveyIds.contains(survey.id);
                                  final deadlineDt = _parseDeadline(survey.deadline);
                                  final now = DateTime.now();
                                  final isExpired = deadlineDt != null && !now.isBefore(deadlineDt);
                                  final remain = (deadlineDt != null && now.isBefore(deadlineDt)) ? deadlineDt.difference(now) : Duration.zero;
                                  
                                  Widget cardContent = GlassCard(
                                    child: Stack(
                                      clipBehavior: Clip.hardEdge,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 64),
                                          child: Theme(
                                            data: Theme.of(context).copyWith(
                                              dividerColor: Colors.transparent,
                                            ),
                                            child: ExpansionTile(
                                              leading: _isMultiSelectMode
                                                  ? GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onTap: () => _onSurveySelectionChanged(survey.id, !isSelected),
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
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                            alignment: Alignment.centerRight,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerRight,
                                              child: Align(
                                                alignment: Alignment.centerRight,
                                                child: Transform.scale(
                                                  scale: _buttonScale(context),
                                                  alignment: Alignment.centerRight,
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      FButton(
                                                        style: context.theme.buttonStyles.outline.call,
                                                        onPress: () => _viewSurveyStats(survey),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: const [
                                                            Icon(Icons.info_outline, size: 20),
                                                            SizedBox(width: 6),
                                                            Text('统计'),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      SurveyActions(
                                                        survey: survey,
                                                        token: widget.token,
                                                        apiService: _apiService,
                                                        useRow: true,
                                                        onSuccess: () {
                                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                                            _refreshController.requestRefresh();
                                                          });
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    child: cardContent,
                                  );
                                },
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

  // 根据屏幕宽度 + DPI 对底部操作按钮做整体缩放，保持在小屏下的视觉紧凑与不遮挡。
  double _buttonScale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // 参考分档：
    // ≤360: 0.85；≤480: 0.90；≤600: 0.95；≤760: 0.98；>760: 1.00
    double base;
    if (width <= 360) {
      base = 0.85;
    } else if (width <= 480) {
      base = 0.90;
    }
    else if (width <= 600) {
      base = 0.95;
    }
    else if (width <= 760) {
      base = 0.98;
    }
    else {
      base = 1.00;
    }

    final dpi = context.watch<ThemeProvider>().dpiScale;
    final scaled = base * dpi;
    // 防止过度放大/缩小破坏布局
    return scaled.clamp(0.80, 1.15);
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

  void _onSelectionChanged(List<int> selectedIds) {
    setState(() {
      _selectedSurveyIds = selectedIds;
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
    });
  }

  void _exitMultiSelectMode() {
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
    });
  }

  Widget _buildDeleteButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _batchDeleteSurveys,
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

  Future<void> _batchDeleteSurveys() async {
    if (_selectedSurveyIds.isEmpty) return;

    final confirm = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style.call,
        animation: animation,
        direction: Axis.horizontal,
        title: const Text('确认批量删除'),
        body: Text('确定要删除选中的 ${_selectedSurveyIds.length} 份问卷吗？此操作不可撤销。'),
        actions: [
          FButton(
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: context.theme.buttonStyles.destructive.call,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final deletedCount = _selectedSurveyIds.length;
        
        await _apiService.batchDeleteSurveys(_selectedSurveyIds);
        
        setState(() {
          _selectedSurveyIds = [];
          _isMultiSelectMode = false;
        });
        
        // 使用分页加载，避免一次性加载全部数据，跳过缓存强制刷新
        if (mounted) {
          await _loadData(silent: true, skipCache: true);
        }
        
        if (mounted) {
          showFToast(
            context: context,
            alignment: FToastAlignment.bottomRight,
            title: const Text('删除成功'),
            description: Text('已删除 $deletedCount 份问卷'),
            suffixBuilder: (context, entry) => IntrinsicHeight(
              child: FButton(
                style: context.theme.buttonStyles.primary.call,
                onPress: entry.dismiss.call,
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
            suffixBuilder: (context, entry) => IntrinsicHeight(
              child: FButton(
                style: context.theme.buttonStyles.primary.call,
                onPress: entry.dismiss.call,
                child: const Text('关闭'),
              ),
            ),
          );
        }
      }
    }
  }
}

class _SurveyStatsDialog extends StatefulWidget {
  final Survey survey;
  final ApiService apiService;
  final FDialogStyle style;
  final Animation<double> animation;

  const _SurveyStatsDialog({
    required this.survey,
    required this.apiService,
    required this.style,
    required this.animation,
  });

  @override
  State<_SurveyStatsDialog> createState() => _SurveyStatsDialogState();
}

class _SurveyStatsDialogState extends State<_SurveyStatsDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  int? _viewCount;
  int? _submitCount;
  DateTime? _lastViewTime;
  DateTime? _lastSubmitTime;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final stats = await widget.apiService.getSurveyStats(widget.survey.id);
      if (mounted) {
        setState(() {
          _viewCount = stats.viewCount;
          _submitCount = stats.submitCount;
          _lastViewTime = stats.lastViewTime;
          _lastSubmitTime = stats.lastSubmitTime;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '暂无记录';
    final local = dateTime.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
           '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSkeletonLine({double width = double.infinity, double height = 14}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final baseColor = isDark
        ? colorScheme.onSurface.withValues(alpha: 0.24)
        : colorScheme.primary.withValues(alpha: 0.22);
    final highlightColor = isDark
        ? colorScheme.onSurface.withValues(alpha: 0.42)
        : colorScheme.primary.withValues(alpha: 0.38);
    final fillColor = isDark
        ? colorScheme.onSurface.withValues(alpha: 0.18)
        : colorScheme.primary.withValues(alpha: 0.24);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_errorMessage != null) {
      content = Center(
        child: Text(
          _errorMessage!,
          textAlign: TextAlign.left,
          style: TextStyle(
            color: context.theme.colors.destructive,
          ),
        ),
      );
    } else if (_isLoading) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSkeletonLine(width: 220),
          const SizedBox(height: 16),
          _buildSkeletonLine(width: 220),
          const SizedBox(height: 16),
          _buildSkeletonLine(width: 260),
          const SizedBox(height: 16),
          _buildSkeletonLine(width: 260),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('总访问次数: ${_viewCount ?? 0}'),
          const SizedBox(height: 12),
          Text('总提交次数: ${_submitCount ?? 0}'),
          const SizedBox(height: 12),
          Text('最后访问时间: ${_formatDateTime(_lastViewTime)}'),
          const SizedBox(height: 12),
          Text('最后提交时间: ${_formatDateTime(_lastSubmitTime)}'),
        ],
      );
    }

    return FDialog(
      style: widget.style.call,
      animation: widget.animation,
      direction: Axis.horizontal,
      title: Text('${widget.survey.surveyName} - 统计信息'),
      body: SizedBox(
        width: 320,
        height: 110,
        child: content,
      ),
      actions: [
        FButton(
          style: context.theme.buttonStyles.outline.call,
          onPress: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}